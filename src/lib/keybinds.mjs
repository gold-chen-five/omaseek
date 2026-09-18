// The rebindable keys: settings text ("ctrl+c", "gx") <-> chord strings ("C-c",
// "g x"). A binding is a named key, one character, ctrl+ either, or — in the
// panes read with vim keys — two keys typed in turn. Anything else parses to
// null. Letters keep their case: G and g are different keys, as in vim.

const NAMED = {
  enter: 'Return', return: 'Return',
  esc: 'Escape', escape: 'Escape',
  tab: 'Tab',
  space: ' ',                       // chord.js spells it by its text
  up: 'Up', down: 'Down', left: 'Left', right: 'Right',
  home: 'Home', end: 'End'
}

const SPELLED = {
  Return: 'enter', Escape: 'esc', Tab: 'tab', ' ': 'space',
  Up: 'up', Down: 'down', Left: 'left', Right: 'right',
  Home: 'home', End: 'end'
}

// Every key the settings page rebinds, in the order it lists them. `scope` is
// where the key is read: 'field' and 'panel' keys are caught before the field
// types anything, so they must be a named key or a ctrl chord (a letter there
// could never be typed); 'panel' keys also work in the two reading panes.
// 'reader' keys belong to those panes, `panes` narrowing them to one, and may
// be two keys in turn. `command` is the name the panes switch on.
export const ACTIONS = [
  { id: 'search', config: 'search_key', default: 'enter', scope: 'field',
    label: 'Search / ask', hint: 'field: runs the query or asks the question' },
  { id: 'newSession', config: 'new_session_key', default: 'ctrl+c', scope: 'panel',
    label: 'New session', hint: 'field and answer: forget the conversation and start one' },
  { id: 'nextSession', config: 'next_session_key', default: 'ctrl+n', scope: 'panel', command: 'nextSession',
    label: 'Next session', hint: 'ask: the next saved conversation, wrapping' },
  { id: 'closeSession', config: 'close_session_key', default: 'ctrl+x', scope: 'panel', command: 'closeSession',
    label: 'Close session', hint: 'ask: forget this conversation, show the next' },
  { id: 'clearSessions', config: 'clear_sessions_key', default: 'ctrl+shift+x', scope: 'panel', command: 'clearSessions',
    label: 'Delete all sessions', hint: 'ask: forget every saved conversation — press it twice' },
  { id: 'retryAnswer', config: 'retry_answer_key', default: 'ctrl+shift+r', scope: 'panel', command: 'retryAnswer',
    label: 'Retry answer', hint: 'ask: ask the last question again after a failure, a stop or an interruption' },
  { id: 'settings', config: 'settings_key', default: 'ctrl+s', scope: 'panel', command: 'settings',
    label: 'Settings', hint: 'anywhere: open or close this page (ctrl+, always works too)' },
  { id: 'switchMode', config: 'switch_mode_key', default: 'tab', scope: 'panel', command: 'toggleMode',
    label: 'Switch search / ask', hint: 'anywhere: between searching and asking (shift+tab too)' },
  { id: 'open', config: 'open_key', default: 'enter', scope: 'reader', command: 'accept',
    label: 'Open', hint: 'results: the selected result · answer: the link under the cursor' },
  { id: 'handoff', config: 'handoff_key', default: 'ga', scope: 'reader', command: 'handOff',
    label: 'Hand off to agent', hint: 'the selected result’s URL, or the selection / reply under the cursor, as a draft' },
  { id: 'handoffAll', config: 'handoff_all_key', default: 'gA', scope: 'reader', command: 'handOffPage',
    label: 'Hand off everything', hint: 'every URL on the results page, or the whole conversation, as a draft' },
  { id: 'askAbout', config: 'ask_about_key', default: 'gc', scope: 'reader', panes: ['results'], command: 'askAbout',
    label: 'Ask about this', hint: 'results: the selected URL into the ask bar, to type a question around' },
  { id: 'searchFor', config: 'search_for_key', default: 'gs', scope: 'reader', panes: ['results', 'answer'], command: 'searchFor',
    label: 'Search for this', hint: 'results: search for the selected result’s title · answer: the selection, or the word under the cursor' },
  { id: 'openLink', config: 'open_link_key', default: 'gx', scope: 'reader', panes: ['answer'], command: 'openLink',
    label: 'Open link', hint: 'answer: the URL under the cursor or in the selection, as vim’s gx' },
  { id: 'nextPage', config: 'next_page_key', default: 'l', scope: 'reader', panes: ['results'], command: 'nextPage',
    label: 'Next page', hint: 'results: the next page (→ too)' },
  { id: 'previousPage', config: 'previous_page_key', default: 'h', scope: 'reader', panes: ['results'], command: 'previousPage',
    label: 'Previous page', hint: 'results: the page before, from the cache (← too)' },
  { id: 'nextChat', config: 'next_chat_key', default: 'L', scope: 'reader', panes: ['answer'], command: 'nextSession',
    label: 'Next conversation', hint: 'ask: the next saved conversation, wrapping — 3L walks three' },
  { id: 'previousChat', config: 'previous_chat_key', default: 'H', scope: 'reader', panes: ['answer'], command: 'previousSession',
    label: 'Previous conversation', hint: 'ask: the conversation before, wrapping' },
  { id: 'insert', config: 'insert_key', default: 'gi', scope: 'reader', command: 'insert',
    label: 'Back to the field', hint: 'results and answer: return to the field in insert mode (i and a do too)' },
  { id: 'normal', config: 'normal_key', default: 'gn', scope: 'reader', command: 'fieldNormal',
    label: 'Back to the field (normal)', hint: 'results and answer: return to the field in normal mode (esc does too)' }
]

