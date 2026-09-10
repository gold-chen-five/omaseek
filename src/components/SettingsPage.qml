import QtQuick
import qs.Commons
import qs.Ui

// The settings page. One row per setting: what it is, what it does, and the
// choices laid out so the current one is visible without opening anything.
//
// Rows come from lib/settings.mjs so the page and the backend cannot disagree
// about which options exist. Keys are handled in Search.qml, which owns the
// panel's focus; a row's chips are still clickable.
Column {
  id: page

  property var rows: []
  property int cursor: 0
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)

  spacing: Style.spacing.xs

  Repeater {
    model: page.rows

    delegate: Rectangle {
      id: settingRow

      required property int index
      required property var modelData

      readonly property bool hasCursor: index === page.cursor

      width: page.width
      height: rowContent.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: hasCursor ? page.selectedBackground : "transparent"

      Item {
        anchors.fill: parent
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.controlPaddingX

        Column {
          id: rowContent

          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - chips.width - Style.spacing.lg
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: settingRow.modelData.label
            color: settingRow.hasCursor ? page.accent : page.foreground
            font.family: page.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: settingRow.modelData.hint
            color: page.foreground
            opacity: 0.55
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        ButtonGroup {
          id: chips

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          options: settingRow.modelData.options.map(option => String(option))
          value: String(settingRow.modelData.value)
          foreground: page.foreground
          accent: page.accent
          fontFamily: page.fontFamily
          focusable: false               // Search.qml drives the keyboard
          cursorIndex: -1

          onChanged: function (picked) {
            page.cursor = settingRow.index
            page.changed(settingRow.modelData.key, picked)
          }
        }
      }
    }
  }
}
