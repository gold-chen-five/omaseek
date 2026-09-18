// Searching the text of the two panes that are read: the prompt's little state
// machine, where the matches are, and which one a step lands on. Pure and under
// test; each pane decides what to do with a position.
//
// `/` used to mean "back to the field". It means this now — gi and gn go back,
// in insert and in normal mode, and esc still does.

import { escapeHtml } from '../html.mjs'

export const IDLE = Object.freeze({ active: false, backward: false, pattern: '' })

/** `/` and `?`: an open prompt with nothing typed into it yet. */
export function openFind (backward) {
  return { active: true, backward: backward === true, pattern: '' }
}

function typed (state, pattern) {
  return { state: { active: true, backward: state.backward, pattern: pattern }, action: 'typing' }
}

function isTypable (text) {
  if (typeof text !== 'string' || text.length !== 1) return false
  const code = text.charCodeAt(0)
  return code >= 0x20 && code !== 0x7f       // a printable character, not a control one
}

/**
 * One keystroke while the prompt is open. `key` names the keys that are not
 * text ('Return', 'Escape', 'Backspace'); `text` is the character typed.
 * Returns the new state and one of '' | 'typing' | 'accept' | 'cancel'.
 *
 * Backspace past the start closes the prompt, as vim's does: the pattern is
 * gone, so there is nothing left to be searching for.
 */
export function feedFind (state, key, text) {
  const current = state && state.active ? state : IDLE
  if (!current.active) return { state: IDLE, action: '' }
  if (key === 'Escape') return { state: IDLE, action: 'cancel' }
  if (key === 'Return') return { state: IDLE, action: current.pattern ? 'accept' : 'cancel' }
  if (key === 'Backspace') {
    if (current.pattern === '') return { state: IDLE, action: 'cancel' }
    return typed(current, current.pattern.slice(0, current.pattern.length - 1))
  }
  if (!isTypable(text)) return { state: current, action: '' }
  return typed(current, current.pattern + text)
}

/** What the status line shows while the prompt is open: `/rust`, `?rust`. */
export function promptText (state) {
  if (!state || !state.active) return ''
  return (state.backward ? '?' : '/') + state.pattern
}

const WORD = /[0-9A-Za-z_]/

function isWordChar (ch) {
  return typeof ch === 'string' && ch !== '' && WORD.test(ch)
}

/**
 * The word `*` searches for: the one under `pos`, or — when the cursor sits on
 * a space, as vim's does — the next one along the same line. '' when there is
 * no word left on it.
 */
export function wordAt (text, pos) {
  const source = String(text == null ? '' : text)
  let at = Math.max(0, Math.min(source.length, pos))
  // Along this line only: a word on the next one is not under the cursor.
  while (at < source.length && source.charAt(at) !== '\n' && !isWordChar(source.charAt(at))) at++
  if (at >= source.length || !isWordChar(source.charAt(at))) return ''
  let start = at
  while (start > 0 && isWordChar(source.charAt(start - 1))) start--
  let end = at
  while (end < source.length && isWordChar(source.charAt(end))) end++
  return source.slice(start, end)
}

// charAt past either end answers '', which is not a word character, so the
// first and last matches in the text are whole words by default.
function isWholeWord (source, at, width) {
  return !isWordChar(source.charAt(at - 1)) && !isWordChar(source.charAt(at + width))
}

/** Vim's smartcase: an uppercase anywhere in the pattern makes it case-sensitive. */
export function caseSensitive (pattern) {
  const text = String(pattern == null ? '' : pattern)
  return text !== text.toLowerCase()
}

/**
 * Every place `pattern` occurs in `text`, in order. Overlaps count. With
 * `wholeWord` — what `*` searches with — a match inside a longer word does
 * not: that is the whole difference between `*` and typing the word after `/`.
 */
export function matchPositions (text, pattern, wholeWord) {
  const positions = []
  const needle = String(pattern == null ? '' : pattern)
  if (needle === '') return positions
  const source = String(text == null ? '' : text)
  const exact = caseSensitive(needle)
  const haystack = exact ? source : source.toLowerCase()
  const find = exact ? needle : needle.toLowerCase()
  let at = haystack.indexOf(find)
  while (at !== -1) {
    if (!wholeWord || isWholeWord(source, at, find.length)) positions.push(at)
    at = haystack.indexOf(find, at + 1)
  }
  return positions
}

/**
 * One step from `from`, wrapping around the text as vim's search does.
 * `inclusive` lets a match sitting exactly on `from` count, which is what the
 * incremental jump wants while the pattern is still being typed — the reader
 * has not moved, so the match under the cursor is the one to show.
 */
export function matchFrom (positions, from, backward, inclusive) {
  const list = positions || []
  if (list.length === 0) return -1
  if (backward) {
    for (let i = list.length - 1; i >= 0; i--) {
      if (inclusive ? list[i] <= from : list[i] < from) return list[i]
    }
    return list[list.length - 1]              // wrap to the last
  }
  for (let i = 0; i < list.length; i++) {
    if (inclusive ? list[i] >= from : list[i] > from) return list[i]
  }
  return list[0]                              // wrap to the first
}

/** `n` and `N`, with a count: `3n` is three steps on. */
export function nextMatch (positions, from, backward, count) {
  const times = Math.max(1, count || 1)
  let at = from
  for (let i = 0; i < times; i++) {
    const step = matchFrom(positions, at, backward, false)
    if (step === -1) return -1
    at = step
  }
  return at
}

/**
 * `text` as StyledText with every match of `pattern` marked bold, and coloured
 * when a colour is given. The rows are plain Text elements with no layout to
 * draw rectangles behind, the way the answer's matches are lit, so the mark
 * goes in the text itself.
 *
 * Everything is escaped, match or not: from here on the string is read as
 * markup, and a result titled "Tom & Jerry" must not become one.
 */
export function markMatches (text, pattern, color) {
  const source = String(text == null ? '' : text)
  const at = matchPositions(source, pattern)
  if (at.length === 0) return escapeHtml(source)
  const width = String(pattern).length
  const open = (color ? '<font color="' + color + '">' : '') + '<b>'
  const close = '</b>' + (color ? '</font>' : '')
  let out = ''
  let from = 0
  for (let i = 0; i < at.length; i++) {
    if (at[i] < from) continue                // an overlapping match is already inside one
    out += escapeHtml(source.slice(from, at[i]))
    out += open + escapeHtml(source.substr(at[i], width)) + close
    from = at[i] + width
  }
  return out + escapeHtml(source.slice(from))
}

/**
 * Which result rows match, for the pane that has rows rather than text. Row
 * indices are sorted ints like text offsets, so matchFrom and nextMatch step
 * through them unchanged.
 */
export function matchingRows (rows, pattern) {
  const list = rows || []
  const found = []
  if (String(pattern == null ? '' : pattern) === '') return found
  for (let i = 0; i < list.length; i++) {
    const row = list[i] || {}
    const haystack = [row.title, row.snippet, row.display_url, row.url].join('\n')
    if (matchPositions(haystack, pattern).length > 0) found.push(i)
  }
  return found
}
