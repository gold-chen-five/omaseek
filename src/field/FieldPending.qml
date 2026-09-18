import QtQuick
import "../vim/motions.mjs" as Motions
import "../vim/textobjects.mjs" as TextObjects
import "../core/urls.mjs" as Urls

// The key a command was waiting for: the target after f/F/t/T and the ; and ,
// that repeat it, the character after r, the object after i/a, and gx's link.
Item {
  id: pending

  property var field: null

  // gx, as vim's: the URL or bare domain under the cursor, or the selection.
  // A pasted address opens without leaving the field for the results.
  function openLinkUnderCursor () {
    const url = field.mode === "visual" ? Urls.urlFromSelection(field.selectedText) : Urls.urlAt(field.text, field.cursorPosition)
    if (field.mode === "visual") field.setMode("normal")
    if (url) field.linkOpened(url)
  }

  function handlePendingFind (key) {
    const command = field.pendingFind
    field.pendingFind = ""
    const count = field.takeCount(1)
    const target = Motions.findInLine(field.text, field.cursorPosition, command, key, count, false)
    if (target >= 0) {
      field.lastFindCommand = command
      field.lastFindChar = key
      field.repeatFindReady = true
      field.currentFindHit = Motions.findMatchPosition(target, command)
    }
    field.edits.applyMotion(target, field.pendingOperator !== "")
  }

  function sameFindKind (a, b) {
    return (a === "f" || a === "F") ? (b === "f" || b === "F")
      : (a === "t" || a === "T") && (b === "t" || b === "T")
  }

  function repeatLastFind (command, count, rememberDirection) {
    if (!field.lastFindChar) return
    const target = Motions.findInLine(field.text, field.cursorPosition, command, field.lastFindChar, count, true)
    if (target >= 0) {
      if (rememberDirection) field.lastFindCommand = command
      field.repeatFindReady = true
      field.currentFindHit = Motions.findMatchPosition(target, command)
    } else {
      return
    }
    field.edits.applyMotion(target, field.pendingOperator !== "")
  }

  // r{char}: replace count characters without entering insert mode, leaving
  // the cursor on the last replacement. Like Vim, it fails at a line end.
  function handleReplace (key) {
    const count = field.pendingReplace
    field.pendingReplace = 0
    const from = field.cursorPosition
    const end = Motions.lineBounds(field.text, from).end
    if (count < 1 || from + count > end) return

    let value = ""
    for (let i = 0; i < count; i++) value += key
    field.remove(from, from + count)
    field.insert(from, value)
    field.cursorPosition = from + count - 1
    field.clampCursor()
  }

  // The key after i or a: diw, ci", da(. A missing pair drops the operator
  // rather than acting on something arbitrary, which is what vim does.
  function handleTextObject (key) {
    const scope = field.pendingTextObject
    field.pendingTextObject = ""

    const range = TextObjects.isTextObject(key)
      ? TextObjects.resolve(field.text, field.cursorPosition, scope, key)
      : null
    if (!range) {
      field.pendingOperator = ""
      return
    }

    if (field.mode === "visual") {
      field.visualAnchor = range.start
      field.cursorPosition = Math.max(range.start, range.end - 1)
      field.select(range.start, range.end)
      return
    }

    const operator = field.pendingOperator
    field.pendingOperator = ""
    if (operator) field.edits.applyOperator(operator, range.start, range.end)
  }
}
