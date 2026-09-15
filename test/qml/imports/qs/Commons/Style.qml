pragma Singleton
import QtQml

QtObject {
  readonly property QtObject spacing: QtObject {
    property real controlPaddingX: 8
    property real inputPaddingY: 4
  }
  function selectionFillFor(foreground, accent) { return accent }
  function space(value) { return value }
}
