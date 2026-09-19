import QtQuick
import Quickshell
import "../shared"

// The key that opens the panel, in the user's own Hyprland bindings: whether
// one is there, and bin/keybind to add SUPER + D when it is free. Adding runs in
// a terminal, as SearXNG's start and update do, so the reader sees the line and
// says yes before their config changes.
Item {
  id: shortcut

  // bin/keybind --status as it answered: { state: bound | free | taken | missing };
  // null before a check.
  property var status: null

  readonly property string scriptPath: Qt.resolvedUrl("../../bin/keybind").toString().replace(/^file:\/\//, "")

  signal launching()                           // a terminal is about to take the screen

  function probe () {
    status = null
    statusProcess.start([shortcut.scriptPath, "--status"])
  }

  // The terminal outlives the panel, so the row learns the answer the next time
  // Settings opens and probes again.
  function add () {
    launching()
    status = null
    Quickshell.execDetached([
      "xdg-terminal-exec", "bash", "-c",
      shortcut.scriptPath + " --add; echo; read -n1 -r -p 'press any key to close'"
    ])
  }

  JsonProcess {
    id: statusProcess

    onParsed: payload => shortcut.status = payload
    onUnreadable: shortcut.status = ({ ok: false })
  }
}
