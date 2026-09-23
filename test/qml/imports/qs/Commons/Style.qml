pragma Singleton
import QtQml

QtObject {
  readonly property QtObject spacing: QtObject {
    property real controlPaddingX: 8
    property real inputPaddingY: 4
    property real xxs: 2
    property real xs: 3
    property real md: 6
  }
  property real cornerRadius: 4
  readonly property QtObject font: QtObject {
    property real body: 12
    property real caption: 10
    property string menuFamily: "monospace"
  }
  function selectionFillFor(foreground, accent) { return accent }
  function space(value) { return value }
}
