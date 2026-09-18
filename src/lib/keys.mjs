// Keypress -> command name for the two panes read with vim keys (results, answer);
// each pane decides what a command does. A chord is "j", "Escape" or "C-d"; a
// sequence joins chords with spaces ("g g"). components/chord.js builds chords
// from Qt events, separately, because this file also runs under node.
//
// A pane's table is its fixed keys — vim's own, spelled once below — plus the
// rebindable ones from settings (ACTIONS in keybinds.mjs). Indexed loops only:
// this runs in QML's JS engine too.

import { ACTIONS, PANES, appliesTo, parseBinding, settingKey, chordText, actionById } from './keybinds.mjs'

function merge (...tables) {
  const out = {}
  for (let i = 0; i < tables.length; i++) {
    const table = tables[i]
    for (const chord in table) out[chord] = table[chord]
  }
  return out
}

// What both panes answer to and settings cannot move.
const NAV = {
  'C-,': 'settings',
  'Backtab': 'toggleMode',
  'Escape': 'cancel',
  'C-d': 'halfPageDown',
  'C-u': 'halfPageUp',
  'j': 'down', 'Down': 'down',
  'k': 'up', 'Up': 'up',
  'g g': 'top',
  'G': 'bottom',
  // `/` searches the pane, as vim's does. Going back to the field is gi, gn,
  // i, a and esc — five ways already, which is what freed this one.
  '/': 'findForward',
  '?': 'findBackward',
  'n': 'findNext',
  'N': 'findPrevious',
  'i': 'insert',
  'a': 'append'
}

const FIXED = {
  results: merge(NAV, {
    'Right': 'nextPage', 'Left': 'previousPage', 'y': 'yankUrl', 'Y': 'yankCitation',
    // A count says which page: 5gp is page five, gp is page one. The answer has
    // no pages, so this one is the results' alone.
    'g p': 'goToPage'
  }),
  // The answer is text, so it adds motions and a selection.
  answer: merge(NAV, {
    'l': 'right', 'Right': 'right',
    'h': 'left', 'Left': 'left',
    'w': 'wordForward', 'W': 'wordForwardBig',
    'b': 'wordBackward', 'B': 'wordBackwardBig',
    'e': 'wordEnd',
    'E': 'wordEndBig',
    '0': 'lineStart', '^': 'lineStart', '_': 'lineStart', 'Home': 'lineStart',
    '$': 'lineEnd', 'End': 'lineEnd',
    'v': 'selectChars',
    'V': 'selectLines',
    // The results have no cursor inside a row, so there is no word under it.
    '*': 'searchWord',
    '#': 'searchWordBack',
    'g v': 'reselect',
    'y': 'yank',
    'p': 'put', 'P': 'putBefore',
    // Stops the reply being written, as the field's q and esc do; macros are
    // deliberately absent, so vim's q is free.
    'q': 'stopAnswer'
  })
}

// Keys a pane takes before its table is consulted: counts in both, and in the
// answer the grammar's finds, y, and the a of a text object.
const TAKEN_FIRST = { results: '123456789', answer: '123456789fFtT;,ya' }

// What the field does with keys before any binding sees them.
const FIELD_FIXED = {
  'Escape': 'cancel', 'C-w': 'deleteWord', 'C-u': 'deleteLine', 'C-j': 'lineBreak',
  'C-r': 'redo', 'Up': 'up', 'Down': 'down', 'C-,': 'settings', 'Backtab': 'toggleMode'
}

// Names for the settings page when it refuses a key.
const LABELS = {
  settings: 'settings', toggleMode: 'switch search / ask', cancel: 'esc',
  nextSession: 'the next session', previousSession: 'the session before', closeSession: 'close the session',
  clearSessions: 'delete all sessions', stopAnswer: 'stop the answer', retryAnswer: 'retry the answer',
  halfPageDown: 'half a screen down', halfPageUp: 'half a screen up',
  down: 'move down', up: 'move up', right: 'move right', left: 'move left',
  top: 'go to the top', bottom: 'go to the bottom',
  fieldNormal: 'back to the field in normal mode', insert: 'insert before the cursor', append: 'insert after the cursor',
  findForward: 'search the pane', findBackward: 'search the pane backwards',
  findNext: 'the next match', findPrevious: 'the match before',
  searchWord: 'search for the word under the cursor', searchWordBack: 'search back for the word under the cursor',
  nextPage: 'next page', previousPage: 'previous page', goToPage: 'jump to a page',
  wordForward: 'a word motion', wordForwardBig: 'a word motion', wordBackward: 'a word motion',
  wordBackwardBig: 'a word motion', wordEnd: 'a word motion', wordEndBig: 'a word motion',
  lineStart: 'line start', lineEnd: 'line end', selectChars: 'visual mode', selectLines: 'linewise visual',
  reselect: 'reselect', yank: 'yank', put: 'put', putBefore: 'put',
  yankUrl: 'yank the URL', yankCitation: 'yank the title and URL',
  askAbout: 'ask about this result', searchFor: 'search the web for this',
  deleteWord: 'delete a word', deleteLine: 'delete to the line start', lineBreak: 'a line break', redo: 'redo'
}

