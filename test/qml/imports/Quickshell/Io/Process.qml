import QtQuick

// Enough of Quickshell's Process to build a JsonFile outside the shell: it
// runs nothing.
Item {
  property var command: []
  property bool running: false

  signal exited(int exitCode)
}