export const PANES = ['results', 'answer']

/** The settings key an action is stored under: handoff -> handoffKey. */
export function settingKey (action) {
  return action.id + 'Key'
}

export function actionById (id) {
  for (let i = 0; i < ACTIONS.length; i++) if (ACTIONS[i].id === id) return ACTIONS[i]
  return null
}

export function appliesTo (action, pane) {
  if (action.scope === 'field') return pane === 'field'
  if (action.scope === 'panel') return true
  if (pane === 'field') return false
  return !action.panes || action.panes.indexOf(pane) !== -1
}

// One key: a named key (any case), ctrl+ (and optionally shift+) a key, or one
// character as typed. Shift without ctrl is refused: on its own it is how a
// capital is typed, and `X` already spells that.
function parseKey (token) {
  const text = String(token == null ? '' : token).trim()
  if (!text) return null
  const plus = text.indexOf('+')
  if (plus > 0 && plus < text.length - 1) {
    const modifier = text.slice(0, plus).trim().toLowerCase()
    const rest = text.slice(plus + 1)
    if (modifier === 'shift') {
      const key = parseKey(rest)
      // Only as ctrl+shift+…, which the branch below assembles.
      return key !== null && key.indexOf('C-') !== 0 && key !== ' ' ? 'S-' + spellKey(key) : null
    }
    if (modifier !== 'ctrl' && modifier !== 'control') return null   // ctrl and shift, for now
    const key = parseKey(rest)
    if (key === null || key === ' ' || key.indexOf('C-') === 0) return null
    // Ctrl+letter is spelled lowercase by chord.js, whatever shift says.
    return 'C-' + (key.indexOf('S-') === 0 ? 'S-' + spellKey(key.slice(2)) : spellKey(key))
  }
  const named = NAMED[text.toLowerCase()]
  if (named) return named
  return text.length === 1 ? text : null
}

function spellKey (key) {
  return key.length === 1 ? key.toLowerCase() : key
}

