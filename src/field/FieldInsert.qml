import QtQuick
import "../vim/motions.mjs" as Motions
import "../vim/keymap.mjs" as Keymap

// Insert mode: only what vim itself would intercept — esc, ctrl+w and ctrl+u,
// ctrl+j for a line break, the arrows — and the escape sequence (jk), whose
// leading keys type and are taken back when it completes.
Item {
  id: insertKeys

  property var field: null

  // Insert mode only intercepts what vim itself would.
  function handleInsertKey (event) {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    const plain = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0

    if (event.key === Qt.Key_Escape) {
      field.setMode("normal")
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_W) {
      field.remove(Motions.wordBackward(field.text, field.cursorPosition), field.cursorPosition)
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_U) {
      field.remove(0, field.cursorPosition)
      event.accepted = true
    } else if (ctrl && event.key === Qt.Key_J) {
      // A line break in a question; Enter is taken, it asks. A search is one
      // line, so there it does nothing.
      clearEscapePending()
      if (field.multiline) field.insert(field.cursorPosition, field.lineBreak)
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      // Down works from insert too, as vim's arrows do; within a question of
      // several lines, Up and Down move between its lines first.
      clearEscapePending()
      field.edits.moveLine(event.key === Qt.Key_Down, true)
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
    const step = Keymap.advance(field.escapePending, event.text, field.escapeSequences)

    if (!step.escaped) {
      field.escapePending = step.pending
      if (field.escapePending) escapeTimer.restart()
      else escapeTimer.stop()
      return
    }

    // Only take back keys that are still the ones we typed: a click or an edit
    // in between means this is no longer one run.
    const from = field.cursorPosition - step.strip
    const ours = from >= 0 && field.text.substring(from, field.cursorPosition) === field.escapePending
    clearEscapePending()
    if (!ours) return

    field.remove(from, field.cursorPosition)
    field.setMode("normal")
    event.accepted = true
  }

  function clearEscapePending () {
    field.escapePending = ""
    escapeTimer.stop()
  }

  // The run only holds while the keys arrive together; after the timeout a lone
  // `j` is just a `j`.
  Timer {
    id: escapeTimer

    interval: insertKeys.field ? insertKeys.field.escapeTimeout : 200
    onTriggered: insertKeys.field.escapePending = ""
  }
}
