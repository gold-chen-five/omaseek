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
  { id: 'settings', config: 'settings_key', default: 'ctrl+s', scope: 'panel', command: 'settings',
    label: 'Settings', hint: 'anywhere: open or close this page (ctrl+, always works too)' },
  { id: 'switchMode', config: 'switch_mode_key', default: 'tab', scope: 'panel', command: 'toggleMode',
    label: 'Switch search / ask', hint: 'anywhere: between searching and asking (shift+tab too)' },
  { id: 'open', config: 'open_key', default: 'enter', scope: 'reader', command: 'accept',
    label: 'Open', hint: 'results: the selected result · answer: the link under the cursor' },
  { id: 'handoff', config: 'handoff_key', default: 'ga', scope: 'reader', command: 'handOff',
    label: 'Hand off to agent', hint: 'the selected result, or the selection / reply under the cursor, as a draft' },
  { id: 'handoffAll', config: 'handoff_all_key', default: 'gA', scope: 'reader', command: 'handOffPage',
    label: 'Hand off everything', hint: 'the whole results page, or the whole conversation, as a draft' },
  { id: 'openLink', config: 'open_link_key', default: 'gx', scope: 'reader', panes: ['answer'], command: 'openLink',
    label: 'Open link', hint: 'answer: the URL under the cursor or in the selection, as vim’s gx' },
  { id: 'nextPage', config: 'next_page_key', default: 'l', scope: 'reader', panes: ['results'], command: 'nextPage',
    label: 'Next page', hint: 'results: the next page (→ too)' },
  { id: 'previousPage', config: 'previous_page_key', default: 'h', scope: 'reader', panes: ['results'], command: 'previousPage',
    label: 'Previous page', hint: 'results: the page before, from the cache (← too)' },
  { id: 'insert', config: 'insert_key', default: 'i', scope: 'reader', command: 'insert',
    label: 'Back to the field', hint: 'results and answer: return to the field with vim’s i (/ returns in normal mode; a appends)' }
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

// One key: a named key (any case), ctrl+ a key, or one character as typed.
function parseKey (token) {
  const text = String(token == null ? '' : token).trim()
  if (!text) return null
  const plus = text.indexOf('+')
  if (plus > 0 && plus < text.length - 1) {
    const modifier = text.slice(0, plus).trim().toLowerCase()
    if (modifier !== 'ctrl' && modifier !== 'control') return null   // only ctrl, for now
    const key = parseKey(text.slice(plus + 1))
    if (key === null || key === ' ' || key.indexOf('C-') === 0) return null
    // Ctrl+letter is spelled lowercase by chord.js, whatever shift says.
    return 'C-' + (key.length === 1 ? key.toLowerCase() : key)
  }
  const named = NAMED[text.toLowerCase()]
  if (named) return named
  return text.length === 1 ? text : null
}

/** "ctrl+c" -> "C-c", "enter" -> "Return", "G" -> "G". Null when it is not one key. */
export function parseChord (raw) {
  return parseKey(raw)
}

/**
 * A binding -> the sequence a keymap is keyed by: "gx" and "g x" -> "g x",
 * "ctrl+enter" -> "C-Return". Null when it is not a key or two keys.
 */
export function parseSequence (raw) {
  const text = String(raw == null ? '' : raw).trim()
  if (!text) return null
  const single = parseKey(text)
  if (single !== null) return single
  const tokens = /\s/.test(text) ? text.split(/\s+/) : (text.length === 2 ? [text[0], text[1]] : [])
  if (tokens.length !== 2) return null
  const keys = []
  for (let i = 0; i < tokens.length; i++) {
    const key = parseKey(tokens[i])
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
  const key = ctrl ? raw.slice(2) : raw
  const spelled = SPELLED[key] || key
  return ctrl ? 'ctrl+' + spelled : spelled
}

/**
 * A binding for `action` -> the sequence it is read as, or null. Field and
 * panel keys are one named key or ctrl chord; reader keys may be anything.
 */
export function parseBinding (action, raw) {
  if (action.scope === 'reader') return parseSequence(raw)
  const chord = parseKey(raw)
  if (chord === null) return null
  const named = SPELLED[chord] !== undefined && chord !== ' '
  return chord.indexOf('C-') === 0 || named ? chord : null
}

/** The stored text a binding round-trips to, or '' when it will not parse. */
export function normalizeBinding (action, raw) {
  const sequence = parseBinding(action, raw)
  return sequence === null ? '' : chordText(sequence)
}
