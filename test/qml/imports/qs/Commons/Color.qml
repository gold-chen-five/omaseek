pragma Singleton
import QtQuick

QtObject {
  property color foreground: "white"
  property color accent: "white"
  property color urgent: "red"
  readonly property QtObject menu: QtObject {
    property color selectedText: "white"
    property color text: "white"
    property color background: "black"
    property color selectedBackground: "gray"
  }
}
