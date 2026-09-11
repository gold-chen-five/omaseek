import test from 'node:test'
import assert from 'node:assert/strict'
import { paletteColor } from '../src/lib/palette.mjs'

const gruvbox = 'accent = "#7daea3"\nyellow = "#d8a657"\nbright_yellow = "#d8a657"\nred = "#ea6962"\n'

test('a named colour is read the way the shell reads colors.toml', () => {
  assert.equal(paletteColor(gruvbox, 'yellow'), '#d8a657')
  assert.equal(paletteColor(gruvbox, 'red'), '#ea6962')
  assert.equal(paletteColor("  yellow = '#AbCdEf'  # comment", 'yellow'), '#AbCdEf')
})

test('a name is matched whole, not as the end of another key', () => {
  assert.equal(paletteColor('bright_yellow = "#111111"\n', 'yellow'), '')
})

test('a missing key or file is empty, so the caller can fall back', () => {
  assert.equal(paletteColor(gruvbox, 'magenta'), '')
  assert.equal(paletteColor('', 'yellow'), '')
  assert.equal(paletteColor(undefined, 'yellow'), '')
})
