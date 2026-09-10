import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/settings.mjs" as SettingsLib
import "../lib/keymap.mjs" as KeymapLib

// ~/.config/omaseek/config.json, read and written.
//
// The file is shared with bin/search and stays hand-editable: this store
// writes only the keys the settings page owns and carries everything else
// through untouched (`searxng_url`, `searxng_engines`). Every reader treats
// an unreadable file as defaults, so a typo costs one setting, not the panel.
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
    const next = {
      escapeSequence: settings.escapeSequence,
      escapeTimeoutMs: settings.escapeTimeoutMs,
      resultsPerPage: settings.resultsPerPage,
      chatAgent: settings.chatAgent,
      launcher: settings.launcher,
      searchKey: settings.searchKey,
      newSessionKey: settings.newSessionKey
    }
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
