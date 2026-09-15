pragma Singleton
import QtQuick

QtObject {
  property color foreground: "white"
  property color accent: "white"
  readonly property QtObject menu: QtObject {
    property color selectedText: "white"
  }
}
