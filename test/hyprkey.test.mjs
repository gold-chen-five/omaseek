import test from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { normalizeHyprKey } from '../src/settings/hyprkey.mjs'

const CASES = [
  ['SUPER + D', 'SUPER + d'], ['super+d', 'SUPER + d'], ['shift + Super + s', 'SUPER + SHIFT + s'],
  ['ctrl+alt+t', 'CTRL + ALT + t'], ['win + space', 'SUPER + SPACE'], ['SUPER + F12', 'SUPER + F12'],
  ['d', ''], ['SUPER +', ''], ['SUPER + SUPER + D', ''], ['HYPER + D', ''], ['SUPER + D;rm', ''],
  ['SUPER + SHIFT', ''], ['', '']
]

test('a key is read in any case, spacing and modifier order, and refused unless it has a modifier', () => {
  for (const [raw, want] of CASES) assert.equal(normalizeHyprKey(raw), want, JSON.stringify(raw))
})

test('bin/keybind reads every key the same way', () => {
  const script = fileURLToPath(new URL('../bin/keybind', import.meta.url))
  for (const [raw, want] of CASES) {
    const out = execFileSync('bash', ['-c', `source <(sed -n '/^normalize_key ()/,/^}/p' "$0"); normalize_key "$1" || true`, script, raw]).toString().trim()
    assert.equal(out, want, JSON.stringify(raw))
  }
})
