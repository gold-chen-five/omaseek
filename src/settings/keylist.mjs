// The key lookup (ctrl+k): the Settings → Keys rows, as the page itself lists
// them — the escape sequence, then every rebindable key with whatever it is
// bound to now — and under them the fixed keys, one row per group as the page's
// last section has them. An entry is shaped like a settings row (`label`, the
// `keys` beside it, the `hint` under it); a fixed row has no binding to show.
// Indexed loops and indexOf only: this runs in QML's JS engine too.

import { ACTIONS, settingKey, parseBinding, chordText } from '../shared/vim/keybinds.mjs'
import { FIXED_KEYS, DEFAULTS } from './choices.mjs'

// The two sections, in the order the page has them.
export const GROUP_ORDER = ['Keys', 'Fixed keys']

/** [{ group, keys, label, hint, fixed }]: every key, as bound under `settings`. */
export function keyEntries (settings) {
  const entries = []
  const escape = settings && settings.escapeSequence ? settings.escapeSequence : DEFAULTS.escapeSequence
  if (escape) entries.push({ group: 'Keys', keys: escape, label: 'Leave insert with', hint: 'typed quickly, back to normal mode', fixed: false })
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    const raw = settings && settings[settingKey(action)] ? settings[settingKey(action)] : action.default
    const sequence = parseBinding(action, raw) || parseBinding(action, action.default)
    entries.push({
      group: 'Keys',
      keys: sequence ? chordText(sequence) : '',
      label: action.label,
      hint: action.hint,
      fixed: false
    })
  }
  for (let i = 0; i < FIXED_KEYS.length; i++) {
    entries.push({ group: 'Fixed keys', keys: '', label: FIXED_KEYS[i].label, hint: FIXED_KEYS[i].keys, fixed: true })
  }
  return entries
}

/**
 * The entries every typed word appears in — in the key, what it does, its hint
 * or its group — whatever the case. An empty query keeps them all.
 */
export function filterEntries (entries, query) {
  const words = String(query || '').toLowerCase().split(/\s+/).filter(word => word !== '')
  if (words.length === 0) return entries
  const out = []
  for (let i = 0; i < entries.length; i++) {
    const hay = (entries[i].keys + ' ' + entries[i].label + ' ' + entries[i].hint + ' ' + entries[i].group).toLowerCase()
    let all = true
    for (let w = 0; w < words.length; w++) if (hay.indexOf(words[w]) === -1) all = false
    if (all) out.push(entries[i])
  }
  return out
}
