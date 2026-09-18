import QtQuick
import "history.mjs" as HistoryLib
import "../shared"

// The queries searched before, ~/.local/share/omaseek/queries.json. The shape of
// SessionStore, and read once and never watched for the same reason: a walk is an
// index into this list, so a re-read behind its back would move the query under
// the cursor.
Item {
  id: store

  property var queries: []
  readonly property alias ready: file.ready
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
    file.write(HistoryLib.writeQueries(list))
  }

  JsonFile {
    id: file

    name: "omaseek/queries.json"
    onLoaded: text => store.queries = HistoryLib.readQueries(text)
  }
}
