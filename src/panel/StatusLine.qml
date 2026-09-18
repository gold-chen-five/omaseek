import QtQuick
import qs.Commons

// The strip under the search field: editing mode on the left, what the search
// is doing on the right. Both strings come from search/search.mjs.
Item {
  id: line

  property string mode: ""
  property string detail: ""
  property bool isError: false
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  implicitHeight: modeLabel.implicitHeight

  Text {
    id: modeLabel

    anchors.left: parent.left
    textFormat: Text.PlainText
    text: line.mode
    color: line.accent
    opacity: 0.75
    font.family: line.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    anchors.right: parent.right
    textFormat: Text.PlainText
    text: line.detail
    color: line.foreground
    opacity: line.isError ? 0.95 : 0.55
    font.family: line.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
    width: Math.min(implicitWidth, line.width - modeLabel.implicitWidth - Style.spacing.lg)
  }
}
