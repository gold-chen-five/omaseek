// The answer view's vim grammar, one keypress at a time: [count] y [count]
// motion, a text object after i or a, the character after f or t. It decides
// what the keys mean; AnswerView decides where that lands in its layout. y is
// the only operator: the transcript is read-only.

import { resolve } from './keys.mjs'

export const IDLE = Object.freeze({ keys: '', count: 0, before: 0, operator: '', find: '', scope: '' })

const FINDS = 'fFtT'

function sameFindKind (a, b) {
  return (a === 'f' || a === 'F') ? (b === 'f' || b === 'F')
    : (a === 't' || a === 'T') && (b === 't' || b === 'T')
}

function amend (state, changes) {
  const out = {
    keys: state.keys, count: state.count, before: state.before,
    operator: state.operator, find: state.find, scope: state.scope
  }
  for (const key in changes) out[key] = changes[key]
  return out
}

// 2y3w yanks six words: vim multiplies the count before the operator by the one after.
function total (state) {
  return Math.max(1, state.before) * Math.max(1, state.count)
}

function busy (state) {
  return state.keys !== '' || state.count > 0 || state.before > 0 ||
    state.operator !== '' || state.find !== '' || state.scope !== ''
}

function done (action) {
  return { state: IDLE, action }
}

/**
 * One chord against the grammar. `keymap` is the pane's table; `visual` is
 * whether a selection is up, which is when i and a start a text object rather
 * than leaving for the field. Returns { state, action }, the action null while
 * a sequence is half-typed or once it has been dropped. A command carries the
 * operator it was typed under; the view drops one that is not a motion.
 */
export function feed (state, chord, keymap, visual, activeFind = null) {
  if (!chord) return { state, action: null }             // a bare modifier

  if (state.find !== '') {
    if (chord.length !== 1) return done(null)
    return done({ type: 'find', command: state.find, char: chord, count: total(state), operator: state.operator })
  }
  if (state.scope !== '') {
    if (chord.length !== 1) return done(null)
    return done({ type: 'object', scope: state.scope, object: chord, operator: state.operator })
  }
  if (chord === 'Escape' && (busy(state) || activeFind)) return done(null)

  if (state.keys === '') {
    if ((chord >= '1' && chord <= '9' && chord.length === 1) || (chord === '0' && state.count > 0)) {
      return { state: amend(state, { count: state.count * 10 + Number(chord) }), action: null }
    }
    if (chord.length === 1 && FINDS.indexOf(chord) !== -1) {
      if (activeFind && state.operator === '' && sameFindKind(activeFind.command, chord)) {
        return done({ type: 'repeatFind', command: chord, count: total(state), operator: state.operator })
      }
      return { state: amend(state, { find: chord }), action: null }
    }
    if (chord === ';' || chord === ',') {
      return done({ type: 'repeatFind', reverse: chord === ',', count: total(state), operator: state.operator })
    }
    if ((chord === 'i' || chord === 'a') && (state.operator !== '' || visual)) {
      return { state: amend(state, { scope: chord }), action: null }
    }
    if (chord === 'y' && !visual) {
      if (state.operator === 'y') return done({ type: 'line', operator: 'y', count: total(state) })
      return { state: amend(state, { operator: 'y', before: state.count, count: 0 }), action: null }
    }
  }

  const step = resolve(keymap, state.keys, chord)
  if (step.pending) return { state: amend(state, { keys: step.pending }), action: null }
  if (!step.command) return done(null)
  return done({ type: 'command', command: step.command, count: total(state), operator: state.operator })
}

/**
 * An exclusive motion that ends at the start of a line stops at the end of the
 * one before, as vim's does: yw on a paragraph's last word takes the word, not
 * the break after it.
 */
export function trimExclusive (text, from, to) {
  let end = to
  while (end > from && text[end - 1] === '\n') end--
  return end
}
