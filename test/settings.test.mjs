import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence,
  ENGINES, PAGE_SIZE_CHOICES, DEFAULTS
} from '../src/lib/settings.mjs'
import { DEFAULT_TIMEOUT_MS } from '../src/lib/keymap.mjs'

test('an absent config yields the defaults', () => {
  const settings = readSettings('')
  assert.equal(settings.engine, 'auto')
  assert.equal(settings.escapeSequence, 'jk')
  assert.equal(settings.resultsPerPage, 10)
})

test('malformed config falls back rather than throwing', () => {
  assert.equal(readSettings('{not json').engine, DEFAULTS.engine)
  assert.equal(readSettings('null').engine, DEFAULTS.engine)
})

test('a known engine is honoured, an unknown one is not', () => {
  assert.equal(readSettings('{"engine":"exa"}').engine, 'exa')
  assert.equal(readSettings('{"engine":"altavista"}').engine, 'auto')
})

test('an off escape sequence reads back as empty', () => {
  assert.equal(readSettings('{"escape_sequence":""}').escapeSequence, '')
})

test('any sequence the user types is kept, not just a listed one', () => {
  assert.equal(readSettings('{"escape_sequence":";;"}').escapeSequence, ';;')
  assert.equal(readSettings('{"escape_sequence":"jjk"}').escapeSequence, 'jjk')
})

test('a single character is refused rather than silently meaning off', () => {
  assert.equal(normalizeSequence('j'), null)
  assert.equal(normalizeSequence(''), '', 'empty is a deliberate off')
  assert.equal(normalizeSequence('  kj  '), 'kj', 'surrounding space is trimmed')
  assert.equal(normalizeSequence(';;'), ';;')
})

test('results per page only accepts offered sizes', () => {
  assert.equal(readSettings('{"results_per_page":20}').resultsPerPage, 20)
  assert.equal(readSettings('{"results_per_page":7}').resultsPerPage, 10, 'not on the menu')
})

test('writing preserves unrelated keys already in the file', () => {
  const source = '{"something_else": 42}'
  const written = JSON.parse(writeSettings({ ...DEFAULTS, engine: 'exa' }, source))
  assert.equal(written.something_else, 42, 'a hand-written key must survive')
  assert.equal(written.engine, 'exa')
})

test('writing off stores an empty sequence, which reads back as off', () => {
  const json = writeSettings({ ...DEFAULTS, escapeSequence: '' }, '')
  assert.equal(JSON.parse(json).escape_sequence, '')
  assert.equal(readSettings(json).escapeSequence, '')
})

test('a written config round-trips unchanged', () => {
  const settings = { engine: 'duckduckgo', escapeSequence: 'kj', resultsPerPage: 20 }
  const back = readSettings(writeSettings(settings, ''))
  assert.equal(back.engine, 'duckduckgo')
  assert.equal(back.escapeSequence, 'kj')
  assert.equal(back.resultsPerPage, 20)
})

test('the sequence window is vim’s timeoutlen, not a setting', () => {
  assert.equal(DEFAULT_TIMEOUT_MS, 1000, 'vim and neovim both default to 1000')
  assert.equal(readSettings('').escapeTimeoutMs, 1000)
  assert.equal(settingsRows(readSettings('')).find(r => r.key === 'escapeTimeoutMs'), undefined)
})

test('a hand-set timeout in the config is still honoured', () => {
  assert.equal(readSettings('{"escape_timeout_ms":300}').escapeTimeoutMs, 300)
})

test('writing does not clobber a hand-set timeout', () => {
  const written = writeSettings({ ...DEFAULTS, engine: 'exa' }, '{"escape_timeout_ms":300}')
  assert.equal(JSON.parse(written).escape_timeout_ms, 300)
})

test('every choice row exposes its current value as one of its options', () => {
  for (const row of settingsRows(readSettings(''))) {
    if (row.type !== 'choice') continue
    assert.ok(row.options.indexOf(row.value) !== -1, `${row.key} value must be selectable`)
  }
})

test('the escape sequence is a typed field, not a fixed list', () => {
  const row = settingsRows(readSettings('')).find(r => r.key === 'escapeSequence')
  assert.equal(row.type, 'text')
  assert.equal(row.options, undefined, 'no menu to be limited by')
})

test('cycling wraps in both directions', () => {
  const row = { options: ENGINES, value: 'auto' }
  assert.equal(cycle(row, 1), 'duckduckgo')
  assert.equal(cycle(row, -1), 'exa', 'wraps backwards off the front')
  assert.equal(cycle({ options: ENGINES, value: 'exa' }, 1), 'auto', 'wraps forwards off the end')
})

test('cycling covers every option and returns', () => {
  let value = PAGE_SIZE_CHOICES[0]
  for (let i = 0; i < PAGE_SIZE_CHOICES.length; i++) {
    value = cycle({ options: PAGE_SIZE_CHOICES, value }, 1)
  }
  assert.equal(value, PAGE_SIZE_CHOICES[0])
})
