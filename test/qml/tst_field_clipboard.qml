import QtQuick
import QtTest

// Copy and paste as the agents' terminals have them: ctrl+shift+c copies,
// ctrl+v or ctrl+shift+v pastes where the cursor is, and ctrl+c is New
// session, selection or not.
Item {
  width: 480
  height: 160

  FieldFixture {
    id: fixture
    anchors.fill: parent
  }

  // What the tests put on the clipboard, copied from here as any app would.
  TextEdit {
    id: source
    visible: false
  }

  FieldTestCase {
    name: "Field clipboard"
    field: fixture.field

    function clip(text) {
      source.text = text
      source.selectAll()
      source.copy()
      field.forceActiveFocus()
    }

    function test_ctrl_c_is_a_new_session_even_over_a_selection() {
      fixture.newSessions = 0
      field.register = ""
      typeText("half a question")
      keyClick(Qt.Key_C, Qt.ControlModifier)
      compare(fixture.newSessions, 1)
      field.select(0, 4)
      keyClick(Qt.Key_C, Qt.ControlModifier)
      compare(fixture.newSessions, 2, "a selection does not make it copy")
      compare(field.register, "")
      compare(field.text, "half a question")
    }

    function test_ctrl_shift_c_copies_a_visual_selection_as_y_does() {
      field.register = ""
      setNormal("copy these words", 5)
      keyClick(Qt.Key_V)
      keyClick(Qt.Key_E)
      keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
      compare(field.register, "these")
      compare(field.mode, "normal", "copied, as y leaves visual mode")
    }

    function test_ctrl_shift_c_copies_a_mouse_selection_and_keeps_it() {
      field.register = ""
      typeText("pick this out")
      field.select(5, 9)
      keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
      compare(field.register, "this")
      compare(field.selectedText, "this", "still selected, as any text box leaves it")
      compare(field.mode, "insert")
    }

    function test_ctrl_shift_c_copies_and_never_starts_a_session() {
      fixture.newSessions = 0
      field.register = ""
      typeText("nothing selected")
      keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
      compare(fixture.newSessions, 0)
      compare(field.register, "")
      field.select(0, 7)
      keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
      compare(field.register, "nothing")
    }

    function test_ctrl_v_and_ctrl_shift_v_paste_at_the_cursor_and_keep_typing() {
      clip("world")
      typeText("hello ")
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(field.text, "hello world")
      compare(field.cursorPosition, 11)
      compare(field.mode, "insert")
      keyClick(Qt.Key_V, Qt.ControlModifier | Qt.ShiftModifier)
      compare(field.text, "hello worldworld")
      typeText("!")
      compare(field.text, "hello worldworld!", "typing carries on after it")
    }

    function test_a_paste_replaces_a_mouse_selection() {
      clip("new")
      typeText("the old one")
      field.select(4, 7)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(field.text, "the new one")
      compare(field.cursorPosition, 7)
    }

    function test_a_search_is_one_line_so_a_pasted_break_is_a_space() {
      clip("two\nlines")
      field.multiline = false
      keyClick(Qt.Key_V, Qt.ControlModifier)
      field.multiline = true
      compare(field.text, "two lines")
      compare(field.cursorPosition, 9)
    }

    function test_normal_mode_pastes_where_P_would_and_u_takes_it_back() {
      clip("b")
      setNormal("ac", 1)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(field.text, "abc")
      compare(field.mode, "normal")
      keyClick(Qt.Key_U)
      compare(field.text, "ac", "one u for the paste")
    }
  }
}
