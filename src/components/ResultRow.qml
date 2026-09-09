import QtQuick
import qs.Commons

// One search result: favicon, title, domain, snippet.
//
// Model roles arrive as required properties, so this is a ListView delegate
// and nothing else.
Rectangle {
  id: row

  required property int index
  required property string title
  required property string url
  required property string snippet
  required property string display_url
  required property string icon

  property bool hasCursor: false
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal activated()
  signal hovered(var mouse)

  readonly property int iconSize: Style.space(16)

  implicitHeight: content.implicitHeight + Style.spacing.md * 2
  radius: Style.cornerRadius
  color: hasCursor ? selectedBackground : "transparent"

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
      sourceSize.width: row.iconSize * 2       // crisp on scaled displays
      sourceSize.height: row.iconSize * 2
      fillMode: Image.PreserveAspectFit
      smooth: true
      asynchronous: true
      visible: status === Image.Ready
    }

    // The domain's initial stands in while the icon loads, or for good when
    // the site has no favicon at all.
    Text {
      anchors.centerIn: parent
      visible: iconImage.status !== Image.Ready
      text: row.display_url ? row.display_url.replace(/^www\./, "").charAt(0).toUpperCase() : "·"
      color: row.foreground
      opacity: 0.45
      font.family: row.fontFamily
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
      color: row.hasCursor ? row.accent : row.foreground
      font.family: row.fontFamily
      font.pixelSize: Style.font.subtitle
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.display_url
      color: row.foreground
      opacity: 0.55
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: row.snippet !== ""
      textFormat: Text.PlainText
      text: row.snippet
      color: row.foreground
      opacity: 0.75
      font.family: row.fontFamily
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
    onPositionChanged: mouse => row.hovered(mouse)
    onClicked: row.activated()
  }
}
