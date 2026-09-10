// The keys behind the panel's two buttons, as a person writes them.
//
// Settings holds them as text — "ctrl+c", "enter" — because that is what a
// keybind looks like everywhere else a person edits one. The panel matches
// against the chord strings components/chord.js produces, so this is the
// translation between the two, and the only place either spelling is known.
//
// The vocabulary is deliberately small: a named key, a single character, or
// ctrl and one of those. Anything else parses to null and the setting keeps
// the value it had, the way a one-character escape sequence is refused
// rather than silently accepted.

const NAMED = {
  enter: 'Return', return: 'Return',
  esc: 'Escape', escape: 'Escape',
  tab: 'Tab',
  space: 'Space',
  up: 'Up', down: 'Down', left: 'Left', right: 'Right',
  home: 'Home', end: 'End'
}

const SPELLED = {
  Return: 'enter', Escape: 'esc', Tab: 'tab', Space: 'space',
  Up: 'up', Down: 'down', Left: 'left', Right: 'right',
  Home: 'home', End: 'end'
}

export const DEFAULT_BINDS = {
  search: 'enter',
  newChat: 'ctrl+c'
}

/** "ctrl+c" -> "C-c", "enter" -> "Return". Null when it is not a chord. */
export function parseChord (raw) {
  const text = String(raw == null ? '' : raw).trim().toLowerCase()
  if (!text) return null

  const parts = text.split('+')
  let ctrl = false
  while (parts.length > 1) {
    const part = parts[0].trim()
    if (part !== 'ctrl' && part !== 'control') return null   // only ctrl, for now
    ctrl = true
    parts.shift()
  }

  const key = parts[0].trim()
  if (!key) return null
  const named = NAMED[key]
  if (named) return ctrl ? 'C-' + named : named
  if (key.length !== 1) return null
  return ctrl ? 'C-' + key : key
}

/** "C-c" -> "ctrl+c", for showing a chord back in the settings row. */
export function chordText (chord) {
  const raw = String(chord == null ? '' : chord)
  if (!raw) return ''
  const ctrl = raw.indexOf('C-') === 0
  const key = ctrl ? raw.slice(2) : raw
  const spelled = SPELLED[key] || key
  return ctrl ? 'ctrl+' + spelled : spelled
}

/** The stored text a chord round-trips to, or '' when it will not parse. */
export function normalizeBind (raw) {
  const chord = parseChord(raw)
  return chord === null ? '' : chordText(chord)
}
