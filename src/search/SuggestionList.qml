import QtQuick
import qs.Commons
import qs.Ui
import "suggest.mjs" as SuggestLib

// The dropdown under the search bar, drawn as the settings dropdown's list is:
// a clock beside a past search, a magnifier beside a suggestion, and what each
// adds to the typed text in bold. It never takes the keyboard — the bar keeps
// typing, and the arrows reach this through the store — so a click is all it
// raises.
//
// One row is lit at a time: the arrows' row, or the pointer's once the pointer
// has really moved. The list opens under a pointer resting in the middle of the
// screen, and lighting whatever row appeared beneath it showed a second row
// chosen before any key was pressed — and two lit once ↓ was.
BorderSurface {
  id: list

  property var rows: []
  property int current: -1
  property string typed: ""
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal picked(string text)

  property int pointed: -1                     // the row the moving pointer is on, or -1

  // The arrows take the highlight back, and new rows start with none pointed.
  onCurrentChanged: forgetPointer()
  onRowsChanged: forgetPointer()
  onVisibleChanged: forgetPointer()

  function forgetPointer () {
    pointed = -1
    pointerGate.reset()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: list
  }

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
        readonly property bool lit: list.pointed !== -1 ? index === list.pointed : index === list.current

        width: column.width
        height: list.rowHeight
        radius: Style.cornerRadius
        color: lit ? Style.hoverFillFor(list.foreground, list.accent) : "transparent"

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

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: mouse => { if (pointerGate.moved(row, mouse)) list.pointed = row.index }
          onExited: if (list.pointed === row.index) list.pointed = -1
          onClicked: list.picked(row.modelData.text)
        }
      }
    }
  }
}
