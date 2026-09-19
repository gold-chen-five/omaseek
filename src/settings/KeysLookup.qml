import QtQuick
import qs.Commons
import qs.Ui
import "keylist.mjs" as KeyList
import "../shared/vim/chord.js" as Chord

// ctrl+k: every key in the panel, to look one up without leaving for Settings.
// What is typed filters the list — words in the key, what it does, or where it
// works — and the arrows scroll it. esc or ctrl+k again closes it, and the panel
// puts the keyboard back where it was (`closed`). The entries are keylist.mjs's.
FocusScope {
  id: lookup

  property var settings: null
  property string closeChord: "C-k"
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var entries: KeyList.filterEntries(KeyList.keyEntries(settings), filter.text)

  signal closed()

  // Opened afresh each time: the last search is not what the next one is after.
  function open () {
    filter.text = ""
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

  Rectangle {
    id: filterBox

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: title.bottom
    anchors.topMargin: Style.spacing.sm
    height: filter.implicitHeight + Style.spacing.inputPaddingY * 2
    radius: Style.cornerRadius
    color: "transparent"
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: lookup.accent

    TextInput {
      id: filter

      anchors.fill: parent
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      verticalAlignment: TextInput.AlignVCenter
      focus: true
      color: lookup.foreground
      selectionColor: Util.alpha(lookup.accent, 0.35)
      font.family: lookup.fontFamily
      font.pixelSize: Style.font.body
      clip: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: event => {
        const chord = Chord.of(event)
        const page = Math.max(1, Math.floor(list.height / Style.font.body / 3))
        if (chord === "Escape" || chord === lookup.closeChord) lookup.closed()
        else if (chord === "Down" || chord === "C-n" || chord === "C-j") list.step(1)
        else if (chord === "Up" || chord === "C-p") list.step(-1)
        else if (chord === "C-d") list.step(page)
        else if (chord === "C-u") list.step(-page)
        else return
        event.accepted = true
      }
    }

    Text {
      anchors.fill: filter
      verticalAlignment: Text.AlignVCenter
      visible: filter.text === ""
      textFormat: Text.PlainText
      text: "translate, ctrl+x, undo, gd …"
      color: lookup.foreground
      opacity: 0.35
      font.family: lookup.fontFamily
      font.pixelSize: Style.font.body
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

    section.property: "group"
    section.delegate: Text {
      required property string section

      width: ListView.view.width
      topPadding: Style.spacing.sm
      bottomPadding: Style.spacing.xxs
      textFormat: Text.PlainText
      text: section.toUpperCase()
      color: lookup.foreground
      opacity: 0.5
      font.family: lookup.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.5
    }

    delegate: Rectangle {
      id: row

      required property var modelData
      required property int index

      width: ListView.view.width
      height: Math.max(keyText.implicitHeight, doesText.implicitHeight) + Style.spacing.xxs * 2
      color: index === list.currentIndex ? Color.menu.selectedBackground : "transparent"
      radius: Style.cornerRadius

      Text {
        id: keyText

        x: Style.spacing.sm
        y: Style.spacing.xxs
        width: Math.round(list.width * 0.18)
        textFormat: Text.PlainText
        text: row.modelData.keys
        color: row.index === list.currentIndex ? lookup.accent : lookup.foreground
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: doesText

        anchors.left: keyText.right
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.md
        anchors.rightMargin: Style.spacing.sm
        y: Style.spacing.xxs
        textFormat: Text.PlainText
        text: row.modelData.text
        color: lookup.foreground
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
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
