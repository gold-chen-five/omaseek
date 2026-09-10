// vim text objects over a single line: iw, aw, i", a(, and the rest.
//
// Pure — text and a cursor in, a range out — so every case runs under node.
// See test/textobjects.test.mjs.

import { charClass, BLANK } from './motions.mjs'

const PAIRS = {
  '(': ['(', ')'], ')': ['(', ')'], b: ['(', ')'],
  '[': ['[', ']'], ']': ['[', ']'],
  '{': ['{', '}'], '}': ['{', '}'], B: ['{', '}'],
  '<': ['<', '>'], '>': ['<', '>']
}

const QUOTES = ['"', "'", '`']

/**
 * Every object this understands, for the caller to validate a keystroke.
 *
 * A plain lookup rather than Object.hasOwn: QML's JS engine does not have it,
 * and node does, so the difference only shows at runtime in the shell.
 */
export function isTextObject (key) {
  return key === 'w' || key === 'W' || QUOTES.indexOf(key) !== -1 || PAIRS[key] !== undefined
}

/** The run of same-class characters the cursor sits in. */
function wordRange (text, pos, big) {
  const at = Math.min(pos, Math.max(0, text.length - 1))
  const cls = charClass(text, at, big)

  let start = at
  while (start > 0 && charClass(text, start - 1, big) === cls) start--
  let end = at
  while (end + 1 < text.length && charClass(text, end + 1, big) === cls) end++
  return { start, end: end + 1 }
}

/**
 * `aw` is the word plus the whitespace after it, or before it when the word
 * ends the line — which is what makes `daw` leave one gap rather than two.
 */
function aroundWord (text, pos, big) {
  const inner = wordRange(text, pos, big)

  let end = inner.end
  while (end < text.length && charClass(text, end, big) === BLANK) end++
  if (end > inner.end) return { start: inner.start, end }

  let start = inner.start
  while (start > 0 && charClass(text, start - 1, big) === BLANK) start--
  return { start, end: inner.end }
}

/**
 * Quotes pair off from the start of the line, as vim does: the first with the
 * second, the third with the fourth. The cursor uses the pair it is inside,
 * or the next one along if it is sitting before them.
 */
function quoteRange (text, pos, quote) {
  const marks = []
  for (let i = 0; i < text.length; i++) {
    if (text[i] === quote) marks.push(i)
  }

  for (let i = 0; i + 1 < marks.length; i += 2) {
    const open = marks[i]
    const close = marks[i + 1]
    if (pos <= close) return { open, close }
  }
  return null
}

/** The innermost pair enclosing the cursor, counting depth both ways. */
function bracketRange (text, pos, open, close) {
  let depth = 0
  let start = -1
  for (let i = Math.min(pos, text.length - 1); i >= 0; i--) {
    const char = text[i]
    if (char === close && i !== pos) depth++
    else if (char === open) {
      if (depth === 0) { start = i; break }
      depth--
    }
  }
  if (start === -1) return null

  depth = 0
  let end = -1
  for (let i = start + 1; i < text.length; i++) {
    const char = text[i]
    if (char === open) depth++
    else if (char === close) {
      if (depth === 0) { end = i; break }
      depth--
    }
  }
  return end === -1 ? null : { open: start, close: end }
}

/**
 * A text object as a half-open range, or null when there is nothing to act on
 * — a missing closing bracket, or a quote that never opens. Callers treat null
 * as a failed motion and drop the pending operator, which is what vim does.
 *
 * `scope` is 'i' for inner or 'a' for around.
 */
export function resolve (text, pos, scope, object) {
  if (typeof text !== 'string' || text.length === 0) return null
  const at = Math.max(0, Math.min(pos, text.length - 1))

  if (object === 'w' || object === 'W') {
    const big = object === 'W'
    return scope === 'a' ? aroundWord(text, at, big) : wordRange(text, at, big)
  }

  if (QUOTES.indexOf(object) !== -1) {
    const found = quoteRange(text, at, object)
    if (!found) return null
    if (scope === 'i') {
      return found.close > found.open + 1
        ? { start: found.open + 1, end: found.close }
        : { start: found.open + 1, end: found.open + 1 }   // "" — an empty inside
    }
    // `a` takes the quotes too, plus trailing whitespace when there is any.
    let end = found.close + 1
    while (end < text.length && charClass(text, end) === BLANK) end++
    return { start: found.open, end }
  }

  const pair = PAIRS[object]
  if (!pair) return null
  const found = bracketRange(text, at, pair[0], pair[1])
  if (!found) return null
  return scope === 'i'
    ? { start: found.open + 1, end: found.close }
    : { start: found.open, end: found.close + 1 }
}
