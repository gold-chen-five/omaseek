import QtQml

// Replacing the settings Repeater destroys an open dropdown and resets its
// cursor to the saved value. Discovery and file-watch updates wait until the
// interaction ends; defer release so the closing delegate can finish first.
QtObject {
  property var source: []
  property var rows: []
  property bool held: false

  onSourceChanged: sync()
  onHeldChanged: if (!held) Qt.callLater(sync)

  function sync () {
    if (!held) rows = source
  }
}
