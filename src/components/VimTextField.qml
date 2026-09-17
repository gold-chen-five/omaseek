import QtQuick
import Quickshell
import QtQuick.Controls
import qs.Commons
import "../lib/motions.mjs" as Motions
import "../lib/textobjects.mjs" as TextObjects
import "../lib/keymap.mjs" as Keymap
import "../lib/keybinds.mjs" as Keybinds
import "../lib/urls.mjs" as Urls
import "chord.js" as Chord
import "measure.js" as Measure

// The search field with a vim editing model: the mode machine and key dispatch.
// Cursor arithmetic lives in lib/motions.mjs, where it runs under test.
//
// A TextArea, not a TextField: a question can hold line breaks, which a
// TextInput strips. It never wraps — a long line scrolls sideways inside the
// frame Search.qml draws around it, as the single-line field did — so only a
// Ctrl+J and o/O add rows. The frame is the container's because the field scrolls.
TextArea {
  id: field

  property color foreground: Color.foreground
  property color accent: Color.accent
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property bool multiline: false            // AI mode: line-opening keys work
  property bool stoppable: false            // a reply is being written: q and esc stop it
  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), foreground, accent)
  readonly property real lineHeight: contentHeight / Math.max(1, lineCount)

  padding: 0
  background: null
  wrapMode: TextEdit.NoWrap
  selectByMouse: true
  color: foreground
  selectionColor: Style.selectionFillFor(foreground, accent)
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  property string mode: "insert"            // insert | normal | visual
  property string register: ""              // vim's unnamed register

  // Pending state for multi-key sequences: 2dw, d3w, f{char}, r{char}, ...
  property int operatorCount: 1
  property string pendingOperator: ""
  property string pendingFind: ""           // f/F/t/T awaiting its target
  property int pendingReplace: 0            // r awaiting its character; value is the count
  property string pendingTextObject: ""     // i/a awaiting its object, as in diw
  property int pendingCount: 0
  property bool pendingG: false             // g awaiting its second key: gx
  property string lastFindCommand: ""       // for ; and ,
  property string lastFindChar: ""
  property bool repeatFindReady: false       // clever-f: fa, then f/F walk the same target
  property int currentFindHit: -1            // actual match; t/T leave the cursor beside it
  readonly property var findMatches: repeatFindReady
    ? Motions.matchingCharsInLine(text, currentFindHit, lastFindChar) : []
  property bool visualLinewise: false
  property int visualCursor: 0
  property int visualAnchor: -1

  // Insert-mode escape sequence (vim's `inoremap jk <Esc>`); empty turns it off.
  property var escapeSequences: []
  property int escapeTimeout: 200
  readonly property string lineBreak: "\n"      // what line-opening commands insert
  property string escapePending: ""          // sequence keys typed so far

  // The panel keys, already parsed, by action id. Checked before mode dispatch
  // so rebinding search moves it off Enter, and so a session key works from
  // insert mode without typing anything.
  property var chords: Keybinds.panelChords(null)

  signal submitted()
  signal cancelled()                        // Esc from normal mode
  signal steppedDown()                      // j / Down: the results are the "line" below
  signal historyPrevRequested()             // Up in the one-line search field: an older query
  signal historyNextRequested()             // Down there: back toward what was being typed
  signal requestedSettings()                // Ctrl+S (or Ctrl+,) in any mode
  signal tabbed()                           // Tab in any mode: the panel switches search <-> ai
  signal newSessionRequested()              // the new-session chord: start over
  signal nextSessionRequested()             // the next saved conversation
  signal closeSessionRequested()            // forget this conversation
  signal clearSessionsRequested()           // forget all of them
  signal linkOpened(string url)             // gx: the URL under the cursor, or selected
  signal stopRequested()                    // stop the reply being written
  signal retryRequested()                   // ask the last question again

  readonly property bool normalish: mode !== "insert"

  // In the order they are checked, so the first match wins. Ctrl+, was the
  // original settings binding and still works; Shift+Tab always switches,
  // because left alone it would move focus.
  function panelCommand (chord) {
    if (chord === "") return ""
    if (chord === chords.settings || chord === "C-,") return "settings"
    if (chord === chords.newSession) return "newSession"
    if (chord === chords.nextSession) return "nextSession"
    if (chord === chords.clearSessions) return "clearSessions"
    if (chord === chords.closeSession) return "closeSession"
    if (chord === chords.retryAnswer) return "retryAnswer"
    if (chord === chords.search) return "submit"
    if (chord === chords.switchMode || chord === "Backtab") return "toggleMode"
    return ""
  }

  function raisePanel (command) {
    switch (command) {
    case "settings":      requestedSettings(); break
    case "newSession":    newSessionRequested(); break
    case "nextSession":   nextSessionRequested(); break
    case "clearSessions": clearSessionsRequested(); break
    case "closeSession":  closeSessionRequested(); break
    case "retryAnswer":   retryRequested(); break
    // Both leave the field for good; a half-typed escape sequence goes with it.
    case "submit":        clearEscapePending(); submitted(); break
    case "toggleMode":    clearEscapePending(); tabbed(); break
    }
  }

  function setMode (next) {
    if (next === "normal" && mode === "insert") {
      cursorPosition = Motions.insertExit(text, cursorPosition)
    }
    if (next !== "visual") {
      if (mode === "visual" && visualLinewise) cursorPosition = visualCursor
      visualLinewise = false
      visualAnchor = -1
      deselect()
    }
    mode = next
    clearPending()
    if (next === "normal") clampCursor()
  }

  // Enter from a reading pane exactly as the matching normal-mode command
  // would: i inserts at the cursor, while a advances one character first.
  function enterInsert (motion) {
    clearPending()
    handleNormalKey(motion === "a" ? "a" : "i")
  }

  function clearPending () {
    pendingOperator = ""
    operatorCount = 1
    pendingFind = ""
    pendingReplace = 0
    pendingTextObject = ""
    pendingCount = 0
    pendingG = false
    repeatFindReady = false
    currentFindHit = -1
  }

  // gx, as vim's: the URL or bare domain under the cursor, or the selection.
  // A pasted address opens without leaving the field for the results.
  function openLinkUnderCursor () {
    const url = mode === "visual" ? Urls.urlFromSelection(selectedText) : Urls.urlAt(text, cursorPosition)
    if (mode === "visual") setMode("normal")
    if (url) linkOpened(url)
  }

  function takeCount (fallback) {
    const count = pendingCount > 0 ? pendingCount : fallback
    pendingCount = 0
    return count
  }

  // A line down or up within the text; down from its last line leaves the
  // field for what is below it, as it always has.
  //
  // In search mode the field is one line, so the arrows have no line to reach:
  // there they walk the queries searched before, the way a shell's history does.
  // j and k never do — j into the results is how the reader gets to them.
  function moveLine (down, arrow) {
    const pos = mode === "visual" && visualLinewise ? visualCursor : cursorPosition
    const next = down ? Motions.lineDown(text, pos) : Motions.lineUp(text, pos)
    if (next !== -1) {
      applyMotion(next, false)
      return
    }
    if (mode === "visual") return
    if (arrow && !multiline) {
      if (down) field.historyNextRequested()
      else field.historyPrevRequested()
      return
    }
    if (down) field.steppedDown()
  }

  // The panel replaces what was typed while walking the query history. Set
  // through here so the cursor lands at the end, as it does in a shell.
  function setQuery (value) {
    text = value
    cursorPosition = length
    clampCursor()
  }

  function openLine (below) {
    if (!multiline || mode !== "normal" || pendingOperator !== "") {
      clearPending()
      return
    }
    const bounds = Motions.lineBounds(text, cursorPosition)
    const at = below ? bounds.end : bounds.start
    insert(at, lineBreak)
    cursorPosition = below ? at + lineBreak.length : at
    setMode("insert")
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

  function operateLines (operator, count) {
    const range = Motions.lineRange(text, cursorPosition, count)
    // Neovim's nostartofline default keeps this column after linewise d.
    const column = cursorPosition - range.start
    let from = range.start
    let to = range.end
    // cc keeps the final separator so the replacement stays on its own line.
    if (operator === "c" && to > from && text[to - 1] === "\n") to--
    register = text.substring(from, to)
    copyToClipboard(register)
    if (operator !== "y") {
      // Deleting the final line also removes the separator before it.
      if (operator === "d" && to === text.length && from > 0 && (to === from || text[to - 1] !== "\n")) from--
      remove(from, to)
    }
    if (operator === "d") {
      cursorPosition = Motions.positionAtColumn(text, Math.min(range.start, text.length), column)
      return
    }
    cursorPosition = Math.min(range.start, text.length)
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
    if (mode === "visual" && visualLinewise) {
      visualCursor = cursorPosition
      const range = visualRange()
      select(range.start, range.end)
    } else if (mode === "visual") select(visualAnchor, cursorPosition)
    else clampCursor()
  }

  function visualRange () {
    const pos = visualLinewise ? visualCursor : cursorPosition
    const start = Math.min(visualAnchor, pos)
    const end = Math.max(visualAnchor, pos)
    return visualLinewise
      ? { start: Motions.lineBounds(text, start).start, end: Motions.lineRange(text, end).end }
      : { start, end: Math.min(text.length, end + 1) }
  }

  function operateOnVisual (operator) {
    if (visualLinewise) {
      const range = visualRange()
      const count = text.substring(range.start, range.end).split("\n").length
        - (range.end > range.start && text[range.end - 1] === "\n" ? 1 : 0)
      setMode("normal")
      cursorPosition = range.start
      operateLines(operator, count)
      return
    }
    const start = Math.min(visualAnchor, cursorPosition)
    const end = Math.max(visualAnchor, cursorPosition) + 1
    visualAnchor = -1
    deselect()
    mode = "normal"
    applyOperator(operator, start, end)
  }

  // p and P: the text given, else the system clipboard — where every yank in
  // the panel lands, so a word yanked from the answer puts here — else the
  // register, should the clipboard not be readable.
  function put (after, value) {
    const at = after && text.length > 0 ? Math.min(text.length, cursorPosition + 1) : cursorPosition
    const before = length
    cursorPosition = at
    if (value) insert(at, value)
    else if (canPaste) field.paste()
    else if (register) insert(at, register)
    if (length === before) return
    if (!multiline) flatten(at, at + length - before)
    cursorPosition = at + length - before - 1
    clampCursor()
  }

  // A search is one line: breaks in what was put become spaces.
  function flatten (from, to) {
    const chunk = getText(from, to)
    const flat = chunk.replace(/[\r\n\u2028\u2029]+/g, " ")
    if (flat === chunk) return
    remove(from, to)
    insert(from, flat)
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
    } else if (ctrl && event.key === Qt.Key_J) {
      // A line break in a question; Enter is taken, it asks. A search is one
      // line, so there it does nothing.
      clearEscapePending()
      if (multiline) insert(cursorPosition, lineBreak)
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      // Down works from insert too, as vim's arrows do; within a question of
      // several lines, Up and Down move between its lines first.
      clearEscapePending()
      moveLine(event.key === Qt.Key_Down, true)
      event.accepted = true
    } else if (plain && Keymap.isTypedKey(event.text)) {
      handleEscapeSequence(event)             // types normally unless it closes the sequence
    } else {
      clearEscapePending()                    // arrows, Backspace and the rest break the run
    }
  }

  // Leading keys type and are taken back when the sequence completes, as in vim;
  // the closing key never reaches the field.
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
    const count = takeCount(1)
    const target = Motions.findInLine(text, cursorPosition, command, key, count, false)
    if (target >= 0) {
      lastFindCommand = command
      lastFindChar = key
      repeatFindReady = true
      currentFindHit = Motions.findMatchPosition(target, command)
    }
    applyMotion(target, pendingOperator !== "")
  }

  function sameFindKind (a, b) {
    return (a === "f" || a === "F") ? (b === "f" || b === "F")
      : (a === "t" || a === "T") && (b === "t" || b === "T")
  }

  function repeatLastFind (command, count, rememberDirection) {
    if (!lastFindChar) return
    const target = Motions.findInLine(text, cursorPosition, command, lastFindChar, count, true)
    if (target >= 0) {
      if (rememberDirection) lastFindCommand = command
      repeatFindReady = true
      currentFindHit = Motions.findMatchPosition(target, command)
    } else {
      return
    }
    applyMotion(target, pendingOperator !== "")
  }

  function characterRect (pos) {
    return Measure.characterRect(field, pos, metrics.averageCharacterWidth)
  }

  // r{char}: replace count characters without entering insert mode, leaving
  // the cursor on the last replacement. Like Vim, it fails at a line end.
  function handleReplace (key) {
    const count = pendingReplace
    pendingReplace = 0
    const from = cursorPosition
    const end = Motions.lineBounds(text, from).end
    if (count < 1 || from + count > end) return

    let value = ""
    for (let i = 0; i < count; i++) value += key
    remove(from, from + count)
    insert(from, value)
    cursorPosition = from + count - 1
    clampCursor()
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
    const pos = mode === "visual" && visualLinewise ? visualCursor : cursorPosition
    const step = (motion, big) => Motions.repeat(at => motion(text, at, big), count, pos)
    if ("fFtT;,".indexOf(key) === -1) repeatFindReady = false

    switch (key) {
    // leaving the field — the result list is the next line down
    case "j":
    case "k":
      if ((mode === "visual" && !visualLinewise) || pendingOperator !== "") {
        clearPending()                      // dj and friends mean nothing here
        return
      }
      for (let i = 0; i < count; i++) moveLine(key === "j", false)
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
    case "o": openLine(true); return
    case "O": openLine(false); return
    case "I": cursorPosition = Motions.firstNonBlank(text); setMode("insert"); return
    case "A": cursorPosition = text.length; setMode("insert"); return
    case "V":
      if (mode === "visual" && visualLinewise) {
        setMode("normal")
      } else {
        if (mode !== "visual") visualAnchor = pos
        visualLinewise = true
        mode = "visual"
        applyMotion(pos, false)
      }
      return
    case "v":
      if (mode === "visual" && visualLinewise) {
        visualLinewise = false
        cursorPosition = pos
        select(visualAnchor, pos + 1)
      } else if (mode === "visual") {
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
      if (repeatFindReady && sameFindKind(lastFindCommand, key)) {
        repeatLastFind(key, count, true)
        return
      }
      pendingFind = key
      pendingCount = count > 1 ? count : 0
      repeatFindReady = false
      return
    case ";": case ",": {
      if (!lastFindCommand) return
      const command = key === "," ? Motions.flipFind(lastFindCommand) : lastFindCommand
      repeatLastFind(command, count, false)
      return
    }

    // operators
    case "d": case "c": case "y":
      if (mode === "visual") {
        operateOnVisual(key)
      } else if (pendingOperator === key) {   // dd / cc / yy act on the line
        pendingOperator = ""
        operateLines(key, count * operatorCount)
        operatorCount = 1
      } else {
        pendingOperator = key
        operatorCount = count
      }
      return
    case "D": applyOperator("d", pos, text.length); return
    case "C": applyOperator("c", pos, text.length); return
    case "Y": operateLines("y", count); return

    // single-key edits
    case "r":
      if (mode !== "visual") pendingReplace = count
      return
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
    case "p": case "P":
      if (mode === "visual") {                // the selection is replaced
        const range = visualRange()
        const start = range.start
        const end = range.end
        setMode("normal")
        remove(start, end)
        cursorPosition = start
        put(false, "")
      } else {
        put(key === "p", "")
      }
      return
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

  FontMetrics { id: metrics; font: field.font }

  Repeater {
    model: field.findMatches

    MatchHighlight {
      required property int modelData

      head: field.characterRect(modelData)
      current: modelData === field.currentFindHit
      foreground: field.foreground
      accent: field.accent
    }
  }

  cursorDelegate: Rectangle {
    width: field.normalish ? Math.max(2, metrics.averageCharacterWidth) : Math.max(1, Style.space(1))
    color: field.normalish ? Color.menu.selectedText : field.foreground
    opacity: field.normalish ? 0.55 : 1.0
    radius: 1

  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0

    // The panel's own keys, in every mode, before the field types anything.
    const command = field.panelCommand(Chord.of(event))
    if (command !== "") {
      field.raisePanel(command)
      event.accepted = true
      return
    }

    if (mode === "insert") {
      handleInsertKey(event)
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (mode === "visual") setMode("normal")
      else if (pendingOperator || pendingCount > 0 || pendingFind || repeatFindReady || pendingReplace > 0 || pendingTextObject || pendingG) clearPending()
      // While a reply is being written, esc stops it rather than closing the
      // panel; the one after that closes it.
      else if (field.stoppable) field.stopRequested()
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

    if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      moveLine(event.key === Qt.Key_Down, true)
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

    if (pendingReplace > 0) {
      handleReplace(key)
      return
    }

    if (pendingTextObject !== "") {
      handleTextObject(key)
      return
    }

    // g's only command here is gx; anything else after g means nothing.
    if (pendingG) {
      pendingG = false
      pendingCount = 0
      if (key === "x" && pendingOperator === "") openLinkUnderCursor()
      return
    }
    if (key === "g" && pendingOperator === "") {
      pendingG = true
      return
    }

    // Vim's q records a macro, which this field deliberately lacks; here it
    // stops the reply being written, and otherwise does nothing.
    if (key === "q") {
      clearPending()
      if (field.stoppable) field.stopRequested()
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
