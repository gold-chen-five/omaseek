import QtQuick
import Quickshell
import "../shared"
import "../shared/terminal.mjs" as Terminal
import "hyprkey.mjs" as HyprKey

// The key that opens the panel, in the user's own Hyprland bindings: whether
// one is there, and bin/keybind to add it — SUPER + D, or the key the reader
// chose — or change the one it added before. That runs in a terminal, as
// SearXNG's start and update do, so the reader sees the line and says yes
// before their config changes.
Item {
  id: shortcut

  // bin/keybind --status as it answered: { state: bound | free | taken | missing };
  // null before a check.
  property var status: null
  // The key asked about: what probe checks and add writes, normalized.
  property string wanted: HyprKey.DEFAULT_OPEN_KEY

  readonly property string scriptPath: Qt.resolvedUrl("../../bin/keybind").toString().replace(/^file:\/\//, "")

  signal launching()                           // a terminal is about to take the screen

  function probe () {
    status = null
    statusProcess.start([shortcut.scriptPath, "--status", "--key", wanted])
  }

  // Another key, typed: kept and checked when it is one Hyprland can bind.
  function choose (raw) {
    const key = HyprKey.normalizeHyprKey(raw)
    if (!key) return false
    wanted = key
    probe()
    return true
  }

  // The terminal outlives the panel, so the row learns the answer the next time
  // Settings opens and probes again. `comeBack`, from the welcome page, brings
  // the panel back once the terminal is done with (terminal.mjs).
  function add (comeBack) {
    launching()
    status = null
    Quickshell.execDetached([
      "xdg-terminal-exec", "bash", "-c",
      // The key goes in as an argument, never spliced into the shell text.
      shortcut.scriptPath + ' --add --key "$1"; ' + Terminal.terminalEnding(comeBack),
      "keybind", wanted
    ])
  }

  JsonProcess {
    id: statusProcess

    onParsed: payload => shortcut.status = payload
    onUnreadable: shortcut.status = ({ ok: false })
  }
}
