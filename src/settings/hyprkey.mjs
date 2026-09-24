// A key to open omaseek with, as Hyprland's bindings write it: "super+shift+s"
// -> "SUPER + SHIFT + S", modifiers in one order so two spellings of a key
// compare equal. Mirrors normalize_key in bin/keybind, which is what finally
// writes it; change both.

const MODIFIERS = { SUPER: 'SUPER', WIN: 'SUPER', META: 'SUPER', MOD4: 'SUPER', CTRL: 'CTRL', CONTROL: 'CTRL', ALT: 'ALT', MOD1: 'ALT', SHIFT: 'SHIFT' }
const ORDER = ['SUPER', 'CTRL', 'ALT', 'SHIFT']

export const DEFAULT_OPEN_KEY = 'SUPER + D'
export const OPEN_KEY_RULE = 'a modifier and a key, such as SUPER + D or SUPER + SHIFT + S'

/** The key normalized, or '' when it is not a modifier (or more) and a key. */
export function normalizeHyprKey (raw) {
  const tokens = String(raw ?? '').toUpperCase().split('+')
  if (tokens.length < 2) return ''
  const held = {}
  for (let i = 0; i < tokens.length - 1; i++) {
    const modifier = MODIFIERS[tokens[i].replace(/\s+/g, '')]
    if (!modifier || held[modifier]) return ''
    held[modifier] = true
  }
  const key = tokens[tokens.length - 1].replace(/\s+/g, '')
  if (!/^[A-Z0-9_]+$/.test(key) || MODIFIERS[key]) return ''
  const parts = []
  for (let i = 0; i < ORDER.length; i++) if (held[ORDER[i]]) parts.push(ORDER[i])
  parts.push(key)
  return parts.join(' + ')
}
