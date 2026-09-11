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

/** `^` — first non-blank character. */
export function firstNonBlank (text) {
  for (let i = 0; i < text.length; i++) {
    if (charClass(text, i) !== BLANK) return i
  }
  return 0
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

/** The inverse of a find command, for `,`. */
export function flipFind (command) {
  return { f: 'F', F: 'f', t: 'T', T: 't' }[command] ?? command
}

/** Normal mode keeps the cursor on a character, never past the last one. */
export function clampToLine (text, pos) {
  if (text.length === 0) return 0
  return Math.max(0, Math.min(pos, text.length - 1))
}

/** Applies a motion `count` times, e.g. `3w`. */
export function repeat (motion, count, pos) {
  let at = pos
  for (let i = 0; i < count; i++) at = motion(at)
  return at
}
