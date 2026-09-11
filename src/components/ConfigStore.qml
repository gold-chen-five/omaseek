import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/settings.mjs" as SettingsLib
import "../lib/keymap.mjs" as KeymapLib

// ~/.config/omaseek/config.json. Writes only the keys the settings page owns;
// everything else (searxng_url, searxng_engines) passes through untouched.
Item {
  id: store

  readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omaseek/config.json"
  readonly property string dir: path.replace(/\/[^\/]*$/, "")

  property string source: ""                   // kept so a write preserves unknown keys
  property var keymap: KeymapLib.readKeymap("")
  property var settings: SettingsLib.readSettings("")

  // Re-read on every summon on top of the watch, so an edit lands whether the
  // file was changed, deleted, or created after the shell started.
  function reload () { configFile.reload() }

  // A change is written straight through — there is no save button to forget.
  function change (key, value) {
    // Every setting, so a key added to the settings lib needs nothing here.
    const next = {}
    for (const name in settings) next[name] = settings[name]
    next[key] = value

    const text = SettingsLib.writeSettings(next, source)
    apply(text)                                // reflect it now; the watcher confirms
    persist(text)
  }

  function apply (text) {
    source = text
    keymap = KeymapLib.readKeymap(text)
    settings = SettingsLib.readSettings(text)
  }

  // setText fails silently when the directory is missing, which is exactly the
  // state a machine is in before its first settings change — so the directory
  // is created first and the write waits for it.
  function persist (text) {
    writer.pending = text
    writer.command = ["mkdir", "-p", store.dir]
    writer.running = true
  }

  // An explicit reload() reads asynchronously, which is why the contents come
  // from onLoaded rather than from text() at the call site.
  FileView {
    id: configFile

    path: store.path
    preload: true
    watchChanges: true
    printErrors: false

    onLoaded: store.apply(text())
    onLoadFailed: store.apply("")              // absent or unreadable: defaults
    onFileChanged: reload()
  }

  Process {
    id: writer

    property string pending: ""

    onExited: {
      if (!writer.pending) return
      configFile.setText(writer.pending)
      writer.pending = ""
    }
  }
}
