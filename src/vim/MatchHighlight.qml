import QtQuick

// A match lit under the text: the one the cursor is on is accented, the rest are
// quiet. Drawn behind the text rather than selected, because a selection
// appearing on a TextEdit is taken for a mouse drag and starts visual mode.
//
// A match spanning a wrap has no single rectangle, so `tail` past `head`'s line
// lights the first character only.
Rectangle {
  id: hit

  property rect head: Qt.rect(0, 0, 0, 0)      // the first character's rectangle
  property rect tail: head                     // the last character's, for a run
  property bool current: false
  property color foreground: "transparent"
  property color accent: "transparent"

  readonly property bool oneLine: Math.abs(tail.y - head.y) < 1

  x: head.x
  y: head.y
  width: oneLine ? Math.max(1, tail.x + tail.width - head.x) : head.width
  height: head.height
  color: current ? accent : foreground
  opacity: current ? 0.42 : 0.14
  radius: 2
}
