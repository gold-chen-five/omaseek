import QtQuick

// Enough of the kit's ToggleSwitch for the settings rows outside the shell.
Item {
  property bool checked: false
  property bool busy: false
  property bool hasCursor: false
  property color foreground: "white"
  property color accent: "white"
  signal toggled()
}
