import QtQuick
import QtTest

// The field's commands beyond motion: gx, gt and gT, walking back through what
// was asked, and the keys a command waits for.
Item {
  width: 480
  height: 160

  FieldFixture {
    id: fixture
    anchors.fill: parent
  }

  FieldTestCase {
    name: "Field commands"
    field: fixture.field

    // gx opens the address under the cursor, as vim's does; g then anything
    // else is nothing, and does not leave a g waiting.
    function test_gx_opens_the_url_under_the_cursor() {
      fixture.opened = []
      setNormal("see docs.rs/tokio please", 7)
      keyClick(Qt.Key_G)
      keyClick(Qt.Key_X)
      compare(fixture.opened, ["https://docs.rs/tokio"])
      compare(field.text, "see docs.rs/tokio please", "x after g deletes nothing")

      setNormal("no address here", 3)
      keyClick(Qt.Key_G)
      keyClick(Qt.Key_X)
      compare(fixture.opened.length, 1, "nothing under the cursor, nothing fixture.opened")

      setNormal("https://example.org", 0)
      keyClick(Qt.Key_G)
      keyClick(Qt.Key_W)
      keyClick(Qt.Key_X)
      compare(fixture.opened.length, 1, "gw is nothing, and the x after it is a plain x")
      compare(field.text, "ttps://example.org")
    }

    function test_up_on_the_first_line_walks_back_through_what_was_asked() {
      fixture.olderAsked = 0
      setNormal("first line\nsecond line", 15)       // on the second line

      keyClick(Qt.Key_Up)
      compare(fixture.olderAsked, 0, "a line above: the arrow moves to it")
      verify(field.cursorPosition < 11)

      keyClick(Qt.Key_Up)
      compare(fixture.olderAsked, 1, "none above: the arrow reaches for the question before")
    }

    function test_U_in_normal_mode_steps_back_and_a_capital_U_still_types() {
      fixture.olderAsked = 0
      field.normalChords = { previousAsked: "U" }
      setNormal("draft", 2)

      keyClick("U")
      compare(fixture.olderAsked, 1)
      keyClick("3")
      keyClick("U")
      compare(fixture.olderAsked, 4, "a count steps further back")

      field.setMode("insert")
      keyClick("U")
      compare(fixture.olderAsked, 4, "insert mode types it")
      verify(field.text.indexOf("U") !== -1)
      field.normalChords = ({})
    }

    function test_gt_translates_the_selection_and_gT_the_whole_bar() {
      fixture.translated = []
      field.normalChords = { translate: "g t", translateBar: "g T" }
      setNormal("what is ownership", 8)

      keyClick("v")                                   // select "ownership"
      for (let i = 0; i < 8; i++) keyClick("l")
      keyClick("g")
      keyClick("t")
      compare(fixture.translated, ["ownership"], "gt: the selection")
      compare(field.mode, "normal", "and visual mode ends")

      keyClick("g")
      keyClick("T")
      compare(fixture.translated, ["ownership", "what is ownership"], "gT: everything in the bar")

      keyClick("g")
      keyClick("t")
      compare(fixture.translated.length, 2, "gt with nothing selected translates nothing")
      compare(field.text, "what is ownership", "and neither edits the text")
      field.normalChords = ({})
    }

    // Every path the key handling spans, one each: the key a command waits for
    // (i/a objects, f and its repeats, r), the operators, the register and put.
    function test_text_objects_finds_replace_and_put_through_the_parts() {
      setNormal("say \"hello world\" now", 6)
      keyClick("d"); keyClick("i"); keyClick("w")
      compare(field.text, "say \" world\" now", "diw takes the word under the cursor")

      setNormal("say \"hello world\" now", 6)
      keyClick("c"); keyClick("i"); keyClick("\"")
      compare(field.text, "say \"\" now", "ci\" empties the quotes")
      compare(field.mode, "insert")

      setNormal("a-b-c-d", 0)
      keyClick("f"); keyClick("-")
      compare(field.cursorPosition, 1)
      keyClick(";")
      compare(field.cursorPosition, 3, "; repeats the find")
      keyClick(",")
      compare(field.cursorPosition, 1, ", reverses it")

      setNormal("abcd", 1)
      keyClick("2"); keyClick("r"); keyClick("x")
      compare(field.text, "axxd", "2rx replaces two")

      setNormal("abcd", 0)
      keyClick("x")
      compare(field.text, "bcd")

      setNormal("one two", 0)
      keyClick("y"); keyClick("w")
      compare(field.register, "one ", "yw fills the register")
      keyClick("$")
      field.put(true, "!")
      compare(field.text, "one two!", "put after the cursor")

      setNormal("first line", 3)
      keyClick("c"); keyClick("c")
      compare(field.text, "", "cc empties the line")
      compare(field.mode, "insert")

      setNormal("gone", 1)
      keyClick("S")
      compare(field.text, "")
      compare(field.mode, "insert", "S clears and inserts")
    }

    // Vim undoes a change whole: ciw, what was typed, and the jk that left
    // insert are one u. Qt's undo made the j that jk takes back its own step.
    function test_u_undoes_a_whole_change_including_jk() {
      setNormal("rust ownership", 6)
      keyClick("c")
      keyClick("i")
      keyClick("w")
      typeText("borrowing")
      keyClick("j")
      keyClick("k")
      compare(field.mode, "normal")
      compare(field.text, "rust borrowing")

      keyClick("u")
      compare(field.text, "rust ownership", "back to before ciw, not to a stray j")
      compare(field.cursorPosition, 5)

      keyClick(Qt.Key_R, Qt.ControlModifier)
      compare(field.text, "rust borrowing")
      compare(field.cursorPosition, 5, "redo, too, lands where the change began")

      keyClick("x")
      keyClick("x")
      keyClick("u")
      compare(field.text, "rust orrowing", "each x is a step of its own: one u gives back only the second")
    }

    function test_ga_hands_off_the_bar_or_the_selection_and_gA_everything() {
      fixture.handedOff = []
      field.normalChords = { handoff: "g a", handoffAll: "g A" }
      setNormal("what is ownership", 8)

      keyClick("g")
      keyClick("a")
      compare(fixture.handedOff, [["what is ownership", false]], "ga: everything in the bar")

      keyClick("v")                                   // select "ownership"
      for (let i = 0; i < 8; i++) keyClick("l")
      keyClick("g")
      keyClick("a")
      compare(fixture.handedOff[1], ["ownership", false], "ga in visual mode: the selection")
      compare(field.mode, "normal", "and visual mode ends")

      keyClick("g")
      keyClick("A")
      compare(fixture.handedOff[2], ["what is ownership", true], "gA: the bar, with everything below")
      compare(field.text, "what is ownership", "and none of them edits the text")
      field.normalChords = ({})
    }

    function test_gd_gj_and_gs_take_the_bar_or_the_selection() {
      fixture.barCommands = []
      field.normalChords = { askNow: "g d", askAbout: "g j", searchFor: "g s" }
      setNormal("what is ownership", 8)

      keyClick("g"); keyClick("d")
      keyClick("g"); keyClick("j")
      keyClick("g"); keyClick("s")
      compare(fixture.barCommands, [["ask", "what is ownership"], ["askAbout", "what is ownership"],
                                    ["search", "what is ownership"]], "all of the bar")

      keyClick("v")                                   // select "ownership"
      for (let i = 0; i < 8; i++) keyClick("l")
      keyClick("g"); keyClick("d")
      compare(fixture.barCommands[3], ["askSelection", "ownership"], "gd in visual mode: the selection")
      compare(field.mode, "normal", "and visual mode ends")
      compare(field.text, "what is ownership", "none of them edits the bar")
      field.normalChords = ({})
    }
  }
}
