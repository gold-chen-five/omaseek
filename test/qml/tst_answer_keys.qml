import QtQuick
import QtTest
import Quickshell
import "../../src/ask"

// The answer read with real keys: ctrl+c is New session there as everywhere,
// even with a word selected in visual mode — only ctrl+shift+c copies.
Item {
  width: 480
  height: 240

  AnswerView {
    id: view
    anchors.fill: parent
    turns: [{ role: "user", text: "a question" }, { role: "assistant", text: "hello world answer" }]
    property int newSessions: 0
    onNewSessionRequested: newSessions++
  }

  TestCase {
    name: "Answer keys"
    when: windowShown

    function copied() {
      const out = []
      for (const command of Quickshell.detached) if (command[0] === "wl-copy") out.push(command[command.length - 1])
      return out
    }

    // Visual mode over one word of the reply: the cursor on "world", then v e.
    function selectOneWord() {
      view.forceActiveFocus()
      tryCompare(view, "activeFocus", true)
      view.placeCursor(view.plain().indexOf("world"))
      keyClick(Qt.Key_V)
      keyClick(Qt.Key_E)
      verify(view.selecting, "one word selected in visual mode")
    }

    function init() {
      view.newSessions = 0
      Quickshell.detached = []
      tryVerify(() => view.replyStarts.length === 1, 2000, "the reply is rendered")
    }

    function test_ctrl_c_over_a_visual_selection_starts_a_new_session() {
      selectOneWord()
      keyClick(Qt.Key_C, Qt.ControlModifier)
      compare(view.newSessions, 1, "ctrl+c is New session, selection or not")
      compare(copied(), [], "and it copies nothing")
      keyClick(Qt.Key_Escape)
    }

    function test_ctrl_shift_c_copies_the_selected_word_and_starts_nothing() {
      selectOneWord()
      keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier)
      compare(copied(), ["world"])
      compare(view.newSessions, 0)
      keyClick(Qt.Key_Escape)
    }
  }
}
