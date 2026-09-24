import QtQuick
import qs.Commons
import qs.Ui
import "suggest.mjs" as SuggestLib

// The dropdown under the search bar, drawn as the settings dropdown's list is:
// a clock beside a past search, a magnifier beside a suggestion, and what each
// adds to the typed text in bold. It never takes the keyboard — the bar keeps
// typing, and the arrows reach this through the store — so a click is all it
// raises.
BorderSurface {
  id: list

  property var rows: []
  property int current: -1
  property string typed: ""
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal picked(string text)

  readonly property int rowHeight: Style.spacing.popupRowHeight

  implicitHeight: column.implicitHeight + topInset + bottomInset
  readonly property real topInset: Border.top(borderSpec) + Style.spacing.hairline
  readonly property real bottomInset: Border.bottom(borderSpec) + Style.spacing.hairline

  color: Color.popups.background
  radius: Style.cornerRadius
  borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)

  // A click here is the list's, not the card's behind it, which would dismiss.
  MouseArea { anchors.fill: parent; onClicked: {} }

  Column {
    id: column

    anchors.fill: parent
    anchors.topMargin: list.topInset
    anchors.bottomMargin: list.bottomInset
    anchors.leftMargin: Border.left(list.borderSpec) + Style.spacing.hairline
    anchors.rightMargin: Border.right(list.borderSpec) + Style.spacing.hairline

    Repeater {
      model: list.rows

      Rectangle {
        id: row

        required property var modelData
        required property int index
        readonly property bool lit: index === list.current || hover.hovered

        width: column.width
        height: list.rowHeight
        radius: Style.cornerRadius
        color: lit ? Style.hoverFillFor(list.foreground, list.accent) : "transparent"

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

        Text {
          id: glyph

          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(16)
          text: row.modelData.past ? "󰋚" : "󰍉"      // history, magnify
          color: Util.alpha(list.foreground, row.modelData.past ? 0.7 : 0.45)
          font.family: list.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.left: glyph.right
          anchors.right: parent.right
          anchors.leftMargin: Style.spacing.md
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.StyledText
          text: SuggestLib.suggestionMarkup(row.modelData.text, list.typed)
          color: row.lit ? Style.hoverStateColor(list.foreground, list.accent) : list.foreground
          font.family: list.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        TapHandler { onTapped: list.picked(row.modelData.text) }
      }
    }
  }
}
