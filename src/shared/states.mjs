// The panel's states, named once. Strings, not a QML enum: enums can't cross into
// these node-tested modules. A misspelt key is undefined, and QML warns on it.

export const VIEW = Object.freeze({
  SEARCH: 'search',       // the field and what is under it
  SETTINGS: 'settings',
  SETUP: 'setup',         // the SearXNG instance is down; asking to start it
  WELCOME: 'welcome'      // the first open after install: SearXNG and SUPER + D, set up in place
})

export const PANEL = Object.freeze({
  SEARCH: 'search',       // Enter searches the web
  AI: 'ai'                // Enter asks an agent
})

export const FOCUS = Object.freeze({
  FIELD: 'field',         // the field has the keyboard
  RESULTS: 'results',     // the list, or the transcript, has it
  TRANSLATION: 'translation'  // the translation beside them has it (ctrl+l)
})
