// Config text <-> settings: what config.json reads as, what is written back,
// and what survives the round trip.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence, ENGINE_STATES,
  LAUNCHER_CHOICES, DEFAULT_AGENT,
  PAGE_SIZE_CHOICES, DEFAULTS, checkRow, FIXED_KEYS, changeSetting, selectedModel,
  ENGINE_CHOICES, DEFAULT_ENGINES, LANGUAGE_CHOICES, toggleEngine, endpointTestText, searchSpeedText, versionText, nextAgent, translateAgentOf, SAME_AS_ASK
} from '../src/settings/settings.mjs'
import { ACTIONS, settingKey } from '../src/shared/vim/keybinds.mjs'
import { DEFAULT_TIMEOUT_MS } from '../src/shared/vim/keymap.mjs'

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

test('streaming is on unless it was deliberately turned off', async () => {
  const { readSettings, writeSettings, settingsRows } = await import('../src/settings/settings.mjs')

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
  assert.deepEqual(DEFAULT_ENGINES, ['google cse', 'bing', 'brave', 'duckduckgo'], 'mirrors DEFAULT_ENGINES in backend/omaseek/search/config.py')
  const google = settingsRows(readSettings(''), 'running').find(r => r.key === 'searxngEngine:google')
  assert.equal(google.value, false, 'plain google is offered, and off by default')
  assert.deepEqual(readSettings('').searxngEngines, DEFAULT_ENGINES)
  assert.deepEqual(readSettings('{"searxng_engines":"brave"}').searxngEngines, DEFAULT_ENGINES, 'malformed')
  assert.deepEqual(readSettings('{"searxng_engines":[]}').searxngEngines, [])
  assert.deepEqual(readSettings('{"searxng_engines":[" brave ","brave",3,"mojeek"]}').searxngEngines, ['brave', 'mojeek'])
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

test('suggestions come from duckduckgo unless another source, or off, is chosen', async () => {
  const { SUGGESTION_CHOICES } = await import('../src/settings/choices.mjs')
  assert.deepEqual(SUGGESTION_CHOICES, ['duckduckgo', 'google', 'brave', 'qwant', 'wikipedia', 'off'],
    'mirrors SUGGESTION_CHOICES in backend/omaseek/search/config.py')
  assert.equal(readSettings('').searchSuggestions, 'duckduckgo')
  assert.equal(readSettings('{"search_suggestions":"altavista"}').searchSuggestions, 'duckduckgo')
  const off = writeSettings(Object.assign(readSettings(''), { searchSuggestions: 'off' }), '{"searxng_url":"http://box"}')
  assert.equal(JSON.parse(off).search_suggestions, 'off')
  assert.equal(JSON.parse(off).searxng_url, 'http://box', 'a key the panel does not own is kept')
  const row = settingsRows(readSettings(off)).find(row => row.key === 'searchSuggestions')
  assert.equal(row.value, 'off')
  assert.match(row.hint, /nothing typed leaves this machine/)
})
