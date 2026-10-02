import QtQuick
import QtTest
import "../../src/settings"

// A choice that sets something off — Run SearXNG with opens a terminal — is
// chosen with h and l and taken with Enter; an ordinary choice changes at once.
Item {
  width: 640
  height: 400

  SettingsPage {
    id: page
    anchors.fill: parent
    incomingRows: [
      { key: 'searxngRunWith', type: 'choice', confirm: true, label: 'Run SearXNG with', hint: 'which engine',
        options: ['podman', 'docker'], value: 'podman', busy: false },
      { key: 'resultsPerPage', type: 'choice', label: 'Results per page', hint: 'how many',
        options: [5, 10, 15], value: 10 }
    ]
    property var changes: []
    onChanged: (key, value) => changes = changes.concat([[key, value]])
  }

  TestCase {
    name: "Settings confirm"
    when: windowShown

    function init() {
      page.changes = []
      page.cursor = 0
      page.clearPending()
      page.forceActiveFocus()
    }

    function test_h_and_l_choose_and_enter_takes_it() {
      keyClick("l")
      compare(page.changes, [], "l only chooses")
      compare(page.pendingValue, "docker")
      keyClick(Qt.Key_Return)
      compare(page.changes, [["searxngRunWith", "docker"]], "Enter takes it")
      compare(page.pendingKey, "", "and the choice is spent")
    }

    function test_back_on_the_value_or_esc_or_another_row_chooses_nothing() {
      keyClick("l"); keyClick("h")
      compare(page.pendingKey, "", "back on podman: nothing chosen")
      keyClick("l")
      keyClick(Qt.Key_Escape)
      compare(page.pendingKey, "", "esc keeps podman")
      keyClick(Qt.Key_Return)
      compare(page.changes, [], "and Enter has nothing to take")
      keyClick("l")
      page.cursor = 1
      compare(page.pendingKey, "", "leaving the row keeps it too")
    }

    function test_an_ordinary_choice_still_changes_at_once() {
      page.cursor = 1
      keyClick("l")
      compare(page.changes, [["resultsPerPage", 15]])
    }
  }
}
