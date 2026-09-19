import QtQuick
import "../shared/vim/undo.mjs" as Undo

// u and ctrl+r, as vim's: a step per change rather than per keystroke. The
// field marks a boundary after each normal-mode key that leaves it out of
// insert, and on leaving insert; everything between two boundaries — ciw, the
// word typed, the jk taken back — undoes as one. The rules are vim/undo.mjs.
Item {
  id: history

  property var field: null
  property var state: Undo.start("")

  Component.onCompleted: state = Undo.start(field.text)

  function mark () {
    state = Undo.record(state, field.text)
  }

  function undo (count) { apply(Undo.undo(state, field.text, count)) }
  function redo (count) { apply(Undo.redo(state, field.text, count)) }

  function apply (step) {
    if (!step) return
    const at = Undo.changeStart(field.text, step.text)
    state = step.state
    field.text = step.text
    field.cursorPosition = Math.min(at, field.text.length)
    field.clampCursor()
  }
}
