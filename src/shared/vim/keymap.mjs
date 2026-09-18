// The insert-mode escape sequence (vim's `inoremap jk <Esc>`) and its config.

import { parseObject } from '../json.mjs'

export const DEFAULT_SEQUENCES = ['jk']
// vim's `timeoutlen`: keys typed within it count as one mapping.
export const DEFAULT_TIMEOUT_MS = 1000

const MIN_TIMEOUT_MS = 20
const MAX_TIMEOUT_MS = 5000

/** config.json -> the escape sequences and their timeout; unreadable config means defaults. */
export function readKeymap (source) {
  const config = parseObject(source)
  return {
    sequences: readSequences(config.escape_sequence),
    timeoutMs: readTimeout(config.escape_timeout_ms)
  }
}

/**
 * A string is one sequence, an array is several (`jk` and `kj` both), and
 * `""`, `null` or `[]` turns the escape sequence off. Single characters are
 * dropped — a one-key sequence would make that key untypable.
 */
function readSequences (raw) {
  if (raw === undefined) return [...DEFAULT_SEQUENCES]
  const list = Array.isArray(raw) ? raw : [raw]
  return list.filter(entry => typeof entry === 'string' && entry.length >= 2)
}

function readTimeout (raw) {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return DEFAULT_TIMEOUT_MS
  return Math.min(MAX_TIMEOUT_MS, Math.max(MIN_TIMEOUT_MS, Math.round(raw)))
}

/** Keys that type a character — the only ones a sequence can be built from. */
export function isTypedKey (key) {
  if (typeof key !== 'string' || key.length !== 1) return false
  const code = key.charCodeAt(0)
  return code >= 32 && code !== 127
}

/**
 * One insert-mode keystroke against the pending keys. Returns the buffer to carry
 * forward, whether a sequence completed, and how many typed characters to take back.
 */
export function advance (pending, key, sequences) {
  const idle = { pending: '', escaped: false, strip: 0 }
  if (!Array.isArray(sequences) || sequences.length === 0) return idle
  if (!isTypedKey(key)) return idle

  const candidate = (pending || '') + key
  if (sequences.indexOf(candidate) !== -1) {
    return { pending: '', escaped: true, strip: candidate.length - 1 }
  }

  // A broken sequence still leaves a start behind: `jjk` escapes on the second
  // `j`, because the longest tail that opens a sequence carries forward.
  for (let start = 0; start < candidate.length; start++) {
    const tail = candidate.slice(start)
    if (sequences.some(sequence => sequence.startsWith(tail))) {
      return { pending: tail, escaped: false, strip: 0 }
    }
  }
  return idle
}
