import QtQuick
import qs.Commons
import qs.Ui
import "keylist.mjs" as KeyList
import "../field"

// ctrl+k: every key in the panel, to look one up without leaving for Settings.
// A row is the Settings → Keys row — what it does, the key beside it, the hint
// under it — so the two read the same; the fixed vim keys close each group as
// they do on the page. What is typed filters the list, and the field is the
// panel's own, so the query is edited with every vim key: esc leaves insert,
// esc again closes, and so does ctrl+k. Its `j`/`k` and the arrows have no line
// to move to in a one-line field, so they walk the list instead (steppedUp,
// steppedDown, the history signals). The entries are keylist.mjs's.
FocusScope {
  id: lookup

  property var settings: null
  property var keymap: ({ sequences: [], timeoutMs: 0 })
  property var chords: ({})
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var entries: KeyList.filterEntries(KeyList.keyEntries(settings), filter.text)

  signal closed()

  // Opened afresh each time: the last search is not what the next one is after.
  function open () {
    filter.text = ""
    filter.enterInsert("i")
    list.positionViewAtBeginning()
    filter.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.background
  }

  // The card under it would take clicks otherwise.
  MouseArea { anchors.fill: parent; onClicked: filter.forceActiveFocus() }

  Text {
    id: title

    anchors.left: parent.left
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: "KEYS · type to filter · esc closes"
    color: lookup.foreground
    opacity: 0.5
    font.family: lookup.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  BorderSurface {
    id: filterBox

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: title.bottom
    anchors.topMargin: Style.spacing.sm
    height: Math.round(filter.implicitHeight + Style.spacing.inputPaddingY * 2)
    radius: Style.cornerRadius
    clip: true                                 // a long query scrolls inside the frame
    color: Style.controlFill(filter.activeFocus, filter.hovered, lookup.foreground, lookup.accent)
    borderSpec: filter.borderSpec

    VimTextField {
      id: filter

      anchors.fill: parent
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      verticalPadding: Style.spacing.inputPaddingY
      verticalAlignment: TextEdit.AlignVCenter
      focus: true
      placeholderText: "translate, ctrl+x, undo, gd …"
      foreground: lookup.foreground
      accent: lookup.accent
      font.family: lookup.fontFamily
      font.pixelSize: Style.font.body
      escapeSequences: lookup.keymap.sequences
      escapeTimeout: lookup.keymap.timeoutMs
      // The panel's keys are the field's, so ctrl+k closes the lookup from
      // here too. The rest raise signals nothing here connects: a panel key
      // does nothing while the lookup is up, rather than acting behind it.
      chords: lookup.chords

      onCancelled: lookup.closed()             // esc from normal mode
      onKeysRequested: lookup.closed()
      onSteppedDown: list.step(1)
      onSteppedUp: list.step(-1)
      onHistoryNextRequested: list.step(1)     // Down, from insert as well
      onHistoryPrevRequested: list.step(-1)
    }
  }

  ListView {
    id: list

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filterBox.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.spacing.md
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: lookup.entries
    currentIndex: 0

    function step (delta) {
      if (count === 0) return
      currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta))
      positionViewAtIndex(currentIndex, ListView.Contain)
    }

    onModelChanged: currentIndex = 0

    // The section heading and its rule, as the settings page draws a section.
    section.property: "group"
    section.delegate: Item {
      required property string section

      width: ListView.view.width
      height: heading.implicitHeight + Style.spacing.lg + Style.spacing.xs

      // No rule above the first group, as the settings page draws none above
      // its first section.
      Rectangle {
        visible: lookup.entries.length > 0 && lookup.entries[0].group !== parent.section
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.md
        height: Math.max(1, Style.normalBorderWidth)
        color: Util.alpha(lookup.foreground, 0.18)
      }

      Text {
        id: heading

        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: parent.section.toUpperCase()
        color: lookup.foreground
        opacity: 0.5
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }
    }

    delegate: Rectangle {
      id: row

      required property var modelData
      required property int index
      // A line of vim's own keys: no binding to show, and read as the settings
      // page reads its fixed rows.
      readonly property bool fixed: modelData.fixed === true

      width: ListView.view.width
      height: labels.implicitHeight + (fixed ? Style.spacing.xs : Style.spacing.md) * 2
      radius: Style.cornerRadius
      color: index === list.currentIndex ? Color.menu.selectedBackground : "transparent"

      Column {
        id: labels

        anchors.left: parent.left
        anchors.right: keyText.left
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.modelData.label
          color: lookup.foreground
          opacity: row.fixed ? 0.8 : 1
          font.family: lookup.fontFamily
          font.pixelSize: row.fixed ? Style.font.body : Style.font.subtitle
          // Wrapped, never elided: a hint cut short hides exactly what it is
          // there to say, and a fixed key's line is all hint.
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: row.modelData.hint || ""
          color: lookup.foreground
          opacity: 0.55
          font.family: lookup.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Text {
        id: keyText

        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: row.fixed ? 0 : Math.round(list.width * 0.2)
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.modelData.keys
        color: row.index === list.currentIndex ? lookup.accent : lookup.foreground
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
    }

    Text {
      anchors.centerIn: parent
      visible: list.count === 0
      textFormat: Text.PlainText
      text: "no key matches “" + filter.text + "”"
      color: lookup.foreground
      opacity: 0.5
      font.family: lookup.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
