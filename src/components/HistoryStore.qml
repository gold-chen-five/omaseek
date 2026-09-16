import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/history.mjs" as HistoryLib

// The queries searched before, ~/.local/share/omaseek/queries.json. The shape of
// SessionStore, and read once and never watched for the same reason: a walk is an
// index into this list, so a re-read behind its back would move the query under
// the cursor.
Item {
  id: store

  readonly property string path: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/omaseek/queries.json"
  readonly property string dir: path.replace(/\/[^\/]*$/, "")

  property var queries: []
  property bool ready: false                   // the file has been read; before that the ring is unknown
  property string waiting: ""                  // a query searched before the file landed

  // The read is asynchronous, so a query searched in the first moments of a
  // session waits for it: recording before the file lands would write a lone
  // query into a ring about to be replaced by the saved twenty-five.
  function remember (query) {
    if (!ready) {
      waiting = query
      return
    }
    save(HistoryLib.rememberQuery(queries, query, Date.now()))
  }

  onReadyChanged: {
    if (!ready || !waiting) return
    const query = waiting
    waiting = ""
    remember(query)
  }

  function save (list) {
    queries = list
    persist(HistoryLib.writeQueries(list))
  }

  // setText fails silently when the directory is missing — the state a machine is
  // in before its first search — so the write waits for mkdir.
  function persist (text) {
    writer.pending = text
    writer.command = ["mkdir", "-p", store.dir]
    writer.running = true
  }

  FileView {
    id: queryFile

    path: store.path
    preload: true
    printErrors: false

    onLoaded: {
      store.queries = HistoryLib.readQueries(text())
      store.ready = true
    }
    onLoadFailed: {
      store.queries = []                       // absent or unreadable: nothing searched yet
      store.ready = true
    }
  }

  Process {
    id: writer

    property string pending: ""

    onExited: {
      if (!writer.pending) return
      queryFile.setText(writer.pending)
      writer.pending = ""
    }
  }
}
