import QtQuick
import QtTest
import "../../src/components"

Item {
  width: 400
  height: 60

  property int pickedIndex: -1
  property int starts: 0

  SessionTabs {
    id: tabs
    anchors.fill: parent
    sessions: [{ id: "a", title: "newest" }, { id: "b", title: "older" }, { id: "c", title: "oldest" }]
    pending: ["c"]
    current: 1

    onPicked: index => pickedIndex = index
    onStarted: starts++
  }

  TestCase {
    name: "SessionTabs"
    when: windowShown

    // The squares, in the order they are laid out; children order is not it.
    function squares() {
      const strip = tabs.children[0]
      const found = []
      for (let i = 0; i < strip.children.length; i++) {
        const item = strip.children[i]
        if (item.text !== undefined) found.push(item)
      }
      return found.sort((a, b) => a.x - b.x)
    }

    function init() {
      pickedIndex = -1
      starts = 0
      tabs.current = 1
    }

    function test_one_square_per_conversation_and_one_to_start_another() {
      const row = squares()
      compare(row.length, 4, "three conversations and the + square")
      compare(row[0].text, "1", "1 is the newest")
      compare(row[2].text, "3")
      compare(row[3].text, "+")
      compare(row[1].selected, true, "the conversation on screen is filled")
      compare(row[0].selected, false)
      compare(row[3].selected, false)
      compare(row[1].tooltipText, "older", "hovering names the conversation")
    }

    function test_a_conversation_still_being_answered_says_so() {
      const row = squares()
      compare(row[2].answering, true, "its answer is still on its way")
      compare(row[2].tooltipText, "oldest — still answering")
      compare(row[0].answering, false)
      compare(row[1].answering, false)
    }

    function test_an_unsaved_conversation_lights_the_plus_instead() {
      tabs.current = -1
      const row = squares()
      compare(row[3].selected, true)
      for (let i = 0; i < 3; i++) compare(row[i].selected, false)
    }

    function test_clicking_a_square_asks_for_that_conversation() {
      const row = squares()
      mouseClick(row[2])
      compare(pickedIndex, 2)
      compare(starts, 0)

      mouseClick(row[3])
      compare(starts, 1, "+ starts a new one rather than picking")
      compare(pickedIndex, 2)
    }
  }
}
