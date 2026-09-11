import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence, ENGINE_STATES,
  LAUNCHER_CHOICES, DEFAULT_AGENT,
  PAGE_SIZE_CHOICES, DEFAULTS
} from '../src/lib/settings.mjs'
import { DEFAULT_TIMEOUT_MS } from '../src/lib/keymap.mjs'

test('an absent config yields the defaults', () => {
  const settings = readSettings('')
  assert.equal(settings.escapeSequence, 'jk')
  assert.equal(settings.resultsPerPage, 10)
})

test('malformed config falls back rather than throwing', () => {
  assert.equal(readSettings('{not json').engine, DEFAULTS.engine)
  assert.equal(readSettings('null').engine, DEFAULTS.engine)
})

test('an engine key left over from an older config is carried, not honoured', () => {
  // writeSettings must not drop a key it does not own.
  assert.equal(readSettings('{"engine":"exa"}').engine, undefined)
  assert.match(writeSettings(readSettings('{"engine":"exa"}'), '{"engine":"exa"}'), /"engine": "exa"/)
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
  // searxng_url is exactly this case: the panel never writes it, so a write
  // that dropped it would point the search at nothing.
  const source = '{"something_else": 42, "searxng_url": "http://box:8888"}'
  const written = JSON.parse(writeSettings(DEFAULTS, source))
  assert.equal(written.something_else, 42, 'a hand-written key must survive')
  assert.equal(written.searxng_url, 'http://box:8888', 'the instance address is not the panel’s to drop')
})

test('writing off stores an empty sequence, which reads back as off', () => {
  const json = writeSettings({ ...DEFAULTS, escapeSequence: '' }, '')
  assert.equal(JSON.parse(json).escape_sequence, '')
  assert.equal(readSettings(json).escapeSequence, '')
})

test('a written config round-trips unchanged', () => {
  const settings = { escapeSequence: 'kj', resultsPerPage: 20 }
  const back = readSettings(writeSettings(settings, ''))
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
  const row = { options: PAGE_SIZE_CHOICES, value: 5 }
  assert.equal(cycle(row, 1), 10)
  assert.equal(cycle(row, -1), 20, 'wraps backwards off the front')
  assert.equal(cycle({ options: PAGE_SIZE_CHOICES, value: 20 }, 1), 5, 'wraps forwards off the end')
})

test('cycling covers every option and returns', () => {
  let value = PAGE_SIZE_CHOICES[0]
  for (let i = 0; i < PAGE_SIZE_CHOICES.length; i++) {
    value = cycle({ options: PAGE_SIZE_CHOICES, value }, 1)
  }
  assert.equal(value, PAGE_SIZE_CHOICES[0])
})

test('the engine row is a switch showing whether the instance runs, and flipping it does the opposite', () => {
  const row = state => settingsRows(readSettings(''), state).find(r => r.key === 'engine')
  assert.equal(row('running').type, 'toggle')
  assert.equal(row('running').value, true)
  assert.equal(row('running').action, 'stop')
  assert.equal(row('stopped').value, false)
  assert.equal(row('stopped').action, 'start')
  // Until the probe answers the switch is off and busy, so nothing can be
  // flipped on a guess; starting an instance that is up is a no-op anyway.
  assert.equal(row('unknown').value, false)
  assert.equal(row('unknown').busy, true)
  assert.equal(row('running').busy, false)
  assert.equal(row('garbage').busy, true)
  assert.equal(row(undefined).busy, true)
  for (const state of ENGINE_STATES) assert.equal(row(state).type, 'toggle')
})

test('the engine row is never written to the config', () => {
  const out = writeSettings(readSettings(''), '{"searxng_url":"http://x:1"}')
  assert.equal(JSON.parse(out).engine, undefined)
  assert.equal(JSON.parse(out).searxng_url, 'http://x:1')
})

test('the chat agent and launcher read, default and round-trip', () => {
  assert.equal(readSettings('').chatAgent, DEFAULT_AGENT)
  assert.equal(readSettings('').launcher, 'terminal')
  assert.equal(readSettings('{"chat_agent":"hermes","launcher":"herdr"}').chatAgent, 'hermes')
  assert.equal(readSettings('{"chat_agent":"hermes","launcher":"herdr"}').launcher, 'herdr')
  assert.equal(readSettings('{"launcher":"screen"}').launcher, 'terminal', 'unknown launcher falls back')
  assert.equal(readSettings('{"chat_agent":"  "}').chatAgent, DEFAULT_AGENT)
  const out = JSON.parse(writeSettings({ ...DEFAULTS, chatAgent: 'codex', launcher: 'tmux' }, ''))
  assert.equal(out.chat_agent, 'codex')
  assert.equal(out.launcher, 'tmux')
})

test('the agent row offers default plus whatever is installed', () => {
  const agents = { agents: [{ id: 'claude', name: 'Claude Code' }, { id: 'hermes', name: 'Hermes' }], default: 'claude', configured: false }
  const row = settingsRows(readSettings('{"chat_agent":"hermes"}'), 'running', agents).find(r => r.key === 'chatAgent')
  assert.deepEqual(row.options, ['default', 'claude', 'hermes'])
  assert.equal(row.value, 'hermes')
  assert.match(row.hint, /unset/)
  // An agent named in the config but not installed shows as default rather
  // than as a chip that is not there.
  const gone = settingsRows(readSettings('{"chat_agent":"grok"}'), 'running', agents).find(r => r.key === 'chatAgent')
  assert.equal(gone.value, 'default')
  assert.ok(gone.options.indexOf(gone.value) !== -1)
  // Before the list arrives the row still has a selectable value.
  const early = settingsRows(readSettings(''), 'running', null).find(r => r.key === 'chatAgent')
  assert.deepEqual(early.options, ['default'])
  assert.equal(cycle(early, 1), 'default')
  const launcher = settingsRows(readSettings(''), 'running', agents).find(r => r.key === 'launcher')
  assert.deepEqual(launcher.options, LAUNCHER_CHOICES)
})


test('the agent row is a dropdown; the short choices stay chips', () => {
  const rows = settingsRows(DEFAULTS, 'running', { agents: [{ id: 'claude', name: 'c' }], default: 'claude', configured: false })
  const control = key => rows.find(r => r.key === key).control
  assert.equal(control('chatAgent'), 'dropdown')
  assert.equal(control('resultsPerPage'), undefined)
  assert.equal(control('launcher'), undefined)
})
