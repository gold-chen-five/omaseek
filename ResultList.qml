import QtQuick
import qs.Commons
import qs.Ui

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
  cacheBuffer: 400                     // keep favicons alive just off-screen

  // Rows sliding under a stationary pointer would otherwise fire hover events
  // and yank the cursor away from where the keyboard put it.
  PointerMoveGate {
    id: pointerGate
    referenceItem: list
  }

  function moveCursor(delta) {
    if (count === 0) return
    pointerGate.reset()
    currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta))
    positionViewAtIndex(currentIndex, ListView.Contain)
  }

  function moveCursorTo(index) {
    if (count === 0) return
    pointerGate.reset()
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
    required property string icon

    readonly property bool hasCursor: index === list.currentIndex
    readonly property int iconSize: Style.space(16)

    width: list.width
    height: content.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: hasCursor ? list.selectedBackground : "transparent"

    Item {
      id: favicon

      width: row.iconSize
      height: row.iconSize
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.top: content.top
      anchors.topMargin: Math.max(0, (titleText.height - row.iconSize) / 2)

      Image {
        id: iconImage
        anchors.fill: parent
        source: row.icon
        sourceSize.width: row.iconSize * 2      // crisp on scaled displays
        sourceSize.height: row.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        visible: status === Image.Ready
      }

      // Domain initial while the icon loads or when the site has none.
      Text {
        anchors.centerIn: parent
        visible: iconImage.status !== Image.Ready
        text: row.display_url ? row.display_url.replace(/^www\./, "").charAt(0).toUpperCase() : "·"
        color: list.foreground
        opacity: 0.45
        font.family: list.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      id: content

      anchors.left: favicon.right
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.controlPaddingX
      spacing: Style.spacing.xxs

      Text {
        id: titleText
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
      onPositionChanged: function (mouse) {
        if (pointerGate.moved(row, mouse)) list.currentIndex = row.index
      }
      onClicked: {
        list.currentIndex = row.index
        list.activated(row.index)
      }
    }
  }
}