// 'S-x' is the half-built shift chord the ctrl branch consumes; on its own it is
// not a key anyone can press.
function whole (key) {
  return key !== null && key.indexOf('S-') === 0 ? null : key
}

/** "ctrl+c" -> "C-c", "enter" -> "Return", "G" -> "G". Null when it is not one key. */
export function parseChord (raw) {
  return whole(parseKey(raw))
}

/**
 * A binding -> the sequence a keymap is keyed by: "gx" and "g x" -> "g x",
 * "ctrl+enter" -> "C-Return". Null when it is not a key or two keys.
 */
export function parseSequence (raw) {
  const text = String(raw == null ? '' : raw).trim()
  if (!text) return null
  const single = whole(parseKey(text))
  if (single !== null) return single
  const tokens = /\s/.test(text) ? text.split(/\s+/) : (text.length === 2 ? [text[0], text[1]] : [])
  if (tokens.length !== 2) return null
  const keys = []
  for (let i = 0; i < tokens.length; i++) {
    const key = whole(parseKey(tokens[i]))
    if (key === null || key === ' ') return null    // a space would read as the separator
    keys.push(key)
  }
  return keys.join(' ')
}

/** "C-c" -> "ctrl+c", "g x" -> "gx": how a binding is shown and stored. */
export function chordText (sequence) {
  const raw = String(sequence == null ? '' : sequence)
  if (!raw) return ''
  if (raw !== ' ' && raw.indexOf(' ') !== -1) {
    const keys = raw.split(' ').map(chordText)
    let letters = true
    for (let i = 0; i < keys.length; i++) if (keys[i].length !== 1) letters = false
    return keys.join(letters ? '' : ' ')
  }
  const ctrl = raw.indexOf('C-') === 0 && raw.length > 2
  let key = ctrl ? raw.slice(2) : raw
  const shift = ctrl && key.indexOf('S-') === 0 && key.length > 2
  if (shift) key = key.slice(2)
  const spelled = SPELLED[key] || key
  return ctrl ? 'ctrl+' + (shift ? 'shift+' : '') + spelled : spelled
}

/**
 * A binding for `action` -> the sequence it is read as, or null. Field and
 * panel keys are one named key or ctrl chord; reader keys may be anything.
 */
export function parseBinding (action, raw) {
  if (action.scope === 'reader') return parseSequence(raw)
  const chord = whole(parseKey(raw))
  if (chord === null) return null
  const named = SPELLED[chord] !== undefined && chord !== ' '
  return chord.indexOf('C-') === 0 || named ? chord : null   // 'C-S-x' counts
}

/** The stored text a binding round-trips to, or '' when it will not parse. */
export function normalizeBinding (action, raw) {
  const sequence = parseBinding(action, raw)
  return sequence === null ? '' : chordText(sequence)
}

/**
 * The keys the field and the panel are read with, by action id: `{ search:
 * 'Return', newSession: 'C-c', … }`. One object rather than a property per key,
 * so adding an action is an entry in ACTIONS and nothing else. Null settings —
 * or an unparseable one — give that key its default.
 */
/**
 * The two conversation keys as chords, for the field: it walks the ring in
 * normal mode as the answer does, so it has to know what they are bound to.
 * Single-character chords only — a two-key binding belongs to the panes, where
 * a pending prefix exists.
 */
export function chatChords (settings) {
  const chords = {}
  for (const id of ['nextChat', 'previousChat']) {
    const action = actionById(id)
    const raw = settings && settings[settingKey(action)] ? settings[settingKey(action)] : action.default
    const chord = parseBinding(action, raw) || parseBinding(action, action.default)
    if (chord && chord.length === 1) chords[id] = chord
  }
  return chords
}

export function panelChords (settings) {
  const chords = {}
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    if (action.scope === 'reader') continue
    const raw = settings ? settings[settingKey(action)] : ''
    chords[action.id] = parseChord(raw) || parseChord(action.default)
  }
  return chords
}
