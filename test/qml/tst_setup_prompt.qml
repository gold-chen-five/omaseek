import QtQuick
import QtTest
import "../../src/engine"

// The setup page with real keys. Shown on opening, it waits below the bar: j
// from the bar gives it the keyboard, k gives it back, and only then is a
// button chosen, h and l move between them, Enter takes one and esc is Not now.
Item {
  width: 640
  height: 360

  TextInput { id: bar; width: 200; height: 20 }

  SetupPrompt {
    id: prompt
    y: 30
    width: 600
    notSetUp: true
    setupPath: "ctrl+s → Search → SearXNG"
    property int confirms: 0
    property int cancels: 0
    property int ups: 0
    onConfirmed: confirms++
    onCancelled: cancels++
    onSteppedUp: ups++
  }

  TestCase {
    name: "Setup prompt"
    when: windowShown

    function init() {
      prompt.confirms = 0; prompt.cancels = 0; prompt.ups = 0
      bar.forceActiveFocus()
    }

    function test_not_set_up_offers_one_searxng_button() {
      compare(prompt.buttons, ["Not now", "SearXNG"], "the terminal asks Podman or Docker")
      prompt.notSetUp = false
      compare(prompt.buttons, ["Not now", "Start it"], "stopped: start it as it was made")
      prompt.notSetUp = true
    }

    function test_h_and_l_choose_and_enter_takes_it() {
      prompt.open()
      tryVerify(() => prompt.activeFocus)
      compare(prompt.selectedIndex, 1, "lands on SearXNG")
      keyClick("l")
      compare(prompt.selectedIndex, 1, "l stops at the end")
      keyClick("h")
      compare(prompt.selectedIndex, 0)
      keyClick("l")
      keyClick(Qt.Key_Return)
      compare(prompt.confirms, 1)
      compare(prompt.cancels, 0)
    }

    function test_the_page_leaves_the_keyboard_in_the_bar_until_asked() {
      verify(bar.activeFocus, "the bar keeps the keyboard")
      verify(!prompt.activeFocus)
      keyClick(Qt.Key_Return)
      compare(prompt.confirms, 0, "Enter in the bar is not the page's")
      prompt.open()                                  // what j or down from the bar does
      tryVerify(() => prompt.activeFocus)
      compare(prompt.selectedIndex, 1, "and lands on SearXNG")
    }

    function test_k_and_up_go_back_to_the_bar() {
      prompt.open()
      tryVerify(() => prompt.activeFocus)
      keyClick("k")
      compare(prompt.ups, 1)
      keyClick(Qt.Key_Up)
      compare(prompt.ups, 2)
      compare(prompt.confirms + prompt.cancels, 0, "neither is an answer")
    }

    function test_h_l_choose_enter_takes_esc_is_not_now() {
      prompt.open()
      tryVerify(() => prompt.activeFocus)
      keyClick("h")
      compare(prompt.selectedIndex, 0)
      keyClick(Qt.Key_Return)
      compare(prompt.cancels, 1, "Enter on Not now")
      keyClick("l")
      keyClick(Qt.Key_Return)
      compare(prompt.confirms, 1, "Enter on SearXNG")
      keyClick(Qt.Key_Escape)
      compare(prompt.cancels, 2, "esc is Not now")
    }
  }
}
