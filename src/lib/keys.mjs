// Which command a keypress is, for the panes that are read with vim keys.
//
// The result list and the answer view share a vocabulary — j/k step, h/l is
// whatever moving sideways means to that pane, gg/G are the two ends, Enter
// takes the thing under the cursor — and they used to say so in two
// forty-line if/else ladders that had already drifted apart in how they
// cleared a pending `g`. The tables below are the whole keymap; the pane
// says what each command *does*. A new key is one row here and one case
// there, in both panes or in neither.
//
// A chord is a string: a character ("j", "G", "$"), a named key ("Escape",
// "Down") or a control chord ("C-d"). A sequence is its chords joined by
// spaces, so gg is "g g". Qt's key enums become these in
// components/chord.js, which is separate because this file also loads in
// node, under test, where there is no Qt.
//
// VimTextField keeps its own dispatch: counts, operators and pending finds
// make it a different machine, and flattening it into a table would hide
// that rather than simplify it.

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

// The answer view is a text, so it also has the motions a text has, and a
// selection to make of them.
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
  'C-n': 'newSession'
})

function isPrefix (keymap, sequence) {
  const start = sequence + ' '
  for (const chord in keymap) {
    if (chord.length > start.length && chord.indexOf(start) === 0) return true
  }
  return false
}

// One keypress against a table. `pending` is what an earlier keypress left
// waiting — "g" after g — and comes back as the pending for the next one.
//
// An empty chord is a modifier held on its own; it must leave the pending
// sequence alone, or reaching for the shift in `gV` would cancel the g. A
// chord that begins nothing and completes nothing clears the pending
// sequence, the way a stray key does in vim.
export function resolve (keymap, pending, chord) {
  if (!chord) return { command: '', pending: pending || '' }
  const sequence = pending ? pending + ' ' + chord : chord
  const command = keymap[sequence]
  if (command) return { command: command, pending: '' }
  return { command: '', pending: isPrefix(keymap, sequence) ? sequence : '' }
}
