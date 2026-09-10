import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle,
  ENGINES, PAGE_SIZE_CHOICES, DEFAULTS
} from '../src/lib/settings.mjs'

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

test('an off escape sequence reads back as off', () => {
  assert.equal(readSettings('{"escape_sequence":""}').escapeSequence, 'off')
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
  const json = writeSettings({ ...DEFAULTS, escapeSequence: 'off' }, '')
  assert.equal(JSON.parse(json).escape_sequence, '')
  assert.equal(readSettings(json).escapeSequence, 'off')
})

test('a written config round-trips unchanged', () => {
  const settings = { engine: 'duckduckgo', escapeSequence: 'kj', escapeTimeoutMs: 300, resultsPerPage: 20 }
  const back = readSettings(writeSettings(settings, ''))
  assert.equal(back.engine, 'duckduckgo')
  assert.equal(back.escapeSequence, 'kj')
  assert.equal(back.escapeTimeoutMs, 300)
  assert.equal(back.resultsPerPage, 20)
})

test('every row exposes its current value as one of its options', () => {
  for (const row of settingsRows(readSettings(''))) {
    assert.ok(row.options.indexOf(row.value) !== -1, `${row.key} value must be selectable`)
  }
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
