import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence, ENGINE_STATES,
  LAUNCHER_CHOICES, DEFAULT_AGENT,
  PAGE_SIZE_CHOICES, DEFAULTS, checkRow, FIXED_KEYS
} from '../src/lib/settings.mjs'
import { ACTIONS, settingKey } from '../src/lib/keybinds.mjs'
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


test('line numbers default to relative and all display choices survive saving', () => {
  assert.equal(readSettings('').lineNumbers, 'relative')
  assert.equal(readSettings('{"line_numbers":"invalid"}').lineNumbers, 'relative')
  for (const mode of ['relative', 'absolute', 'hide']) {
    const source = JSON.stringify({ line_numbers: mode, searxng_url: 'http://box:8888' })
    const settings = readSettings(source)
    const saved = writeSettings({ ...settings, resultsPerPage: 5 }, source)
    assert.equal(readSettings(saved).lineNumbers, mode)
    assert.equal(JSON.parse(saved).searxng_url, 'http://box:8888')
    const row = settingsRows(settings).find(row => row.key === 'lineNumbers')
    assert.equal(row.value, mode)
    assert.deepEqual(row.options, ['relative', 'absolute', 'hide'])
  }
})


test('hand-off defaults to ga, everything to gA, and gx still opens a link', () => {
  const initial = readSettings('')
  assert.equal(initial.handoffKey, 'ga')
  assert.equal(initial.handoffAllKey, 'gA')
  assert.equal(initial.openLinkKey, 'gx')
})

test('every rebindable key has an editable row, and each round-trips through the file', () => {
  const rows = settingsRows(readSettings(''))
  for (const action of ACTIONS) {
    const row = rows.find(row => row.key === settingKey(action))
    assert.ok(row, `${action.id} has no row`)
    assert.equal(row.type, 'text')
    assert.equal(row.normalize, 'bind')
    assert.equal(row.value, action.default)
    assert.ok(row.hint)
  }
  const changed = { ...readSettings(''), handoffKey: 'ctrl+h', handoffAllKey: 'gt', openLinkKey: 'ctrl+o', settingsKey: 'ctrl+o' }
  const written = writeSettings(changed, '{"searxng_url":"http://box:8888"}')
  const restored = readSettings(written)
  for (const key of ['handoffKey', 'handoffAllKey', 'openLinkKey', 'settingsKey']) assert.equal(restored[key], changed[key])
  assert.equal(JSON.parse(written).handoff_all_key, 'gt')
  assert.equal(JSON.parse(written).searxng_url, 'http://box:8888')
})

test('a key keeps its case through the file', () => {
  assert.equal(readSettings('{"handoff_all_key":"gA"}').handoffAllKey, 'gA')
  assert.equal(readSettings('{"handoff_all_key":"G A"}').handoffAllKey, 'GA')
})

test('keys from a config written before they were rebindable still read', () => {
  const settings = readSettings('{"search_key":"ctrl+enter","new_session_key":"ctrl+n"}')
  assert.equal(settings.searchKey, 'ctrl+enter')
  assert.equal(settings.newSessionKey, 'ctrl+n')
  assert.equal(readSettings('{"search_key":"q"}').searchKey, 'enter', 'a letter the field would type falls back')
})

test('the page refuses a key another action has, and says which', () => {
  const rows = settingsRows(readSettings(''))
  const row = rows.find(row => row.key === 'handoffKey')
  assert.match(checkRow(row, 'gx', rows).error, /Open link/)
  assert.equal(checkRow(row, 'gx', rows).value, null)
  assert.deepEqual(checkRow(row, 'ctrl+h', rows), { value: 'ctrl+h', error: '' })
  assert.deepEqual(checkRow(row, 'g a', rows), { value: 'ga', error: '' }, 'its own key is not a clash')
  assert.deepEqual(checkRow(row, '', rows), { value: 'ga', error: '' }, 'empty restores the default')
  const escape = rows.find(row => row.key === 'escapeSequence')
  assert.ok(checkRow(escape, 'j', rows).error)
  assert.deepEqual(checkRow(escape, '', rows), { value: '', error: '' })
})

test('the fixed keys close the page as read-only rows, so it lists everything pressable', () => {
  const rows = settingsRows(readSettings(''))
  const fixed = rows.slice(rows.findIndex(row => row.type === 'section' && row.label === 'Fixed keys') + 1)
  assert.deepEqual(fixed.map(row => row.label), FIXED_KEYS.map(entry => entry.label))
  for (const row of fixed) {
    assert.equal(row.type, 'info')
    assert.equal(row.key, undefined, 'nothing to write')
    assert.ok(row.hint)
  }
  assert.match(FIXED_KEYS.find(entry => entry.label === 'Settings').keys, /\/ field normal/)
})
