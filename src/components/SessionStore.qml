import QtQuick
import "../lib/sessions.mjs" as SessionsLib

// The saved conversations on disk, ~/.local/share/omaseek/sessions.json.
//
// Unlike ConfigStore the file is read once and never watched: the panel's place
// in the ring is an index into this list, so a re-read behind its back would
// move the conversation under the cursor.
Item {
  id: store

  property var sessions: []
  readonly property alias ready: file.ready

  // The list is the panel's while it runs: it is replaced whole, then written.
  function save (list) {
    sessions = list
    file.write(SessionsLib.writeSessions(list))
  }

  JsonFile {
    id: file

    name: "omaseek/sessions.json"
    onLoaded: text => store.sessions = SessionsLib.readSessions(text)
  }
}
