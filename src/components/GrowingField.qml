import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The kit's TextField chrome on a TextArea, so the field can hold a line
// break. Ui.TextField is a TextInput underneath, and a TextInput cannot
// render a newline — it strips it — so a question that wants two lines needs
// a TextEdit under it. Everything the vim layer calls (text, cursorPosition,
// select, insert, remove, undo, redo, clear, cursorDelegate) exists on both,
// which is why VimTextField could move over without changing a motion.
//
// Sizing: one line tall at rest, growing with the text up to `maxLines`, so
// the search bar stays a bar until someone actually breaks a line.
TextArea {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property bool hasCursor: false
  property int maxLines: 8

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)
  readonly property real _lineHeight: metrics.height
  readonly property real _chrome: topPadding + bottomPadding
  // What the field measures with one line in it — the buttons beside it
  // keep this height while the field itself grows.
  readonly property real oneLineHeight: Math.round(_lineHeight + _chrome)

  FontMetrics { id: metrics; font: root.font }

  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: foreground
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)
  wrapMode: TextEdit.Wrap
  selectByMouse: true

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: verticalPadding + Border.top(_borderSpec)
  bottomPadding: verticalPadding + Border.bottom(_borderSpec)

  // implicitHeight follows the content; the cap keeps a pasted essay from
  // eating the panel. Below the cap the field is exactly as tall as its text.
  height: Math.min(implicitHeight, Math.round(_lineHeight * maxLines + _chrome))
  clip: true

  background: BorderSurface {
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }
}
