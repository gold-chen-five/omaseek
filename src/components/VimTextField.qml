import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "../lib/motions.mjs" as Motions
import "../lib/textobjects.mjs" as TextObjects
import "../lib/keymap.mjs" as Keymap

// Search input with a vim editing model.
//
// Ui.TextField descends from QtQuick Controls TextField, so cursorPosition,
// select(), remove(), insert() and undo()/redo() are inherited — this file adds
// the mode machine and key dispatch, while the cursor arithmetic lives in
// lib/motions.mjs where it can be tested without a running shell.
//
// Normal and visual mode consume printable keys so they never land as text;
// insert mode passes everything through untouched apart from the escape
// sequence — `jk` by default, which is the one insert-mode binding vim users
// reach for and the one this field has to fake.
Ui.TextField {
  id: field

  property string mode: "insert"            // insert | normal | visual
  property string register: ""              // vim's unnamed register

  // Pending state for multi-key sequences: 2dw, d3w, f{char}, ...
  property string pendingOperator: ""
  property string pendingFind: ""           // f/F/t/T awaiting its target
  property string pendingTextObject: ""     // i/a awaiting its object, as in diw
  property int pendingCount: 0
  property string lastFindCommand: ""       // for ; and ,
  property string lastFindChar: ""
  property int visualAnchor: -1

  // The insert-mode escape sequence, vim's `inoremap jk <Esc>`. Which keys and
  // how long they may take comes from the user's config (see Search.qml); an
  // empty list turns the whole thing off.
  property var escapeSequences: []
  property int escapeTimeout: 200
  property string escapePending: ""          // sequence keys typed so far

  signal submitted()
  signal cancelled()                        // Esc from normal mode
  signal steppedDown()                      // j / Down: the results are the "line" below
  signal requestedSettings()                // Ctrl+S (or Ctrl+,) in any mode
  signal tabbed()                           // Tab in any mode: the panel switches search <-> ai
  signal newSessionRequested()              // Ctrl+N: start the conversation over

  readonly property bool normalish: mode !== "insert"

  function setMode (next) {
    if (next === "normal" && mode === "insert") {
      cursorPosition = Math.max(0, cursorPosition - 1)   // vim steps left on Esc
    }
    if (next !== "visual") {
      visualAnchor = -1
      deselect()
    }
    mode = next
    clearPending()
    if (next === "normal") clampCursor()
  }

  function clearPending () {
    pendingOperator = ""
    pendingFind = ""
    pendingTextObject = ""
    pendingCount = 0
  }

  function takeCount (fallback) {
    const count = pendingCount > 0 ? pendingCount : fallback
    pendingCount = 0
    return count
  }

  function clampCursor () {
    if (mode === "insert") return
    cursorPosition = Motions.clampToLine(text, cursorPosition)
  }

  function copyToClipboard (value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  // Applies a pending operator over [start, end).
  function applyOperator (operator, start, end) {
    const from = Math.max(0, Math.min(start, end))
    const to = Math.min(text.length, Math.max(start, end))
    if (from === to && operator !== "c") return

    register = text.substring(from, to)
    copyToClipboard(register)

    if (operator === "y") {
      cursorPosition = from
      clampCursor()
      return
    }

    remove(from, to)
    cursorPosition = from
    if (operator === "c") setMode("insert")
    else clampCursor()
  }

  // A resolved motion target either moves the cursor, extends the visual
  // selection, or feeds the operator waiting on it.
  function applyMotion (target, inclusive) {
    if (target < 0) {                       // a find that missed
      clearPending()
      return
    }
    if (pendingOperator !== "") {
      const operator = pendingOperator
      pendingOperator = ""
      applyOperator(operator, cursorPosition, inclusive ? target + 1 : target)
      return
    }
    cursorPosition = Math.max(0, Math.min(text.length, target))
    if (mode === "visual") select(visualAnchor, cursorPosition)
    else clampCursor()
  }

  function operateOnVisual (operator) {
    const start = Math.min(visualAnchor, cursorPosition)
    const end = Math.max(visualAnchor, cursorPosition) + 1
    visualAnchor = -1
    deselect()
    mode = "normal"
    applyOperator(operator, start, end)
  }

  function paste (after) {
    if (!register) return
    const at = after ? Math.min(text.length, cursorPosition + 1) : cursorPosition
    insert(at, register)
    cursorPosition = at + register.length - 1
    clampCursor()
  }

  // Insert mode only intercepts what vim itself would.
  function handleInsertKey (event) {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    const plain = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0

    if (event.key === Qt.Key_Escape) {
      setMode("normal")
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_W) {
      remove(Motions.wordBackward(text, cursorPosition), cursorPosition)
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_U) {
      remove(0, cursorPosition)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      // The results stay put after Enter, so the way down has to work from
      // insert mode as well — vim's arrows do, and nobody wants Esc first.
      clearEscapePending()
      field.steppedDown()
      event.accepted = true
    } else if (plain && Keymap.isTypedKey(event.text)) {
      handleEscapeSequence(event)             // types normally unless it closes the sequence
    } else {
      clearEscapePending()                    // arrows, Backspace and the rest break the run
    }
  }

  // The leading keys of the sequence type as normal and are taken back once it
  // completes — vim shows that `j` too, then removes it — while the closing key
  // is swallowed before it ever reaches the field.
  function handleEscapeSequence (event) {
    const step = Keymap.advance(escapePending, event.text, escapeSequences)

    if (!step.escaped) {
      escapePending = step.pending
      if (escapePending) escapeTimer.restart()
      else escapeTimer.stop()
      return
    }

    // Only take back keys that are still the ones we typed: a click or an edit
    // in between means this is no longer one run.
    const from = cursorPosition - step.strip
    const ours = from >= 0 && text.substring(from, cursorPosition) === escapePending
    clearEscapePending()
    if (!ours) return

    remove(from, cursorPosition)
    setMode("normal")
    event.accepted = true
  }

  function clearEscapePending () {
    escapePending = ""
    escapeTimer.stop()
  }

  function handlePendingFind (key) {
    const command = pendingFind
    pendingFind = ""
    lastFindCommand = command
    lastFindChar = key

    let target = cursorPosition
    const count = takeCount(1)
    for (let i = 0; i < count; i++) {
      const next = Motions.find(text, target, command, key)
      if (next < 0) {
        target = -1
        break
      }
      target = next
    }
    applyMotion(target, pendingOperator !== "")
  }

  // The key after i or a: diw, ci", da(. A missing pair drops the operator
  // rather than acting on something arbitrary, which is what vim does.
  function handleTextObject (key) {
    const scope = pendingTextObject
    pendingTextObject = ""

    const range = TextObjects.isTextObject(key)
      ? TextObjects.resolve(text, cursorPosition, scope, key)
      : null
    if (!range) {
      pendingOperator = ""
      return
    }

    if (mode === "visual") {
      visualAnchor = range.start
      cursorPosition = Math.max(range.start, range.end - 1)
      select(range.start, range.end)
      return
    }

    const operator = pendingOperator
    pendingOperator = ""
    if (operator) applyOperator(operator, range.start, range.end)
  }

  function handleNormalKey (key) {
    const count = takeCount(1)
    const pos = cursorPosition
    const step = (motion, big) => Motions.repeat(at => motion(text, at, big), count, pos)

    switch (key) {
    // leaving the field — the result list is the next line down
    case "j":
      if (mode === "visual" || pendingOperator !== "") {
        clearPending()                      // dj and friends mean nothing on one line
        return
      }
      field.steppedDown()
      return

    // modes
    case "i":
      if (pendingOperator !== "" || mode === "visual") { pendingTextObject = "i"; return }
      setMode("insert")
      return
    case "a":
      if (pendingOperator !== "" || mode === "visual") { pendingTextObject = "a"; return }
      cursorPosition = Math.min(text.length, pos + 1)
      setMode("insert")
      return
    case "I": cursorPosition = Motions.firstNonBlank(text); setMode("insert"); return
    case "A": cursorPosition = text.length; setMode("insert"); return
    case "v":
      if (mode === "visual") {
        setMode("normal")
      } else {
        visualAnchor = pos
        mode = "visual"
        select(pos, pos + 1)
      }
      return

    // motions
    case "h": applyMotion(Math.max(0, pos - count), false); return
    case "l": applyMotion(Math.min(text.length, pos + count), false); return
    case "0": applyMotion(0, false); return
    case "^": applyMotion(Motions.firstNonBlank(text), false); return
    case "$": applyMotion(text.length, false); return
    case "w": applyMotion(step(Motions.wordForward, false), false); return
    case "W": applyMotion(step(Motions.wordForward, true), false); return
    case "b": applyMotion(step(Motions.wordBackward, false), false); return
    case "B": applyMotion(step(Motions.wordBackward, true), false); return
    case "e": applyMotion(step(Motions.wordEnd, false), true); return
    case "E": applyMotion(step(Motions.wordEnd, true), true); return
    case "f": case "F": case "t": case "T":
      pendingFind = key
      pendingCount = count > 1 ? count : 0
      return
    case ";": case ",": {
      if (!lastFindCommand) return
      const command = key === "," ? Motions.flipFind(lastFindCommand) : lastFindCommand
      applyMotion(Motions.find(text, pos, command, lastFindChar), pendingOperator !== "")
      return
    }

    // operators
    case "d": case "c": case "y":
      if (mode === "visual") {
        operateOnVisual(key)
      } else if (pendingOperator === key) {   // dd / cc / yy act on the line
        pendingOperator = ""
        applyOperator(key, 0, text.length)
      } else {
        pendingOperator = key
      }
      return
    case "D": applyOperator("d", pos, text.length); return
    case "C": applyOperator("c", pos, text.length); return
    case "Y": applyOperator("y", 0, text.length); return

    // single-key edits
    case "x":
      if (mode === "visual") operateOnVisual("d")
      else applyOperator("d", pos, Math.min(text.length, pos + count))
      return
    case "X": applyOperator("d", Math.max(0, pos - count), pos); return
    case "s": applyOperator("c", pos, Math.min(text.length, pos + count)); return
    case "S":
      register = text
      copyToClipboard(register)
      clear()
      setMode("insert")
      return
    case "p": paste(true); return
    case "P": paste(false); return
    case "u": undo(); clampCursor(); return
    }
  }

  onModeChanged: {
    if (mode !== "visual") deselect()
    clearEscapePending()                      // a half-typed sequence dies with the mode
  }

  // The run only holds while the keys arrive together; after the timeout a lone
  // `j` is just a `j`.
  Timer {
    id: escapeTimer

    interval: field.escapeTimeout
    onTriggered: field.escapePending = ""
  }

  // Block cursor in normal/visual, thin bar in insert — the mode is readable
  // from the cursor alone, without checking the indicator.
  cursorDelegate: Rectangle {
    width: field.normalish ? Math.max(2, metrics.averageCharacterWidth) : Math.max(1, Style.space(1))
    color: field.normalish ? Color.menu.selectedText : field.foreground
    opacity: field.normalish ? 0.55 : 1.0
    radius: 1

    FontMetrics { id: metrics; font: field.font }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0

    // Reaches the settings page from either mode, so it is never a question of
    // which one you happen to be in. Ctrl+, still works: it was the original
    // binding, and muscle memory outlives a rename.
    if (ctrl && (event.key === Qt.Key_S || event.key === Qt.Key_Comma)) {
      field.requestedSettings()
      event.accepted = true
      return
    }

    // Same reason: a new conversation should not need you to leave the field
    // you are typing the next question in.
    if (ctrl && event.key === Qt.Key_N) {
      field.newSessionRequested()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      clearEscapePending()
      field.submitted()
      event.accepted = true
      return
    }

    // Tab never types or moves focus here — it is the panel's switch between
    // searching and asking, from either mode, so it is taken before the modes.
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      clearEscapePending()
      field.tabbed()
      event.accepted = true
      return
    }

    if (mode === "insert") {
      handleInsertKey(event)
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (mode === "visual") setMode("normal")
      else if (pendingOperator || pendingCount > 0 || pendingFind || pendingTextObject) clearPending()
      else field.cancelled()
      event.accepted = true
      return
    }

    if (ctrl && event.key === Qt.Key_R) {
      redo()
      clampCursor()
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Down) {
      field.steppedDown()
      event.accepted = true
      return
    }

    const key = event.text
    event.accepted = true
    if (!key || key.length !== 1) return

    if (pendingFind !== "") {
      handlePendingFind(key)
      return
    }

    if (pendingTextObject !== "") {
      handleTextObject(key)
      return
    }

    // 0 is a motion unless it is continuing a count.
    const isCountDigit = (key >= "1" && key <= "9") || (key === "0" && pendingCount > 0)
    if (isCountDigit) {
      pendingCount = pendingCount * 10 + parseInt(key, 10)
      return
    }

    handleNormalKey(key)
  }
}
