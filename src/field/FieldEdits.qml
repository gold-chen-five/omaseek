import QtQuick
import Quickshell
import "../shared/vim/motions.mjs" as Motions

// What the keys do to the text: an operator over a range, a whole line, a
// motion applied (moving, stretching the selection, or feeding the operator
// waiting on it), the visual range, put, a line opened, and moving between
// lines — past the first or last, into the query and question history.
Item {
  id: edits

  property var field: null

  // A line down or up within the text; down from its last line leaves the
  // field for what is below it, as it always has.
  //
  // In search mode the field is one line, so the arrows have no line to reach:
  // there they walk the queries searched before, the way a shell's history does.
  // In ask mode they reach the questions asked before once past the first line.
  // j and k never do — j into the results is how the reader gets to them.
  function moveLine (down, arrow) {
    const pos = field.mode === "visual" && field.visualLinewise ? field.visualCursor : field.cursorPosition
    const next = down ? Motions.lineDown(field.text, pos) : Motions.lineUp(field.text, pos)
    if (next !== -1) {
      applyMotion(next, false)
      return
    }
    if (field.mode === "visual") return
    // Past the first or last line the arrows walk what was asked or searched
    // before, as a shell's history does; in the one-line search field that is
    // every arrow press. The panel turns a Down with nothing newer to show into
    // a step down to the results, as j always is.
    if (arrow) {
      if (down) field.historyNextRequested()
      else field.historyPrevRequested()
      return
    }
    if (down) field.steppedDown()
  }

  function openLine (below) {
    if (!field.multiline || field.mode !== "normal" || field.pendingOperator !== "") {
      field.clearPending()
      return
    }
    const bounds = Motions.lineBounds(field.text, field.cursorPosition)
    const at = below ? bounds.end : bounds.start
    field.insert(at, field.lineBreak)
    field.cursorPosition = below ? at + field.lineBreak.length : at
    field.setMode("insert")
  }

  function copyToClipboard (value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  // Applies a pending operator over [start, end).
  function applyOperator (operator, start, end) {
    const from = Math.max(0, Math.min(start, end))
    const to = Math.min(field.text.length, Math.max(start, end))
    if (from === to && operator !== "c") return

    field.register = field.text.substring(from, to)
    copyToClipboard(field.register)

    if (operator === "y") {
      field.cursorPosition = from
      field.clampCursor()
      return
    }

    field.remove(from, to)
    field.cursorPosition = from
    if (operator === "c") field.setMode("insert")
    else field.clampCursor()
  }

  function operateLines (operator, count) {
    const range = Motions.lineRange(field.text, field.cursorPosition, count)
    // Neovim's nostartofline default keeps this column after linewise d.
    const column = field.cursorPosition - range.start
    let from = range.start
    let to = range.end
    // cc keeps the final separator so the replacement stays on its own line.
    if (operator === "c" && to > from && field.text[to - 1] === "\n") to--
    field.register = field.text.substring(from, to)
    copyToClipboard(field.register)
    if (operator !== "y") {
      // Deleting the final line also removes the separator before it.
      if (operator === "d" && to === field.text.length && from > 0 && (to === from || field.text[to - 1] !== "\n")) from--
      field.remove(from, to)
    }
    if (operator === "d") {
      field.cursorPosition = Motions.positionAtColumn(field.text, Math.min(range.start, field.text.length), column)
      return
    }
    field.cursorPosition = Math.min(range.start, field.text.length)
    if (operator === "c") field.setMode("insert")
    else field.clampCursor()
  }

  // gg and G: to a line's first non-blank. They are linewise in vim, so an
  // operator takes every whole line between the cursor and there (dG, ygg).
  function jumpToLine (target) {
    if (field.pendingOperator === "") {
      applyMotion(target, false)
      return
    }
    const operator = field.pendingOperator
    field.pendingOperator = ""
    field.operatorCount = 1
    const from = Math.min(field.cursorPosition, target)
    const to = Math.max(field.cursorPosition, target)
    const lines = field.text.substring(from, to).split("\n").length
    field.cursorPosition = Motions.lineBounds(field.text, from).start
    operateLines(operator, lines)
  }

  // A resolved motion target either moves the cursor, extends the visual
  // selection, or feeds the operator waiting on it.
  function applyMotion (target, inclusive) {
    if (target < 0) {                       // a find that missed
      field.clearPending()
      return
    }
    if (field.pendingOperator !== "") {
      const operator = field.pendingOperator
      field.pendingOperator = ""
      applyOperator(operator, field.cursorPosition, inclusive ? target + 1 : target)
      return
    }
    field.cursorPosition = Math.max(0, Math.min(field.text.length, target))
    if (field.mode === "visual" && field.visualLinewise) {
      field.visualCursor = field.cursorPosition
      const range = visualRange()
      field.select(range.start, range.end)
    } else if (field.mode === "visual") field.select(field.visualAnchor, field.cursorPosition)
    else field.clampCursor()
  }

  function visualRange () {
    const pos = field.visualLinewise ? field.visualCursor : field.cursorPosition
    const start = Math.min(field.visualAnchor, pos)
    const end = Math.max(field.visualAnchor, pos)
    return field.visualLinewise
      ? { start: Motions.lineBounds(field.text, start).start, end: Motions.lineRange(field.text, end).end }
      : { start, end: Math.min(field.text.length, end + 1) }
  }

  function operateOnVisual (operator) {
    if (field.visualLinewise) {
      const range = visualRange()
      const count = field.text.substring(range.start, range.end).split("\n").length
        - (range.end > range.start && field.text[range.end - 1] === "\n" ? 1 : 0)
      field.setMode("normal")
      field.cursorPosition = range.start
      operateLines(operator, count)
      return
    }
    const start = Math.min(field.visualAnchor, field.cursorPosition)
    const end = Math.max(field.visualAnchor, field.cursorPosition) + 1
    field.visualAnchor = -1
    field.deselect()
    field.mode = "normal"
    applyOperator(operator, start, end)
  }

  // p and P: the text given, else the system clipboard — where every yank in
  // the panel lands, so a word yanked from the answer puts here — else the
  // register, should the clipboard not be readable.
  function put (after, value) {
    const at = after && field.text.length > 0 ? Math.min(field.text.length, field.cursorPosition + 1) : field.cursorPosition
    const before = field.length
    field.cursorPosition = at
    if (value) field.insert(at, value)
    else if (field.canPaste) field.paste()
    else if (field.register) field.insert(at, field.register)
    if (field.length === before) return
    if (!field.multiline) flatten(at, at + field.length - before)
    field.cursorPosition = at + field.length - before - 1
    field.clampCursor()
  }

  // A search is one line: breaks in what was put become spaces.
  function flatten (from, to) {
    const chunk = field.getText(from, to)
    const flat = chunk.replace(/[\r\n\u2028\u2029]+/g, " ")
    if (flat === chunk) return
    field.remove(from, to)
    field.insert(from, flat)
  }
}
