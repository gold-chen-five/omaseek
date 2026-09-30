import QtQuick

// Enough of Quickshell's FileView to build a JsonFile outside the shell: it
// reads nothing, so a file is always absent.
Item {
  property string path: ""
  property bool preload: false
  property bool watchChanges: false
  property bool printErrors: true

  signal loaded()
  signal loadFailed()
  signal fileChanged()

  function reload () { loadFailed() }
  function text () { return "" }
  function setText (value) {}
}
