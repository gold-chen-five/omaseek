// The panel's three pieces of state, spelled once.
//
// Search.qml sets them and lib/search.mjs reads them to build the status line
// and the mode label, so they cross the QML ↔ node boundary constantly. A QML
// `enum` cannot make that trip — it exists only inside a QML type, as an
// integer — so these are strings, named here and nowhere else. The point is
// the misspelling: `view = "setings"` was accepted silently and the panel
// showed nothing; `States.VIEW.SETINGS` is undefined, and QML says so.

export const VIEW = Object.freeze({
  SEARCH: 'search',       // the field and what is under it
  SETTINGS: 'settings',
  SETUP: 'setup'          // the SearXNG instance is down; asking to start it
})

export const PANEL = Object.freeze({
  SEARCH: 'search',       // Enter searches the web
  AI: 'ai'                // Enter asks an agent
})

export const FOCUS = Object.freeze({
  FIELD: 'field',         // the field has the keyboard
  RESULTS: 'results'      // the list, or the transcript, has it
})
