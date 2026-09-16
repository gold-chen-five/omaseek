import QtQuick
import Quickshell
import Quickshell.Io

// One of our JSON files under an XDG base directory, read whole and written
// whole. The three stores above it (config, queries, conversations) differ only
// in where the file lives, whether it is watched, and what the text means.
//
// Two traps live here so they are settled once: setText fails silently when the
// directory is missing — the state a machine is in before its first write — so
// every write waits for a mkdir; and the read is asynchronous, so `ready` is
// what a caller waits on rather than assuming the first `loaded`.
Item {
  id: file

  property string base: "data"                 // "config" or "data": which XDG root
  property string name: ""                     // "omaseek/sessions.json"
  property bool watch: false                   // re-read when something else writes it

  readonly property string root: base === "config"
    ? (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
    : (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
  readonly property string path: root + "/" + name
  readonly property string dir: path.replace(/\/[^\/]*$/, "")

  property bool ready: false                   // the file has been read; before that its contents are unknown

  // The text on disk, or "" when it is absent or unreadable — which every
  // reader here treats as empty rather than as an error. Raised *before*
  // `ready`: a store waiting on `ready` acts on the contents, so a flag that
  // arrived first would let it work from a list it has not been given yet.
  signal loaded(string text)

  function reload () { view.reload() }

  function write (text) {
    writer.pending = text
    writer.command = ["mkdir", "-p", file.dir]
    writer.running = true
  }

  // An explicit reload() reads asynchronously, which is why the contents come
  // from onLoaded rather than from text() at the call site.
  FileView {
    id: view

    path: file.path
    preload: true
    watchChanges: file.watch
    printErrors: false

    onLoaded: {
      file.loaded(text())
      file.ready = true
    }
    onLoadFailed: {
      file.loaded("")
      file.ready = true
    }
    onFileChanged: if (file.watch) reload()
  }

  Process {
    id: writer

    property string pending: ""

    onExited: {
      if (!writer.pending) return
      view.setText(writer.pending)
      writer.pending = ""
    }
  }
}
