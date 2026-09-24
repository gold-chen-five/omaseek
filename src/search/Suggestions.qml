import QtQuick
import "suggest.mjs" as SuggestLib
import "../shared"

// The dropdown under the search bar: what was typed, the rows for it (past
// searches, then SearXNG's suggestions), and the one the arrows are on. The
// panel says when typing happened (type) and whether the bar is where the list
// belongs (active); the rules are suggest.mjs.
Item {
  id: suggestions

  property string backendPath: ""
  property bool enabled: true                  // Settings → Search → Suggestions is not off
  property bool active: false                  // search mode, the bar focused, insert mode
  property var past: []                        // the queries searched before, newest first

  property string typed: ""                    // what the reader typed; the bar may show a row instead
  property var remote: []                      // SearXNG's suggestions…
  property string remoteFor: ""                // …and the text they answered
  property int index: -1                       // the row the arrows are on; -1 is the typed text

  readonly property var rows: SuggestLib.suggestionRows(typed, past, enabled ? remote : [], remoteFor)
  readonly property bool showing: active && rows.length > 0

  // The reader typed: new rows for the new text, a moment after the last key.
  function type (text) {
    typed = String(text ?? "")
    index = -1
    if (!enabled || typed.trim() === "") {
      pause.stop()
      process.stop()
      return
    }
    pause.restart()
  }

  // ↓ or ↑: the text the bar should show now — a row, or back to what was typed.
  function step (delta) {
    index = SuggestLib.stepSuggestion(index, rows.length, delta)
    return index === -1 ? typed : rows[index].text
  }

  // Searched, or left: the list goes until the next thing typed.
  function clear () {
    typed = ""
    index = -1
    pause.stop()
    process.stop()
  }

  // A key per keystroke would be a request per letter: wait for a pause.
  Timer {
    id: pause

    interval: 120
    onTriggered: process.start([suggestions.backendPath, "--suggest", suggestions.typed.trim()])
  }

  JsonProcess {
    id: process

    // Only for the text still typed: a slow answer for "yo" must not replace
    // the rows for "you".
    onParsed: payload => {
      const found = SuggestLib.readSuggestions(payload)
      if (found === null || String(payload.query ?? "") !== suggestions.typed.trim()) return
      suggestions.remote = found
      suggestions.remoteFor = payload.query
    }
    onUnreadable: {}
  }
}
