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
  property int stops: 0
  property int retries: 0
  property int olderAsked: 0
  property int agentSwitches: 0
  property int tabs: 0
  property var translated: []
  property int cancels: 0
  property var opened: []

  Connections {
    target: field
    function onNextSessionRequested () { nextSessions++ }
    function onCloseSessionRequested () { closedSessions++ }
    function onClearSessionsRequested () { clearedSessions++ }
    function onStopRequested () { stops++ }
    function onCancelled () { cancels++ }
    function onLinkOpened (url) { opened = opened.concat([url]) }
    function onRetryRequested () { retries++ }
    function onHistoryPrevRequested () { olderAsked++ }
    function onAgentSwitchRequested () { agentSwitches++ }
    function onTabbed () { tabs++ }
    function onTranslateRequested (text) { translated = translated.concat([text]) }
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

    // gx opens the address under the cursor, as vim's does; g then anything
    // else is nothing, and does not leave a g waiting.
    function test_gx_opens_the_url_under_the_cursor() {
      opened = []
      setNormal("see docs.rs/tokio please", 7)
      keyClick(Qt.Key_G)
      keyClick(Qt.Key_X)
      compare(opened, ["https://docs.rs/tokio"])
      compare(field.text, "see docs.rs/tokio please", "x after g deletes nothing")

      setNormal("no address here", 3)
      keyClick(Qt.Key_G)
      keyClick(Qt.Key_X)
      compare(opened.length, 1, "nothing under the cursor, nothing opened")

      setNormal("https://example.org", 0)
      keyClick(Qt.Key_G)
      keyClick(Qt.Key_W)
      keyClick(Qt.Key_X)
      compare(opened.length, 1, "gw is nothing, and the x after it is a plain x")
      compare(field.text, "ttps://example.org")
    }

    // Retry reaches the panel from either mode, and wears shift so that
    // normal mode's ctrl+r is still redo.
    function test_retry_is_a_panel_chord_and_redo_survives() {
      retries = 0
      typeText("abc")
      keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier)
      compare(field.text, "abc", "the chord may not reach the text")
      compare(retries, 1)

      field.setMode("normal")
      keyClick(Qt.Key_X)
      compare(field.text, "ab")
      keyClick(Qt.Key_U)
      compare(field.text, "abc")
      keyClick(Qt.Key_R, Qt.ControlModifier)
      compare(field.text, "ab", "plain ctrl+r is still redo")
      compare(retries, 1)
    }

    // q and esc stop a reply in normal mode; insert types q, and esc there only
    // leaves insert. With nothing being written, q does nothing and esc closes.
    function test_q_and_esc_stop_a_reply_in_normal_mode() {
      stops = 0
      cancels = 0
      field.stoppable = true
      typeText("q")
      compare(field.text, "q", "insert types q")
      keyClick(Qt.Key_Escape)
      compare(field.mode, "normal")
      compare(stops, 0, "the first esc only leaves insert")
      keyClick(Qt.Key_Q)
      compare(stops, 1)
      keyClick(Qt.Key_Escape)
      compare(stops, 2)
      compare(cancels, 0, "esc stops rather than closing the panel")
      compare(field.text, "q")

      field.stoppable = false
      keyClick(Qt.Key_Q)
      compare(stops, 2, "nothing to stop")
      compare(field.text, "q")
      keyClick(Qt.Key_Escape)
      compare(cancels, 1, "and esc closes as before")
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

    function test_line_motions_keep_to_the_line_under_the_cursor() {
      setNormal("first\n  second line\nthird", 12)

      keyClick("0")
      compare(field.cursorPosition, 6)
      keyClick("$")
      compare(field.cursorPosition, 18, "the last character of this line, not of the text")
      keyClick(Qt.Key_Underscore, Qt.ShiftModifier)    // as a keyboard sends it
      compare(field.cursorPosition, 8)
      field.cursorPosition = 16
      keyClick("^")
      compare(field.cursorPosition, 8)
    }

    function test_a_count_on_dollar_and_underscore_reaches_lines_below() {
      setNormal("one\n  two\nthree", 1)

      keyClick("2")
      keyClick("_")
      compare(field.cursorPosition, 6)
      keyClick("2")
      keyClick("$")
      compare(field.cursorPosition, 14)
    }

    function test_d_dollar_and_D_stop_at_the_line_break() {
      setNormal("first line\nsecond", 5)
      keyClick("d")
      keyClick("$")
      compare(field.text, "first\nsecond")

      setNormal("first line\nsecond", 5)
      keyClick("D")
      compare(field.text, "first\nsecond")
    }

    function test_d_underscore_deletes_the_line() {
      setNormal("first\nsecond\nthird", 8)
      keyClick("d")
      keyClick("_")
      compare(field.text, "first\nthird")
    }

    function test_I_and_A_insert_at_this_lines_ends() {
      setNormal("first\n  second", 1)
      field.cursorPosition = 10
      keyClick("I")
      compare(field.cursorPosition, 8)
      field.setMode("normal")
      field.cursorPosition = 1
      keyClick("A")
      compare(field.cursorPosition, 5)
    }

    function test_up_on_the_first_line_walks_back_through_what_was_asked() {
      olderAsked = 0
      setNormal("first line\nsecond line", 15)       // on the second line

      keyClick(Qt.Key_Up)
      compare(olderAsked, 0, "a line above: the arrow moves to it")
      verify(field.cursorPosition < 11)

      keyClick(Qt.Key_Up)
      compare(olderAsked, 1, "none above: the arrow reaches for the question before")
    }

    function test_U_in_normal_mode_steps_back_and_a_capital_U_still_types() {
      olderAsked = 0
      field.normalChords = { previousAsked: "U" }
      setNormal("draft", 2)

      keyClick("U")
      compare(olderAsked, 1)
      keyClick("3")
      keyClick("U")
      compare(olderAsked, 4, "a count steps further back")

      field.setMode("insert")
      keyClick("U")
      compare(olderAsked, 4, "insert mode types it")
      verify(field.text.indexOf("U") !== -1)
      field.normalChords = ({})
    }

    function test_shift_tab_switches_the_agent_and_tab_still_switches_halves() {
      agentSwitches = 0
      tabs = 0
      field.text = "half a question"
      keyClick(Qt.Key_Backtab)                        // as Qt delivers shift+tab
      compare(agentSwitches, 1, "from insert mode, without typing anything")
      compare(tabs, 0)
      compare(field.text, "half a question")
      field.setMode("normal")
      keyClick(Qt.Key_Backtab)
      compare(agentSwitches, 2, "and from normal mode")
      keyClick(Qt.Key_Tab)
      compare(tabs, 1, "tab alone is still the switch between search and ask")
    }

    function test_h_and_l_stop_at_the_line_ends() {
      setNormal("first\nsecond", 6)                   // the start of the second line
      keyClick("h")
      compare(field.cursorPosition, 6, "h does not climb onto the line above")

      field.cursorPosition = 4                          // the last character of the first
      keyClick("l")
      compare(field.cursorPosition, 4, "l does not run onto the line below")

      keyClick("h")
      compare(field.cursorPosition, 3, "and both still move along the line")
    }

    function test_dl_at_the_end_of_a_line_still_takes_the_last_character() {
      setNormal("first\nsecond", 4)
      keyClick("d")
      keyClick("l")
      compare(field.text, "firs\nsecond")
    }

    function test_gt_translates_the_selection_and_gT_the_whole_bar() {
      translated = []
      field.normalChords = { translate: "g t", translateBar: "g T" }
      setNormal("what is ownership", 8)

      keyClick("v")                                   // select "ownership"
      for (let i = 0; i < 8; i++) keyClick("l")
      keyClick("g")
      keyClick("t")
      compare(translated, ["ownership"], "gt: the selection")
      compare(field.mode, "normal", "and visual mode ends")

      keyClick("g")
      keyClick("T")
      compare(translated, ["ownership", "what is ownership"], "gT: everything in the bar")

      keyClick("g")
      keyClick("t")
      compare(translated.length, 2, "gt with nothing selected translates nothing")
      compare(field.text, "what is ownership", "and neither edits the text")
      field.normalChords = ({})
    }
  }
}
