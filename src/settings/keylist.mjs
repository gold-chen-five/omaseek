// The key lookup (ctrl+k): every key in the panel, grouped by where it works,
// and the words typed to find one. An entry is shaped like a settings row —
// `label` with `keys` beside it and `hint` under it — so the lookup reads as
// the Settings → Keys page does. The rebindable keys come from ACTIONS with
// whatever they are bound to now; the rest are the fixed keys the settings page
// lists, one line each (`fixed`), which have no binding to show. Indexed loops
// and indexOf only: this runs in QML's JS engine too.

import { ACTIONS, settingKey, parseBinding, chordText } from '../shared/vim/keybinds.mjs'
import { FIXED_KEYS, DEFAULTS } from './choices.mjs'

// The order the groups are listed in. A group not named here goes last.
export const GROUP_ORDER = ['Anywhere', 'Field', 'Field, normal mode', 'Results and answer', 'Results',
  'Answer', 'Translate', 'Sessions (ask)', 'Pages (search)', 'Settings']

function groupOf (action) {
  if (action.scope === 'panel') return 'Anywhere'
  if (action.scope === 'field') return 'Field'
  if (action.scope === 'normal') return 'Field, normal mode'
  return 'Results and answer'
}

/** [{ group, keys, label, hint, fixed }]: every key, as bound under `settings`, in GROUP_ORDER. */
export function keyEntries (settings) {
  const entries = []
  const escape = settings && settings.escapeSequence ? settings.escapeSequence : DEFAULTS.escapeSequence
  if (escape) entries.push({ group: 'Field', keys: escape, label: 'Leave insert with', hint: 'typed quickly, back to normal mode', fixed: false })
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    const raw = settings && settings[settingKey(action)] ? settings[settingKey(action)] : action.default
    const sequence = parseBinding(action, raw) || parseBinding(action, action.default)
    entries.push({
      group: groupOf(action),
      keys: sequence ? chordText(sequence) : '',
      label: action.label,
      hint: action.hint,
      fixed: false
    })
  }
  // The fixed keys are written as runs joined by ' · ', and a long run lists
  // commands joined by ', '; each is its own line, so a filter finds one.
  for (let i = 0; i < FIXED_KEYS.length; i++) {
    const runs = FIXED_KEYS[i].keys.split(' · ')
    for (let r = 0; r < runs.length; r++) {
      const parts = runs[r].split(', ')
      for (let p = 0; p < parts.length; p++) entries.push({ group: FIXED_KEYS[i].label, keys: '', label: parts[p], hint: '', fixed: true })
    }
  }
  const rank = group => { const at = GROUP_ORDER.indexOf(group); return at === -1 ? GROUP_ORDER.length : at }
  const order = []
  for (let i = 0; i < entries.length; i++) order.push(i)
  order.sort((a, b) => rank(entries[a].group) - rank(entries[b].group) || a - b)
  const sorted = []
  for (let i = 0; i < order.length; i++) sorted.push(entries[order[i]])
  return sorted
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
