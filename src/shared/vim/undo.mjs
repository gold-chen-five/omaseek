// Vim's undo for the field: one step per change, not per keystroke. A change is
// a normal-mode command, or a whole visit to insert mode together with the
// command that opened it — ciw, the word typed, and the jk that left, are one
// `u`. Qt's own undo records each edit, so the j that jk types and takes back
// was a step of its own, and `u` after `ciw…jk` only brought the j back.
//
// Texts, not diffs: the field is a line or a question, so a whole copy per step
// is cheap. `saved` is the text as of the last boundary; `record` at a boundary
// turns whatever changed since into one step. Indexed loops and slice/concat
// only: this runs in QML's JS engine too.

export const LIMIT = 100

export function start (text) {
  return { undo: [], redo: [], saved: String(text) }
}

/** A boundary: what changed since the last one becomes one step, and redo is gone. */
export function record (state, text) {
  if (text === state.saved) return state
  const undo = state.undo.concat([state.saved])
  return { undo: undo.length > LIMIT ? undo.slice(undo.length - LIMIT) : undo, redo: [], saved: text }
}

/** `u` (a count undoes several): the state after, and the text to show; null when there is nothing to undo. */
export function undo (state, text, count = 1) {
  return walk(record(state, text), text, count, 'undo', 'redo')
}

/** ctrl+r: the reverse. An edit since the last undo has already cleared it. */
export function redo (state, text, count = 1) {
  return walk(record(state, text), text, count, 'redo', 'undo')
}

function walk (state, text, count, from, to) {
  let s = state
  let current = text
  let moved = 0
  for (let i = 0; i < Math.max(1, count); i++) {
    const stack = s[from]
    if (stack.length === 0) break
    const next = stack[stack.length - 1]
    const out = {}
    out[from] = stack.slice(0, stack.length - 1)
    out[to] = s[to].concat([current])
    out.saved = next
    s = out
    current = next
    moved++
  }
  return moved === 0 ? null : { state: s, text: current }
}

/** Where two texts first differ — where vim leaves the cursor after an undo or redo. */
export function changeStart (before, after) {
  let i = 0
  while (i < before.length && i < after.length && before[i] === after[i]) i++
  return i
}
