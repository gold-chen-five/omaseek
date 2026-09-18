import QtQuick
import QtTest

// The panel's keys, caught in every mode before the field types anything:
// the session chords, retry, stop, the agent and mode switches, ctrl+t.
Item {
  width: 480
  height: 160

  FieldFixture {
    id: fixture
    anchors.fill: parent
  }

  FieldTestCase {
    name: "Field panel keys"
    field: fixture.field

    // The session keys are caught before the field types anything, in any mode.
    function test_the_session_chords_are_taken_from_both_modes() {
      fixture.nextSessions = 0
      fixture.closedSessions = 0
      typeText("half a question")

      keyClick(Qt.Key_N, Qt.ControlModifier)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(field.text, "half a question", "neither chord may reach the text")
      compare(fixture.nextSessions, 1)
      compare(fixture.closedSessions, 1)

      field.setMode("normal")
      keyClick(Qt.Key_N, Qt.ControlModifier)
      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(fixture.nextSessions, 2)
      compare(fixture.closedSessions, 2)
      compare(field.text, "half a question")
    }

    // Retry reaches the panel from either mode, and wears shift so that
    // normal mode's ctrl+r is still redo.
    function test_retry_is_a_panel_chord_and_redo_survives() {
      fixture.retries = 0
      typeText("abc")
      keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier)
      compare(field.text, "abc", "the chord may not reach the text")
      compare(fixture.retries, 1)

      field.setMode("normal")
      keyClick(Qt.Key_X)
      compare(field.text, "ab")
      keyClick(Qt.Key_U)
      compare(field.text, "abc")
      keyClick(Qt.Key_R, Qt.ControlModifier)
      compare(field.text, "ab", "plain ctrl+r is still redo")
      compare(fixture.retries, 1)
    }

    // q and esc stop a reply in normal mode; insert types q, and esc there only
    // leaves insert. With nothing being written, q does nothing and esc closes.
    function test_q_and_esc_stop_a_reply_in_normal_mode() {
      fixture.stops = 0
      fixture.cancels = 0
      field.stoppable = true
      typeText("q")
      compare(field.text, "q", "insert types q")
      keyClick(Qt.Key_Escape)
      compare(field.mode, "normal")
      compare(fixture.stops, 0, "the first esc only leaves insert")
      keyClick(Qt.Key_Q)
      compare(fixture.stops, 1)
      keyClick(Qt.Key_Escape)
      compare(fixture.stops, 2)
      compare(fixture.cancels, 0, "esc fixture.stops rather than closing the panel")
      compare(field.text, "q")

      field.stoppable = false
      keyClick(Qt.Key_Q)
      compare(fixture.stops, 2, "nothing to stop")
      compare(field.text, "q")
      keyClick(Qt.Key_Escape)
      compare(fixture.cancels, 1, "and esc closes as before")
    }

    // Shift makes a chord of its own: forgetting everything must not be one
    // slip away from forgetting one.
    function test_shift_separates_forget_all_from_forget_one() {
      fixture.closedSessions = 0
      fixture.clearedSessions = 0

      keyClick(Qt.Key_X, Qt.ControlModifier)
      compare(fixture.closedSessions, 1)
      compare(fixture.clearedSessions, 0)

      keyClick(Qt.Key_X, Qt.ControlModifier | Qt.ShiftModifier)
      compare(fixture.clearedSessions, 1)
      compare(fixture.closedSessions, 1, "ctrl+shift+x is not also ctrl+x")
      compare(field.text, "", "and neither reaches the text")
    }

    function test_shift_tab_switches_the_agent_and_tab_still_switches_halves() {
      fixture.agentSwitches = 0
      fixture.tabs = 0
      field.text = "half a question"
      keyClick(Qt.Key_Backtab)                        // as Qt delivers shift+tab
      compare(fixture.agentSwitches, 1, "from insert mode, without typing anything")
      compare(fixture.tabs, 0)
      compare(field.text, "half a question")
      field.setMode("normal")
      keyClick(Qt.Key_Backtab)
      compare(fixture.agentSwitches, 2, "and from normal mode")
      keyClick(Qt.Key_Tab)
      compare(fixture.tabs, 1, "tab alone is still the switch between search and ask")
    }

    function test_ctrl_t_translates_the_bar_without_leaving_insert_mode() {
      fixture.translated = []
      field.text = "what is ownership"
      field.cursorPosition = field.text.length
      compare(field.mode, "insert")
      keyClick(Qt.Key_T, Qt.ControlModifier)
      compare(fixture.translated, ["what is ownership"])
      compare(field.mode, "insert", "still typing")
      compare(field.text, "what is ownership", "and no t typed")
      field.setMode("normal")
      keyClick(Qt.Key_T, Qt.ControlModifier)
      compare(fixture.translated.length, 2, "normal mode too")
    }
  }
}
