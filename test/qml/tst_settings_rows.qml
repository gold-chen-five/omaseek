import QtQuick
import QtTest
import "../../src/components"

Item {
  width: 480
  height: 200

  SettingsRows { id: state }

  // Like SettingsPage: replacing the array recreates the delegate, including
  // the list cursor owned by its popup. Use enough options to scroll offscreen.
  Repeater {
    id: repeater
    model: state.rows
    delegate: ListView {
      required property var modelData
      width: 400
      height: 100
      clip: true
      model: modelData.options
      currentIndex: 0
      delegate: Text { required property string modelData; text: modelData; height: 20 }
      Keys.onPressed: event => {
        if (event.key === Qt.Key_J) currentIndex = Math.min(count - 1, currentIndex + 1)
        else if (event.key === Qt.Key_K) currentIndex = Math.max(0, currentIndex - 1)
        else return
        event.accepted = true
      }
    }
  }

  TestCase {
    name: "SettingsRows"
    when: windowShown

    function options(count) {
      const result = []
      for (let i = 0; i < count; i++) result.push("model-" + i)
      return result
    }

    function init() {
      state.held = false
      state.source = [{ options: options(40) }]
      tryCompare(repeater, "count", 1)
    }

    function test_discovery_cannot_reset_an_open_long_list() {
      const list = repeater.itemAt(0)
      state.held = true
      list.forceActiveFocus()
      for (let i = 0; i < 39; i++) keyClick(Qt.Key_J)
      compare(list.currentIndex, 39)

      state.source = [{ options: options(70) }]
      wait(20)
      compare(repeater.itemAt(0), list)
      compare(list.currentIndex, 39)
      keyClick(Qt.Key_J)
      compare(list.currentIndex, 39, "j at the end stays at the end")
      keyClick(Qt.Key_K)
      compare(list.currentIndex, 38)

      state.held = false
      tryVerify(() => repeater.itemAt(0).count === 70)
    }

    function test_latest_refresh_wins_after_close_not_during_selection() {
      const before = state.rows
      state.held = true
      state.source = [{ options: options(50) }]
      state.source = [{ options: options(60) }]
      state.held = false
      compare(state.rows, before, "the closing delegate is still alive this turn")
      tryVerify(() => state.rows === state.source)
      compare(state.rows[0].options.length, 60)
    }
  }
}
