// Cursor motions over one line: (text, position) -> position. Pure; under test.

const WORD_CHAR = /[A-Za-z0-9_]/

export const BLANK = 0
export const WORD = 1
export const PUNCT = 2

/** Vim's three character classes. WORD motions (`W`, `B`, `E`) fold PUNCT into WORD. */
export function charClass (text, index, big = false) {
  if (index < 0 || index >= text.length) return BLANK
  const char = text[index]
  if (char === ' ' || char === '\t') return BLANK
  if (big) return WORD
  return WORD_CHAR.test(char) ? WORD : PUNCT
}

/** `w` — start of the next word. */
export function wordForward (text, pos, big = false) {
  const end = text.length
  if (pos >= end) return end

  let at = pos
  const startClass = charClass(text, at, big)
  if (startClass !== BLANK) {
    while (at < end && charClass(text, at, big) === startClass) at++
  }
  while (at < end && charClass(text, at, big) === BLANK) at++
  return at
}

/** `b` — start of the previous word. */
export function wordBackward (text, pos, big = false) {
  if (pos <= 0) return 0

  let at = pos - 1
  while (at > 0 && charClass(text, at, big) === BLANK) at--

  const runClass = charClass(text, at, big)
  while (at > 0 && charClass(text, at - 1, big) === runClass) at--
  return at
}

/** `e` — end of the current or next word. */
export function wordEnd (text, pos, big = false) {
  const end = text.length
  if (end === 0) return 0
  if (pos >= end - 1) return end - 1

  let at = pos + 1
  while (at < end && charClass(text, at, big) === BLANK) at++
  if (at >= end) return end - 1

  const runClass = charClass(text, at, big)
  while (at + 1 < end && charClass(text, at + 1, big) === runClass) at++
  return at
}

/** `^` `_` — first non-blank character of the line holding pos; its start when it is all blank. */
export function firstNonBlank (text, pos = 0) {
  const bounds = lineBounds(text, Math.max(0, Math.min(pos, text.length)))
  for (let i = bounds.start; i < bounds.end; i++) {
    if (charClass(text, i) !== BLANK) return i
  }
  return bounds.start
}

/** A count on `$` or `_` reaches count - 1 lines down, stopping at the last. */
export function linesDown (text, pos, count) {
  let at = pos
  for (let i = 1; i < count; i++) {
    const next = lineDown(text, at)
    if (next < 0) break
    at = next
  }
  return at
}

/**
 * `f` `F` `t` `T` — character search. Returns -1 when the target is absent,
 * which callers treat as a failed motion that cancels any pending operator.
 */
export function find (text, pos, command, target) {
  const end = text.length

  if (command === 'f' || command === 't') {
    for (let i = pos + 1; i < end; i++) {
      if (text[i] === target) return command === 'f' ? i : i - 1
    }
  } else {
    for (let i = pos - 1; i >= 0; i--) {
      if (text[i] === target) return command === 'F' ? i : i + 1
    }
  }
  return -1
}

/**
 * Whether two find commands walk the same way — f with F, t with T. Clever-f
 * repeats only within a kind: after `fa`, F steps back through the same a's,
 * but t starts a new find.
 */
export function sameFindKind (a, b) {
  return (a === 'f' || a === 'F') ? (b === 'f' || b === 'F')
    : (a === 't' || a === 'T') && (b === 't' || b === 'T')
}

/** The inverse of a find command, for `,`. */
export function flipFind (command) {
  return { f: 'F', F: 'f', t: 'T', T: 't' }[command] ?? command
}

/** Normal mode stays on a character, or at the sole position of an empty line. */
export function clampToLine (text, pos) {
  const at = Math.max(0, Math.min(pos, text.length))
  const bounds = lineBounds(text, at)
  if (bounds.start === bounds.end) return bounds.start
  return Math.max(bounds.start, Math.min(at, bounds.end - 1))
}

/** Vim steps left on leaving insert mode, but never onto the previous line. */
export function insertExit (text, pos) {
  const at = Math.max(0, Math.min(pos, text.length))
  if (at === 0) return 0
  return '\r\n\u2028\u2029'.indexOf(text[at - 1]) === -1 ? at - 1 : at
}

/** Applies a motion `count` times, e.g. `3w`. */
export function repeat (motion, count, pos) {
  let at = pos
  for (let i = 0; i < count; i++) at = motion(at)
  return at
}

/** j or Down inside a question of several lines: the same column on the next line, or -1 on the last. */
export function lineDown (text, pos) {
  const nl = text.indexOf('\n', pos)
  if (nl === -1) return -1
  const lineStart = pos === 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1
  const column = pos - lineStart
  const nextEnd = text.indexOf('\n', nl + 1)
  const nextLength = (nextEnd === -1 ? text.length : nextEnd) - (nl + 1)
  return nl + 1 + Math.min(column, nextLength)
}

/** k or Up: the same column on the line above, or -1 on the first. */
export function lineUp (text, pos) {
  const lineStart = pos === 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1
  if (lineStart === 0) return -1
  const column = pos - lineStart
  const prevStart = lineStart - 2 < 0 ? 0 : text.lastIndexOf('\n', lineStart - 2) + 1
  const prevLength = (lineStart - 1) - prevStart
  return prevStart + Math.min(column, prevLength)
}

/** The line holding pos, in text of several: [start, end), its break left out. */
export function lineBounds (text, pos) {
  const start = pos <= 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1
  const nl = text.indexOf('\n', pos)
  return { start, end: nl === -1 ? text.length : nl }
}

/** A logical column on the line holding pos, clamped to its last character. */
export function positionAtColumn (text, pos, column) {
  const at = Math.max(0, Math.min(pos, text.length))
  const bounds = lineBounds(text, at)
  const length = bounds.end - bounds.start
  if (length === 0) return bounds.start
  return bounds.start + Math.min(Math.max(0, column), length - 1)
}

/**
 * `f` `F` `t` `T` within the line holding pos, `count` times; -1 when it runs
 * out. Repeated (`again`, for ; and ,) a t or T already beside its character
 * looks past it rather than standing still, as vim's does.
 */
export function findInLine (text, pos, command, target, count = 1, again = false) {
  const { start, end } = lineBounds(text, pos)
  const forward = command === 'f' || command === 't'
  const step = forward ? 1 : -1
  let hit = again && (command === 't' || command === 'T') ? pos + step : pos
  for (let n = 0; n < count; n++) {
    let i = hit + step
    while (i >= start && i < end && text[i] !== target) i += step
    if (i < start || i >= end) return -1
    hit = i
  }
  if (command === 't') return hit - 1
  if (command === 'T') return hit + 1
  return hit
}

/** The matched character for a find landing; t/T leave the cursor beside it. */
export function findMatchPosition (landing, command) {
  if (landing < 0) return -1
  if (command === 't') return landing + 1
  if (command === 'T') return landing - 1
  return landing
}

/** Every occurrence of target on the logical line containing pos. */
export function matchingCharsInLine (text, pos, target) {
  if (typeof target !== 'string' || target.length !== 1) return []
  const bounds = lineBounds(text, pos)
  const matches = []
  for (let i = bounds.start; i < bounds.end; i++) if (text[i] === target) matches.push(i)
  return matches
}

/** Whole logical lines starting at the cursor, including their following break. */
export function lineRange (text, pos, count = 1) {
  const start = lineBounds(text, pos).start
  let end = start
  for (let i = 0; i < Math.max(1, count); i++) {
    const nl = text.indexOf('\n', end)
    end = nl === -1 ? text.length : nl + 1
    if (end >= text.length) break
  }
  return { start, end }
}
