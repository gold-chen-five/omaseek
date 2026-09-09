import QtQuick
import qs.Commons

// Search results with a vim-style cursor. Key handling lives in Search.qml so
// the panel owns the whole focus state machine; this file is presentation plus
// the cursor bookkeeping that goes with it.
ListView {
  id: list

  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal activated(int index)

  clip: true
  keyNavigationEnabled: false          // Search.qml drives j/k and the arrows
  boundsBehavior: Flickable.StopAtBounds
  currentIndex: 0
  spacing: Style.spacing.xxs
  highlightMoveDuration: 0

  function moveCursor(delta) {
    if (count === 0) return
    currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta))
    positionViewAtIndex(currentIndex, ListView.Contain)
  }

  function moveCursorTo(index) {
    if (count === 0) return
    currentIndex = Math.max(0, Math.min(count - 1, index))
    positionViewAtIndex(currentIndex, ListView.Contain)
  }

  delegate: Rectangle {
    id: row

    required property int index
    required property string title
    required property string url
    required property string snippet
    required property string display_url

    readonly property bool hasCursor: index === list.currentIndex

    width: list.width
    height: content.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: hasCursor ? list.selectedBackground : "transparent"

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.title
        color: row.hasCursor ? list.accent : list.foreground
        font.family: list.fontFamily
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.display_url
        color: list.foreground
        opacity: 0.55
        font.family: list.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: row.snippet !== ""
        textFormat: Text.PlainText
        text: row.snippet
        color: list.foreground
        opacity: 0.75
        font.family: list.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) list.currentIndex = row.index
      onClicked: {
        list.currentIndex = row.index
        list.activated(row.index)
      }
    }
  }
}