const PANE_NAMES = { field: 'the field', results: 'the results', answer: 'the answer' }

/** A pane's keymap: its fixed keys plus the rebindable ones, as `binds` (the settings) has them. */
export function readerKeys (pane, binds) {
  const keys = merge(FIXED[pane] || {})
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    if (!action.command || !appliesTo(action, pane)) continue
    const raw = binds && binds[settingKey(action)] ? binds[settingKey(action)] : action.default
    const sequence = parseBinding(action, raw) || parseBinding(action, action.default)
    keys[sequence] = action.command
  }
  // Fixed Vim keys stay fixed even if a hand-edited or older config collides.
  return merge(keys, FIXED[pane] || {})
}

// The tables with every key at its default.
export const LIST_KEYS = readerKeys('results', null)
export const ANSWER_KEYS = readerKeys('answer', null)

function keysOf (sequence) {
  return sequence === ' ' ? [' '] : sequence.split(' ')
}

// Two bindings collide when one is the other or begins it: with gx bound, a g
// on its own would never be seen.
function collides (a, b) {
  const x = keysOf(a)
  const y = keysOf(b)
  const n = Math.min(x.length, y.length)
  for (let i = 0; i < n; i++) if (x[i] !== y[i]) return false
  return true
}

/**
 * Why `raw` cannot be the key for action `id`, given the other bindings in
 * `binds` (settings-shaped: handoffKey …), or '' when it can.
 */
export function bindingProblem (id, raw, binds) {
  const action = actionById(id)
  if (!action) return 'not a key this page knows'
  const sequence = parseBinding(action, raw)
  if (sequence === null) {
    return action.scope === 'reader'
      ? 'not a key — try enter, ctrl+o, a letter, or two keys such as gx'
      : 'use a named key or a ctrl chord (enter, tab, ctrl+o) — a letter here could never be typed'
  }
  const text = chordText(sequence)
  const panes = ['field'].concat(PANES)
  for (let p = 0; p < panes.length; p++) {
    const pane = panes[p]
    if (!appliesTo(action, pane)) continue
    const fixed = pane === 'field' ? FIELD_FIXED : FIXED[pane]
    for (const chord in fixed) {
      if (collides(sequence, chord)) return `${text} is taken in ${PANE_NAMES[pane]}: ${LABELS[fixed[chord]] || fixed[chord]}`
    }
    const first = keysOf(sequence)[0]
    if (pane !== 'field' && first.length === 1 && TAKEN_FIRST[pane].indexOf(first) !== -1) {
      return `${text} is taken in ${PANE_NAMES[pane]}: ${first >= '1' && first <= '9' ? 'a count' : 'vim uses ' + first}`
    }
  }
  for (let i = 0; i < ACTIONS.length; i++) {
    const other = ACTIONS[i]
    if (other.id === id) continue
    let shared = false
    for (let p = 0; p < panes.length; p++) if (appliesTo(action, panes[p]) && appliesTo(other, panes[p])) shared = true
    if (!shared) continue
    const theirs = parseBinding(other, binds && binds[settingKey(other)] ? binds[settingKey(other)] : other.default)
    if (theirs !== null && collides(sequence, theirs)) return `${text} is already ${other.label}`
  }
  return ''
}

// One keypress against a table; `pending` carries a half-typed sequence ("g").
// A bare modifier (empty chord) keeps it; a chord that leads nowhere clears it.
export function resolve (keymap, pending, chord) {
  if (!chord) return { command: '', pending: pending || '' }
  const sequence = pending ? pending + ' ' + chord : chord
  const command = keymap[sequence]
  if (command) return { command: command, pending: '' }
  return { command: '', pending: isPrefix(keymap, sequence) ? sequence : '' }
}

function isPrefix (keymap, sequence) {
  const start = sequence + ' '
  for (const chord in keymap) {
    if (chord.length > start.length && chord.indexOf(start) === 0) return true
  }
  return false
}

// Results only need counts and key sequences, without the text/yank grammar.
export function resolveCounted (keymap, state, chord) {
  if (!chord) return { state, command: '', count: 1 }
  if (!state.pending && (/^[1-9]$/.test(chord) || (chord === '0' && state.count > 0))) {
    return { state: { pending: '', count: Math.min(99999, state.count * 10 + Number(chord)) }, command: '', count: 1 }
  }
  const step = resolve(keymap, state.pending, chord)
  const cancelled = chord === 'Escape' && (state.pending || state.count > 0)
  return {
    state: { pending: step.pending, count: step.pending ? state.count : 0 },
    command: cancelled ? '' : step.command,
    count: Math.max(1, state.count)
  }
}
