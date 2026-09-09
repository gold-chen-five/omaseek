import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui

// Search input with a vim editing model on top of the kit's TextField.
//
// Ui.TextField descends from QtQuick Controls TextField, so cursorPosition,
// select(), remove(), insert() and undo()/redo() are all inherited — the vim
// layer is a key handler plus a small pending-state machine, not a reimplemented
// text editor.
//
// Normal/visual mode consumes printable keys so they don't land as text;
// insert mode lets everything through untouched.
Ui.TextField {
  id: field

  property string mode: "insert"          // insert | normal | visual
  property string register: ""            // vim's unnamed register

  // Pending state for multi-key sequences: 2dw, d3w, f{char}, ...
  property string pendingOperator: ""
  property string pendingFind: ""         // f/F/t/T awaiting its target char
  property int pendingCount: 0
  property string lastFindCommand: ""     // for ; and ,
  property string lastFindChar: ""
  property int visualAnchor: -1

  signal submitted()
  signal cancelled()                      // Esc from normal mode

  readonly property bool normalish: mode !== "insert"

  function setMode(next) {
    if (next === "normal" && mode === "insert")
      cursorPosition = Math.max(0, cursorPosition - 1)   // vim steps left on Esc
    if (next !== "visual") {
      visualAnchor = -1
      deselect()
    }
    mode = next
    clearPending()
    if (next === "normal") clampCursor()
  }

  function clearPending() {
    pendingOperator = ""
    pendingFind = ""
    pendingCount = 0
  }

  function takeCount(fallback) {
    var n = pendingCount > 0 ? pendingCount : fallback
    pendingCount = 0
    return n
  }

  // In normal mode the cursor sits ON a character, never past the last one.
  function clampCursor() {
    if (mode === "insert" || text.length === 0) return
    if (cursorPosition > text.length - 1) cursorPosition = text.length - 1
    if (cursorPosition < 0) cursorPosition = 0
  }

  // 0 = whitespace, 1 = word char, 2 = punctuation. WORD motions collapse 1 and 2.
  function charClass(index, big) {
    if (index < 0 || index >= text.length) return 0
    var c = text.charAt(index)
    if (c === " " || c === "\t") return 0
    if (big) return 1
    return /[A-Za-z0-9_]/.test(c) ? 1 : 2
  }

  function motionWordForward(pos, big) {
    var n = text.length
    if (pos >= n) return n
    var cls = charClass(pos, big)
    if (cls !== 0) while (pos < n && charClass(pos, big) === cls) pos++
    while (pos < n && charClass(pos, big) === 0) pos++
    return pos
  }

  function motionWordBackward(pos, big) {
    if (pos <= 0) return 0
    pos--
    while (pos > 0 && charClass(pos, big) === 0) pos--
    var cls = charClass(pos, big)
    while (pos > 0 && charClass(pos - 1, big) === cls) pos--
    return pos
  }

  function motionWordEnd(pos, big) {
    var n = text.length
    if (n === 0) return 0
    if (pos >= n - 1) return n - 1
    pos++
    while (pos < n && charClass(pos, big) === 0) pos++
    if (pos >= n) return n - 1
    var cls = charClass(pos, big)
    while (pos + 1 < n && charClass(pos + 1, big) === cls) pos++
    return pos
  }

  function motionFirstNonBlank() {
    for (var i = 0; i < text.length; i++)
      if (charClass(i, false) !== 0) return i
    return 0
  }

  function motionFind(pos, command, target) {
    var n = text.length
    var i
    if (command === "f" || command === "t") {
      for (i = pos + 1; i < n; i++)
        if (text.charAt(i) === target) return command === "f" ? i : i - 1
    } else {
      for (i = pos - 1; i >= 0; i--)
        if (text.charAt(i) === target) return command === "F" ? i : i + 1
    }
    return -1
  }

  function copyToClipboard(value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  // Applies a pending operator over [start, end). Inclusive motions pre-adjust end.
  function applyOperator(op, start, end) {
    if (start > end) { var swap = start; start = end; end = swap }
    start = Math.max(0, start)
    end = Math.min(text.length, end)
    if (start === end && op !== "c") return

    register = text.substring(start, end)
    if (op === "y") {
      copyToClipboard(register)
      cursorPosition = start
      clampCursor()
      return
    }

    copyToClipboard(register)
    remove(start, end)
    cursorPosition = start
    if (op === "c") setMode("insert")
    else clampCursor()
  }

  // A motion resolved to a target index: either moves the cursor, extends the
  // visual selection, or feeds the pending operator.
  function applyMotion(target, inclusive) {
    if (target < 0) { clearPending(); return }
    if (pendingOperator !== "") {
      var op = pendingOperator
      pendingOperator = ""
      applyOperator(op, cursorPosition, inclusive ? target + 1 : target)
      return
    }
    cursorPosition = Math.max(0, Math.min(text.length, target))
    if (mode === "visual") select(visualAnchor, cursorPosition)
    else clampCursor()
  }

  function operateOnVisual(op) {
    var start = Math.min(visualAnchor, cursorPosition)
    var end = Math.max(visualAnchor, cursorPosition) + 1
    visualAnchor = -1
    deselect()
    mode = "normal"
    applyOperator(op, start, end)
  }

  function paste(after) {
    if (!register) return
    var at = after ? Math.min(text.length, cursorPosition + 1) : cursorPosition
    insert(at, register)
    cursorPosition = at + register.length - 1
    clampCursor()
  }

  onModeChanged: if (mode !== "visual") deselect()

  cursorDelegate: Rectangle {
    // Block cursor in normal/visual mode, thin bar in insert — the mode is
    // readable from the cursor alone, without checking the indicator.
    width: field.normalish ? Math.max(2, metrics.averageCharacterWidth) : Math.max(1, Style.space(1))
    color: field.normalish ? Color.menu.selectedText : field.foreground
    opacity: field.normalish ? 0.55 : 1.0
    radius: 1
    FontMetrics { id: metrics; font: field.font }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var isEnter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter

    if (isEnter) {
      field.submitted()
      event.accepted = true
      return
    }

    // ---- insert mode: stay out of the way ----
    if (mode === "insert") {
      if (event.key === Qt.Key_Escape) {
        setMode("normal")
        event.accepted = true
      } else if (ctrl && event.key === Qt.Key_W) {
        var wordStart = motionWordBackward(cursorPosition, false)
        remove(wordStart, cursorPosition)
        event.accepted = true
      } else if (ctrl && event.key === Qt.Key_U) {
        remove(0, cursorPosition)
        event.accepted = true
      }
      return                                  // everything else types normally
    }

    // ---- normal / visual mode ----
    if (event.key === Qt.Key_Escape) {
      if (mode === "visual") setMode("normal")
      else if (pendingOperator !== "" || pendingCount > 0 || pendingFind !== "") clearPending()
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

    var key = event.text
    if (!key || key.length !== 1) { event.accepted = true; return }
    event.accepted = true

    // f/F/t/T consume the next keystroke as their target.
    if (pendingFind !== "") {
      var command = pendingFind
      pendingFind = ""
      lastFindCommand = command
      lastFindChar = key
      var found = cursorPosition
      var repeat = takeCount(1)
      for (var r = 0; r < repeat; r++) {
        var next = motionFind(found, command, key)
        if (next < 0) { found = -1; break }
        found = next
      }
      applyMotion(found, pendingOperator !== "")
      return
    }

    // Counts: 0 is a motion unless it continues a count.
    if (key >= "1" && key <= "9" || (key === "0" && pendingCount > 0)) {
      pendingCount = pendingCount * 10 + parseInt(key, 10)
      return
    }

    var count = takeCount(1)
    var i
    var pos = cursorPosition

    switch (key) {
    // ---- mode changes ----
    case "i": setMode("insert"); return
    case "a": cursorPosition = Math.min(text.length, pos + 1); setMode("insert"); return
    case "I": cursorPosition = motionFirstNonBlank(); setMode("insert"); return
    case "A": cursorPosition = text.length; setMode("insert"); return
    case "v":
      if (mode === "visual") { setMode("normal") }
      else { visualAnchor = pos; mode = "visual"; select(pos, pos + 1) }
      return

    // ---- motions ----
    case "h": applyMotion(Math.max(0, pos - count), false); return
    case "l": applyMotion(Math.min(text.length, pos + count), false); return
    case "0": applyMotion(0, false); return
    case "^": applyMotion(motionFirstNonBlank(), false); return
    case "$": applyMotion(text.length, false); return
    case "w": for (i = 0; i < count; i++) pos = motionWordForward(pos, false); applyMotion(pos, false); return
    case "W": for (i = 0; i < count; i++) pos = motionWordForward(pos, true); applyMotion(pos, false); return
    case "b": for (i = 0; i < count; i++) pos = motionWordBackward(pos, false); applyMotion(pos, false); return
    case "B": for (i = 0; i < count; i++) pos = motionWordBackward(pos, true); applyMotion(pos, false); return
    case "e": for (i = 0; i < count; i++) pos = motionWordEnd(pos, false); applyMotion(pos, true); return
    case "E": for (i = 0; i < count; i++) pos = motionWordEnd(pos, true); applyMotion(pos, true); return
    case "f": case "F": case "t": case "T":
      pendingFind = key
      pendingCount = count > 1 ? count : 0
      return
    case ";": case ",":
      if (!lastFindCommand) return
      var command2 = lastFindCommand
      if (key === ",")
        command2 = { f: "F", F: "f", t: "T", T: "t" }[lastFindCommand]
      applyMotion(motionFind(pos, command2, lastFindChar), pendingOperator !== "")
      return

    // ---- operators ----
    case "d": case "c": case "y":
      if (mode === "visual") { operateOnVisual(key); return }
      if (pendingOperator === key) {          // dd / cc / yy: the whole line
        pendingOperator = ""
        applyOperator(key, 0, text.length)
        return
      }
      pendingOperator = key
      return
    case "D": applyOperator("d", pos, text.length); return
    case "C": applyOperator("c", pos, text.length); return
    case "Y": applyOperator("y", 0, text.length); return

    // ---- single-key edits ----
    case "x":
      if (mode === "visual") { operateOnVisual("d"); return }
      applyOperator("d", pos, Math.min(text.length, pos + count))
      return
    case "X": applyOperator("d", Math.max(0, pos - count), pos); return
    case "s": applyOperator("c", pos, Math.min(text.length, pos + count)); return
    case "S": register = text; copyToClipboard(register); clear(); setMode("insert"); return
    case "p": paste(true); return
    case "P": paste(false); return
    case "u": undo(); clampCursor(); return
    }
  }
}
