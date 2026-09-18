import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence, ENGINE_STATES,
  LAUNCHER_CHOICES, DEFAULT_AGENT,
  PAGE_SIZE_CHOICES, DEFAULTS, checkRow, FIXED_KEYS, changeSetting, selectedModel,
  ENGINE_CHOICES, DEFAULT_ENGINES, LANGUAGE_CHOICES, toggleEngine, endpointTestText, searchSpeedText, versionText, nextAgent, translateAgentOf, SAME_AS_ASK
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

test('updating SearXNG is a separate action from starting and stopping it', () => {
  for (const state of ENGINE_STATES) {
    const row = settingsRows(readSettings(''), state).find(r => r.key === 'engineUpdate')
    assert.equal(row.type, 'action')
    assert.equal(row.action, 'update')
    assert.equal(row.button, 'Update')
  }
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

test('model edits follow the resolved agent and preserve other agents through saving', () => {
  const agents = { agents: [{ id: 'codex' }, { id: 'opencode' }], default: 'codex' }
  const source = '{"chat_models":{"codex":"model-one","opencode":"provider/model"},"extra":42}'
  const original = readSettings(source)
  let settings = changeSetting(original, 'chatModel:codex', ' model-two ')
  assert.equal(original.chatModels.codex, 'model-one', 'edits do not mutate live settings')
  settings = changeSetting(settings, 'chatAgent', 'opencode')
  const catalog = { agent: 'opencode', models: ['provider/model'] }
  const modelRow = settingsRows(settings, 'running', agents, catalog).find(r => r.label === 'Model')
  assert.equal(modelRow.value, 'provider/model')
  const saved = writeSettings(settings, source)
  assert.deepEqual(readSettings(saved).chatModels, { codex: 'model-two', opencode: 'provider/model' })
  assert.equal(JSON.parse(saved).extra, 42)
  settings = changeSetting(settings, modelRow.key, 'default')
  assert.deepEqual(readSettings(writeSettings(settings, saved)).chatModels, { codex: 'model-two' })
})

test('invalid model config falls back per agent and an unresolved agent offers default', () => {
  for (const value of [null, [], 'sonnet', 42]) {
    assert.deepEqual(readSettings(JSON.stringify({ chat_models: value })).chatModels, {})
  }
  assert.deepEqual(readSettings('{"chat_models":{"claude":42,"codex":" model ","gemini":"bad\\u0000id"}}').chatModels, { codex: 'model' })
  const waiting = settingsRows(readSettings('')).find(r => r.label === 'Model')
  assert.equal(waiting.control, 'dropdown')
  assert.deepEqual(waiting.options, ['default'])
  assert.deepEqual(changeSetting(readSettings(''), waiting.key, 'default').chatModels, {})
})

test('model and agent share the dropdown control; discovery follows the selected agent', () => {
  const agents = { agents: [{ id: 'claude' }, { id: 'opencode' }], default: 'claude' }
  let settings = readSettings('{"chat_models":{"opencode":"custom/saved"}}')
  const catalog = { agent: 'opencode', models: ['provider/one', 'provider/two', 'provider/one', null, ''] }
  let rows = settingsRows(settings, 'running', agents, catalog)
  let model = rows.find(r => r.label === 'Model')
  const agent = rows.find(r => r.key === 'chatAgent')
  assert.equal(model.type, agent.type)
  assert.equal(model.control, agent.control)
  assert.deepEqual(model.options, ['default'])
  assert.equal(model.value, 'default', 'saved values are not offered without discovery')
  assert.equal(selectedModel(settings, agents, catalog), '')
  assert.ok(!model.options.includes('provider/one'), 'an old discovery cannot leak across agents')
  settings = changeSetting(settings, 'chatAgent', 'opencode')
  rows = settingsRows(settings, 'running', agents, catalog)
  model = rows.find(r => r.label === 'Model')
  assert.deepEqual(model.options, ['default', 'provider/one', 'provider/two'])
  assert.equal(model.value, 'default', 'an unreported saved model cannot be selected')
  assert.equal(selectedModel(settings, agents, catalog), '')
  const includingSaved = { agent: 'opencode', models: ['provider/one', 'custom/saved'] }
  model = settingsRows(settings, 'running', agents, includingSaved).find(r => r.label === 'Model')
  assert.equal(model.value, 'custom/saved')
  assert.equal(selectedModel(settings, agents, includingSaved), 'custom/saved')
  const chosen = cycle(model, 1)
  assert.equal(chosen, 'default')
  assert.deepEqual(changeSetting(settings, model.key, chosen).chatModels, {})
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

test('old field-return defaults migrate to gi', () => {
  assert.equal(readSettings('{"insert_key":"i"}').insertKey, 'gi')
  assert.equal(readSettings('{"insert_key":"/"}').insertKey, 'gi')
  assert.equal(readSettings('{"insert_key":"ctrl+o"}').insertKey, 'ctrl+o')
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
  // The two strips and the keys that walk them are a row each, not a clause
  // buried in a pane's line: they are how a reader finds out they exist.
  assert.match(FIXED_KEYS.find(entry => entry.label === 'Sessions (ask)').keys, /read in the answer and in the field/)
  assert.match(FIXED_KEYS.find(entry => entry.label === 'Pages (search)').keys, /5gp jumps to page 5/)
})

test('streaming is on unless it was deliberately turned off', async () => {
  const { readSettings, writeSettings, settingsRows } = await import('../src/lib/settings.mjs')

  assert.equal(readSettings('{}').stream, true)
  assert.equal(readSettings('{"stream":false}').stream, false)
  // Anything that is not an explicit false leaves the behaviour alone.
  assert.equal(readSettings('{"stream":"maybe"}').stream, true)
  assert.equal(readSettings('not json').stream, true)

  const settings = readSettings('{}')
  assert.equal(JSON.parse(writeSettings({ ...settings, stream: false }, '{}')).stream, false)
  assert.equal(JSON.parse(writeSettings(settings, '{}')).stream, true)

  const row = settingsRows(settings).find(r => r.key === 'stream')
  assert.equal(row.type, 'toggle')
  assert.equal(row.value, true)
  assert.equal(row.action, 'off', 'the action says what flipping it does')
  assert.equal(settingsRows({ ...settings, stream: false }).find(r => r.key === 'stream').action, 'on')
})

test('engines read as bin/search reads them: absent is the defaults, an explicit [] is kept', () => {
  assert.deepEqual(DEFAULT_ENGINES, ['google cse', 'bing', 'brave', 'duckduckgo'], 'mirrors DEFAULT_ENGINES in bin/search')
  const google = settingsRows(readSettings(''), 'running').find(r => r.key === 'searxngEngine:google')
  assert.equal(google.value, false, 'plain google is offered, and off by default')
  assert.deepEqual(readSettings('').searxngEngines, DEFAULT_ENGINES)
  assert.deepEqual(readSettings('{"searxng_engines":"brave"}').searxngEngines, DEFAULT_ENGINES, 'malformed')
  assert.deepEqual(readSettings('{"searxng_engines":[]}').searxngEngines, [])
  assert.deepEqual(readSettings('{"searxng_engines":[" brave ","brave",3,"mojeek"]}').searxngEngines, ['brave', 'mojeek'])
})

test('each offered engine is a switch, and a hand-typed one is kept and shown', () => {
  const settings = readSettings('{"searxng_engines":["bing","mojeek"]}')
  const rows = settingsRows(settings, 'running').filter(r => String(r.key).indexOf('searxngEngine:') === 0)
  assert.deepEqual(rows.map(r => r.key), ENGINE_CHOICES.map(n => 'searxngEngine:' + n).concat(['searxngEngine:mojeek']))
  const bing = rows.find(r => r.key === 'searxngEngine:bing')
  assert.equal(bing.type, 'toggle')
  assert.equal(bing.value, true)
  assert.equal(bing.action, 'off')
  assert.equal(rows.find(r => r.key === 'searxngEngine:brave').action, 'on')
  assert.match(rows.find(r => r.key === 'searxngEngine:mojeek').hint, /by hand/)
  assert.equal(rows.find(r => r.key === 'searxngEngine:google cse').label, 'Google CSE')
  assert.equal(rows.find(r => r.key === 'searxngEngine:mojeek').label, 'Mojeek')
})

test('switching an engine keeps the other names, hand-typed ones included, and writes through', () => {
  const settings = readSettings('{"searxng_engines":["mojeek","bing"]}')
  assert.deepEqual(toggleEngine(settings, 'brave', true), ['mojeek', 'bing', 'brave'])
  assert.deepEqual(toggleEngine(settings, 'bing', false), ['mojeek'])
  assert.deepEqual(toggleEngine(settings, 'bing', true), ['mojeek', 'bing'], 'on twice is on')
  const written = JSON.parse(writeSettings(changeSetting(settings, 'searxngEngines', ['google']), '{"searxng_url":"http://x:1"}'))
  assert.deepEqual(written.searxng_engines, ['google'])
  assert.equal(written.searxng_url, 'http://x:1', 'the address is still not the panel’s')
})

test('switching every engine off says what SearXNG does then', () => {
  const rows = settingsRows(readSettings('{"searxng_engines":[]}'), 'running')
  assert.match(rows.find(r => r.key === 'searxngEngine:brave').hint, /every engine/)
})

test('language is a dropdown; default sends nothing, and a hand-set code is kept', () => {
  assert.equal(readSettings('').searxngLanguage, 'default')
  assert.equal(readSettings('{"searxng_language":"de-DE"}').searxngLanguage, 'de-DE')
  assert.equal(readSettings('{"searxng_language":"fi-FI"}').searxngLanguage, 'fi-FI', 'well-formed, just not listed')
  assert.equal(readSettings('{"searxng_language":"german please"}').searxngLanguage, 'default')
  const row = settingsRows(readSettings('{"searxng_language":"fi-FI"}')).find(r => r.key === 'searxngLanguage')
  assert.equal(row.control, 'dropdown')
  assert.ok(row.options.indexOf('fi-FI') !== -1, 'the saved value is offered, or the dropdown could not show it')
  assert.equal(JSON.parse(writeSettings(readSettings(''), '{"searxng_language":"fr"}')).searxng_language, undefined,
    'default is written as absent')
  assert.equal(JSON.parse(writeSettings(changeSetting(readSettings(''), 'searxngLanguage', 'en-GB'), '')).searxng_language, 'en-GB')
  for (const code of LANGUAGE_CHOICES) assert.equal(readSettings(JSON.stringify({ searxng_language: code })).searxngLanguage, code)
})

test('the endpoint test is an action row whose hint is what the test found', () => {
  const row = test => settingsRows(readSettings(''), 'running', null, null, test).find(r => r.key === 'engineTest')
  assert.equal(row(null).type, 'action')
  assert.equal(row(null).action, 'test')
  assert.equal(row({ running: true }).busy, true)
  assert.equal(row({
    ok: true,
    ms: 1486,
    engines: { brave: { rows: 20, ms: 630 }, bing: { rows: 10, ms: 194 }, google: { rows: 0, ms: 3, reason: 'Suspended: CAPTCHA' } },
    unresponsive: [{ engine: 'google', reason: 'Suspended: CAPTCHA' }]
  }).hint,
  'brave 20 in 630 ms · bing 10 in 194 ms · google 0 in 3 ms (CAPTCHA)',
  'a blocked engine keeps its count and time, and says why in brackets')
  assert.equal(endpointTestText({ ok: true, ms: 312, engines: { brave: 20 }, unresponsive: [{ engine: 'google', reason: 'CAPTCHA' }] }),
    'brave 20 · google: CAPTCHA', 'counts alone, as an older --test printed them')
  assert.equal(endpointTestText({ ok: false, message: 'SearXNG is not reachable' }), 'SearXNG is not reachable')
  assert.equal(endpointTestText({ ok: true, ms: 5, engines: {}, unresponsive: [] }), 'no rows')
})

test('the page squares have a numbering of their own, apart from the lines', () => {
  const row = source => settingsRows(readSettings(source), 'running').find(r => r.key === 'pageNumbers')
  assert.equal(readSettings('').pageNumbers, 'absolute', 'a square says which page it is, by default')
  assert.deepEqual(row('').options, ['absolute', 'relative'], 'no hide: a square with no number says nothing')
  assert.equal(row('{"page_numbers":"relative"}').value, 'relative')
  assert.equal(row('{"page_numbers":"nonsense"}').value, 'absolute', 'a typo costs one setting, not the strip')
  assert.equal(readSettings('{"line_numbers":"relative"}').pageNumbers, 'absolute', 'the two are set apart')
  const written = JSON.parse(writeSettings(changeSetting(readSettings(''), 'pageNumbers', 'relative'), ''))
  assert.equal(written.page_numbers, 'relative')
})

test('the search-speed row times one real search, as a keypress sends it', () => {
  const row = speed => settingsRows(readSettings(''), 'running', null, null, null, null, speed)
    .find(r => r.key === 'engineSpeed')
  assert.match(row(null).hint, /every engine at once/, 'before a run it says what the button does')
  assert.equal(row({ running: true }).busy, true)
  assert.equal(row({ ok: true, ms: 848, rows: 28, unresponsive: [] }).hint, '848 ms for 28 rows')
  assert.equal(row({ ok: true, ms: 720, rows: 18, unresponsive: [{ engine: 'google', reason: 'Suspended: CAPTCHA' }] }).hint,
    '720 ms for 18 rows · google: Suspended: CAPTCHA')
  assert.equal(searchSpeedText({ ok: false, message: 'SearXNG is not reachable' }), 'SearXNG is not reachable')
})

test('the update row says which version runs and whether a newer one exists', () => {
  const hint = version => settingsRows(readSettings(''), 'running', null, null, null, version)
    .find(r => r.key === 'engineUpdate').hint
  assert.match(hint(null), /pull the latest image/, 'before a check it says what the button does')
  assert.equal(hint({ checking: true }), 'checking the running version…')
  assert.equal(hint({ ok: true, version: '2026.9.16+461f174b0', latest: '2026.9.16-461f174b0', current: true }),
    '2026.9.16 — the latest')
  assert.equal(hint({ ok: true, version: '2026.9.8+3fdc6d753', latest: '2026.9.16-461f174b0', current: false }),
    '2026.9.8 running · 2026.9.16 available — update')
  assert.equal(versionText({ ok: true, version: '2026.9.8+3fdc6d753', latest: null, current: null }),
    '2026.9.8 running · could not check for a newer one')
  assert.equal(versionText({ ok: false, error: 'network', setup: true }), 'not running — start it to see its version')
})

test('shift+tab hands the conversation to the next installed agent, wrapping', () => {
  const found = { agents: [{ id: 'claude' }, { id: 'codex' }, { id: 'opencode' }], default: 'claude', configured: true }
  assert.equal(nextAgent(found, 'default'), 'codex', 'from default, the one after whoever stands in for it')
  assert.equal(nextAgent(found, 'codex'), 'opencode')
  assert.equal(nextAgent(found, 'opencode'), 'claude', 'wrapping')
  assert.equal(nextAgent({ agents: [{ id: 'claude' }], default: 'claude' }, 'claude'), null, 'nobody else to ask')
  assert.equal(nextAgent(null, 'default'), null, 'before discovery has answered')
  assert.equal(settingsRows(readSettings(''), 'running').find(r => r.key === 'switchAgentKey').value, 'shift+tab',
    'and the page lists it with the other keys')
})

test('Translate follows the search language and Ask’s agent until told otherwise', () => {
  const found = { agents: [{ id: 'claude' }, { id: 'codex' }], default: 'claude' }
  const settings = readSettings('{"searxng_language":"ja-JP","chat_agent":"codex"}')
  assert.equal(settings.translateLanguage, 'search language')
  assert.equal(settings.translateAgent, SAME_AS_ASK)
  assert.equal(translateAgentOf(settings, found), 'codex', 'whoever Ask uses')
  assert.equal(translateAgentOf({ ...settings, translateAgent: 'claude' }, found), 'claude')
  assert.equal(translateAgentOf({ ...settings, chatAgent: 'default' }, found), 'claude', 'Ask on default: the stand-in')
  const rows = settingsRows(settings, 'running', found)
  assert.match(rows.find(r => r.key === 'translateLanguage').hint, /into 日本語/)
  assert.equal(rows.find(r => r.key === 'translateModel:codex').value, 'default')
})

test('Translate settings round-trip through config.json, keeping what they do not own', () => {
  let settings = readSettings('{"searxng_url":"http://x:1"}')
  settings = changeSetting(settings, 'translateLanguage', 'ko')
  settings = changeSetting(settings, 'translateAgent', 'codex')
  settings = changeSetting(settings, 'translateModel:codex', 'gpt-5-mini')
  const written = JSON.parse(writeSettings(settings, '{"searxng_url":"http://x:1"}'))
  assert.equal(written.translate_language, 'ko')
  assert.equal(written.translate_agent, 'codex')
  assert.deepEqual(written.translate_models, { codex: 'gpt-5-mini' })
  assert.equal(written.searxng_url, 'http://x:1')
  const back = readSettings(JSON.stringify(written))
  assert.equal(back.translateLanguage, 'ko')
  assert.equal(back.translateAgent, 'codex')
  const reset = JSON.parse(writeSettings(changeSetting(back, 'translateLanguage', 'search language'), JSON.stringify(written)))
  assert.equal(reset.translate_language, undefined, 'following search is an absent key')
  assert.equal(JSON.parse(writeSettings(readSettings(''), '')).translate_agent, 'same')
})
