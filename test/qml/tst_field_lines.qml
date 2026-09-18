import QtQuick
import QtTest

// Lines and motions in a question of several lines: jk, o and O, dd, the line
// ends, h and l, I and A, gg and G.
Item {
  width: 480
  height: 160

  FieldFixture {
    id: fixture
    anchors.fill: parent
  }

  FieldTestCase {
    name: "Field lines and motions"
    field: fixture.field

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

    function test_gg_and_G_reach_the_first_and_last_line() {
      setNormal("  first\nsecond\n  third", 10)

      keyClick("G")
      compare(field.cursorPosition, 17, "G: the last line's first non-blank")
      keyClick("g")
      keyClick("g")
      compare(field.cursorPosition, 2, "gg: the first line's")
      keyClick("2")
      keyClick("G")
      compare(field.cursorPosition, 8, "2G: the second line")
      keyClick("3")
      keyClick("g")
      keyClick("g")
      compare(field.cursorPosition, 17, "3gg: the third")
      compare(field.text, "  first\nsecond\n  third")
    }

    function test_dG_and_dgg_take_whole_lines() {
      setNormal("first\nsecond\nthird", 8)
      keyClick("d")
      keyClick("G")
      compare(field.text, "first")

      setNormal("first\nsecond\nthird", 8)
      keyClick("d")
      keyClick("g")
      keyClick("g")
      compare(field.text, "third")
      compare(field.mode, "normal")
    }
  }
}
