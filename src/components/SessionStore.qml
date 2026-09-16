import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/sessions.mjs" as SessionsLib

// The saved conversations on disk, ~/.local/share/omaseek/sessions.json. The
// shape of ConfigStore, with one difference: the file is read once and never
// watched. The panel's place in the ring is an index into this list, so a
// re-read behind its back would move the conversation under the cursor.
Item {
  id: store

  readonly property string path: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/omaseek/sessions.json"
  readonly property string dir: path.replace(/\/[^\/]*$/, "")

  property var sessions: []
  property bool ready: false                   // the file has been read; before that the ring is unknown

  // The list is the panel's while it runs: it is replaced whole, then written.
  function save (list) {
    sessions = list
    persist(SessionsLib.writeSessions(list))
  }

  // setText fails silently when the directory is missing — the state a machine
  // is in before its first conversation — so the write waits for mkdir.
  function persist (text) {
    writer.pending = text
    writer.command = ["mkdir", "-p", store.dir]
    writer.running = true
  }

  FileView {
    id: sessionFile

    path: store.path
    preload: true
    printErrors: false

    onLoaded: {
      store.sessions = SessionsLib.readSessions(text())
      store.ready = true
    }
    onLoadFailed: {
      store.sessions = []                       // absent or unreadable: nothing saved
      store.ready = true
    }
  }

  Process {
    id: writer

    property string pending: ""

    onExited: {
      if (!writer.pending) return
      sessionFile.setText(writer.pending)
      writer.pending = ""
    }
  }
}
