import QtQuick
import QtTest

// While suggestions show under the bar, the arrows and vim's completion keys
// walk them; otherwise they are what they always were.
Item {
  width: 480
  height: 160

  FieldFixture {
    id: fixture
    anchors.fill: parent
  }

  FieldTestCase {
    name: "Field suggestions"
    field: fixture.field

    function cleanup() {
      field.completing = false
      field.multiline = true
    }

    function test_the_arrows_and_ctrl_n_ctrl_p_walk_the_list() {
      fixture.completionSteps = []
      fixture.nextSessions = 0
      field.multiline = false
      typeText("you")
      field.completing = true
      keyClick(Qt.Key_Down)
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_N, Qt.ControlModifier)
      keyClick(Qt.Key_P, Qt.ControlModifier)
      compare(fixture.completionSteps, [1, -1, 1, -1])
      compare(fixture.nextSessions, 0, "ctrl+n walks the list, not the sessions")
      compare(fixture.olderAsked, 0, "and ↑ is not the query before")
      compare(field.text, "you", "the keys type nothing")
    }

    function test_without_a_list_they_are_what_they_were() {
      fixture.completionSteps = []
      fixture.nextSessions = 0
      fixture.olderAsked = 0
      field.multiline = false
      typeText("you")
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_N, Qt.ControlModifier)
      compare(fixture.completionSteps, [])
      compare(fixture.olderAsked, 1, "↑ walks back through past searches")
      compare(fixture.nextSessions, 1, "ctrl+n is the session key")
    }

    function test_normal_mode_keeps_its_own_ctrl_n() {
      fixture.completionSteps = []
      fixture.nextSessions = 0
      field.completing = true
      setNormal("you", 1)
      keyClick(Qt.Key_N, Qt.ControlModifier)
      compare(fixture.completionSteps, [], "the list is insert mode's")
      compare(fixture.nextSessions, 1)
    }
  }
}
