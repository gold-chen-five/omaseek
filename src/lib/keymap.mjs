// The insert-mode escape sequence — vim's `inoremap jk <Esc>` — and the user
// config that decides which sequence is live.
//
// Pure: keys and config text in, a decision out, with no QML or Qt dependency,
// so the matching rules run under node. See test/keymap.test.mjs.

export const DEFAULT_SEQUENCES = ['jk']
export const DEFAULT_TIMEOUT_MS = 200

const MIN_TIMEOUT_MS = 20
const MAX_TIMEOUT_MS = 5000

/**
 * `~/.config/jonas.search/config.json` -> the escape sequences and the window
 * they must be typed within.
 *
 * Anything unreadable — no file, malformed JSON, a key of the wrong type —
 * falls back to the defaults rather than failing: a typo in the config should
 * cost the setting, not the search bar.
 */
export function readKeymap (source) {
  const config = parseConfig(source)
  return {
    sequences: readSequences(config.escape_sequence),
    timeoutMs: readTimeout(config.escape_timeout_ms)
  }
}

function parseConfig (source) {
  if (typeof source !== 'string' || source.trim() === '') return {}
  try {
    const parsed = JSON.parse(source)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch (error) {
    return {}
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
 * One insert-mode keystroke against the keys pending so far.
 *
 * Returns the buffer to carry forward, whether a sequence just completed, and
 * how many characters the caller must take back out of the field: the closing
 * key is swallowed before it types, but the ones before it are already on
 * screen — vim shows that leading `j` too, then removes it.
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
