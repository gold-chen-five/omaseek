import QtQuick
import qs.Commons
import qs.Ui
import "../field"
import "../shared/pixels.mjs" as Pixels

// A filter typed into the panel's own vim field, in the frame the search bar
// draws round its field: the key lookup's and the settings page's. The frame is
// the bar's because the field scrolls inside it, and a frame the field drew
// would scroll with it. Its signals are the field's (`field`); what they do is
// the owner's.
BorderSurface {
  id: bar

  property var keymap: ({ sequences: [], timeoutMs: 0 })
  property var chords: ({})
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property real outputScale: 1                 // the monitor's, for a whole-pixel frame
  property alias placeholderText: filter.placeholderText

  readonly property alias field: filter
  readonly property string text: filter.text
  readonly property real insetTop: Border.top(filter.borderSpec) + filter.verticalPadding
  readonly property real insetBottom: Border.bottom(filter.borderSpec) + filter.verticalPadding

  function clear () { filter.text = "" }

  // i and a insert, as from a reading pane; anything else is a mode to set.
  function focusField (mode) {
    if (mode === "i" || mode === "a") filter.enterInsert(mode)
    else filter.setMode(mode)
    filter.forceActiveFocus()
  }

  // Whole device pixels, as the search bar's frame (pixels.mjs).
  height: Pixels.snapToDevice(filter.lineHeight + insetTop + insetBottom, bar.outputScale)
  radius: Style.cornerRadius
  color: Style.controlFill(filter.activeFocus, filter.hovered, bar.foreground, bar.accent)
  borderSpec: filter.borderSpec

  Flickable {
    id: filterScroll

    anchors.fill: parent
    anchors.leftMargin: Border.left(filter.borderSpec) + filter.horizontalPadding
    anchors.rightMargin: Border.right(filter.borderSpec) + filter.horizontalPadding
    anchors.topMargin: bar.insetTop
    anchors.bottomMargin: bar.insetBottom
    clip: true
    interactive: false                         // it follows the cursor; nothing drags it
    contentWidth: filter.width
    contentHeight: filter.height

    VimTextField {
      id: filter

      width: Math.max(filterScroll.width, implicitWidth)
      height: Math.max(filterScroll.height, implicitHeight)
      foreground: bar.foreground
      accent: bar.accent
      font.family: bar.fontFamily
      font.pixelSize: Style.font.body
      verticalPadding: Style.spacing.md
      escapeSequences: bar.keymap.sequences
      escapeTimeout: bar.keymap.timeoutMs
      chords: bar.chords

      onCursorRectangleChanged: {
        const r = cursorRectangle
        if (r.x < filterScroll.contentX) filterScroll.contentX = r.x
        else if (r.x + r.width > filterScroll.contentX + filterScroll.width) filterScroll.contentX = r.x + r.width - filterScroll.width
      }
    }
  }
}
