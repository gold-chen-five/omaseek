// Keypress -> command name for the two panes read with vim keys (results, answer);
// each pane decides what a command does. A chord is "j", "Escape" or "C-d"; a
// sequence joins chords with spaces ("g g"). components/chord.js builds chords
// from Qt events, separately, because this file also runs under node.

function merge (...tables) {
  const out = {}
  for (let i = 0; i < tables.length; i++) {
    const table = tables[i]
    for (const chord in table) out[chord] = table[chord]
  }
  return out
}

// What both panes answer to, spelled once.
const NAV = {
  'C-s': 'settings',
  'C-,': 'settings',
  'Tab': 'toggleMode',
  'Backtab': 'toggleMode',
  'Return': 'accept',
  'Escape': 'cancel',
  'C-d': 'halfPageDown',
  'C-u': 'halfPageUp',
  'j': 'down', 'Down': 'down',
  'k': 'up', 'Up': 'up',
  'l': 'right', 'Right': 'right',
  'h': 'left', 'Left': 'left',
  'g g': 'top',
  'G': 'bottom',
  'i': 'insert',
  '/': 'insert'
}

export const LIST_KEYS = merge(NAV)

// The answer is text, so it adds motions and a selection.
export const ANSWER_KEYS = merge(NAV, {
  'w': 'wordForward', 'W': 'wordForwardBig',
  'b': 'wordBackward', 'B': 'wordBackwardBig',
  'e': 'wordEnd',
  '0': 'lineStart', '^': 'lineStart', 'Home': 'lineStart',
  '$': 'lineEnd', 'End': 'lineEnd',
  'v': 'selectChars',
  'V': 'selectLines',
  'g v': 'reselect',
  'y': 'yank',
  'g x': 'openLink'
})

function isPrefix (keymap, sequence) {
  const start = sequence + ' '
  for (const chord in keymap) {
    if (chord.length > start.length && chord.indexOf(start) === 0) return true
  }
  return false
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
