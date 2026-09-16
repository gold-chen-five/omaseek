import QtQuick
import QtTest
import "../../src/components"

Item {
  width: 480
  height: 160

  VimTextField {
    id: field
    anchors.fill: parent
    multiline: true
    escapeSequences: ["jk"]
    escapeTimeout: 1000
  }

  property int nextSessions: 0
  property int closedSessions: 0
  property int clearedSessions: 0

  Connections {
    target: field
    function onNextSessionRequested () { nextSessions++ }
    function onCloseSessionRequested () { closedSessions++ }
    function onClearSessionsRequested () { clearedSessions++ }
  }

  TestCase {
    name: "VimTextField"
    when: windowShown

    function typeText(text) {
      for (let i = 0; i < text.length; i++) keyClick(text[i])
    }

    function setNormal(text, cursor) {
      field.text = text
      field.setMode("normal")
      field.cursorPosition = cursor
    }

    function init() {
      field.text = ""
      field.cursorPosition = 0
      field.setMode("insert")
      field.forceActiveFocus()
      tryCompare(field, "activeFocus", true)
    }

    // The session keys are caught before the field types anything, in any mode.
    function test_the_session_chords_are_taken_from_both_modes() {
      nextSessions = 0
      closedSessions = 0
      typeText("half a question")

      keyClick(Qt.Key_N, Qt.ControlModifier)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(field.text, "half a question", "neither chord may reach the text")
      compare(nextSessions, 1)
      compare(closedSessions, 1)

      field.setMode("normal")
      keyClick(Qt.Key_N, Qt.ControlModifier)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(nextSessions, 2)
      compare(closedSessions, 2)
      compare(field.text, "half a question")
    }

    // Shift makes a chord of its own: forgetting everything must not be one
    // slip away from forgetting one.
    function test_shift_separates_forget_all_from_forget_one() {
      closedSessions = 0
      clearedSessions = 0

      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(closedSessions, 1)
      compare(clearedSessions, 0)

      keyClick(Qt.Key_X, Qt.ControlModifier | Qt.ShiftModifier)
      compare(clearedSessions, 1)
      compare(closedSessions, 1, "ctrl+shift+x is not also ctrl+x")
      compare(field.text, "", "and neither reaches the text")
    }

    function test_jk_keeps_an_empty_new_line_reachable() {
      typeText("first")
      keyClick(Qt.Key_J, Qt.ControlModifier)

      compare(field.text, "first\n")
      compare(field.cursorPosition, 6)

      keyClick("j")
      keyClick("k")

      compare(field.text, "first\n")
      compare(field.mode, "normal")
      compare(field.cursorPosition, 6)

      keyClick("k")
      compare(field.cursorPosition, 0)
      keyClick("j")
      compare(field.cursorPosition, 6)
    }

    function test_o_opens_a_line_below_and_inserts_there() {
      setNormal("first\nthird", 1)

      keyClick("o")

      compare(field.text, "first\n\nthird")
      compare(field.mode, "insert")
      compare(field.cursorPosition, 6)
      typeText("second")
      compare(field.text, "first\nsecond\nthird")
    }

    function test_O_opens_a_line_above_and_inserts_there() {
      setNormal("first\nthird", 7)

      keyClick("O")

      compare(field.text, "first\n\nthird")
      compare(field.mode, "insert")
      compare(field.cursorPosition, 6)
      typeText("second")
      compare(field.text, "first\nsecond\nthird")
    }

    function test_dd_preserves_the_column_on_the_next_line() {
      setNormal("first\n  second\n  third", 10)

      keyClick("d")
      keyClick("d")

      compare(field.text, "first\n  third")
      compare(field.mode, "normal")
      compare(field.cursorPosition, 10)
    }

    function test_dd_on_the_final_line_preserves_the_column_above() {
      setNormal("  first\nsecond", 12)

      keyClick("d")
      keyClick("d")

      compare(field.text, "  first")
      compare(field.mode, "normal")
      compare(field.cursorPosition, 4)
    }

    function test_dd_clamps_the_column_to_a_shorter_surviving_line() {
      setNormal("xy\nlong current", 11)

      keyClick("d")
      keyClick("d")

      compare(field.text, "xy")
      compare(field.mode, "normal")
      compare(field.cursorPosition, 1)
    }
  }
}
