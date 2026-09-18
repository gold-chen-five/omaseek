import QtQuick
import qs.Commons
import qs.Ui

// The saved conversations as numbered squares, 1 the newest. The one on screen
// is filled; clicking one shows it, and the last square starts a new one — the
// same three things ctrl+n, ctrl+x and ctrl+c do from the keyboard. The strip
// only exists once something is saved; before that the new-session button beside
// the field says it all.
Item {
  id: tabs

  property var sessions: []
  property var pending: []                     // ids whose answer is still on its way
  property int current: -1                     // -1: the live conversation is not saved yet
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property real squareSize: Math.round(Style.font.body * 2)

  signal picked(int index)
  signal started()                             // the + square: a new conversation

  implicitHeight: squareSize
  height: visible ? implicitHeight : 0

  Row {
    id: row

    anchors.left: parent.left
    spacing: Style.spacing.xs

    Repeater {
      model: tabs.sessions

      Button {
        id: square

        required property int index
        required property var modelData

        readonly property bool answering: tabs.pending.indexOf(modelData.id) !== -1

        width: tabs.squareSize
        height: tabs.squareSize
        text: String(index + 1)
        tooltipText: answering ? modelData.title + " — still answering" : modelData.title
        bordered: true
        selected: index === tabs.current
        foreground: tabs.foreground
        accent: tabs.accent
        fontFamily: tabs.fontFamily
        fontSize: Style.font.caption

        onClicked: tabs.picked(index)

        // A question left behind keeps being answered; this is the only sign of
        // it once the conversation is no longer on screen.
        Rectangle {
          visible: square.answering
          width: Math.max(3, Math.round(tabs.squareSize / 6))
          height: width
          radius: width / 2
          color: tabs.accent
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: Math.max(1, Math.round(tabs.squareSize / 12))

          SequentialAnimation on opacity {
            running: square.answering
            loops: Animation.Infinite
            NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
          }
        }
      }
    }

    Button {
      width: tabs.squareSize
      height: tabs.squareSize
      text: "+"
      tooltipText: "new conversation"
      bordered: true
      selected: tabs.current === -1            // the live conversation, with nothing saved of it yet
      foreground: tabs.foreground
      accent: tabs.accent
      fontFamily: tabs.fontFamily
      fontSize: Style.font.caption

      onClicked: tabs.started()
    }
  }
}
