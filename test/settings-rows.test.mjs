// The settings page, row by row: what each row shows and offers, and the checks
// a typed row runs.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence, ENGINE_STATES,
  LAUNCHER_CHOICES, DEFAULT_AGENT,
  PAGE_SIZE_CHOICES, DEFAULTS, checkRow, FIXED_KEYS, changeSetting, selectedModel,
  ENGINE_CHOICES, DEFAULT_ENGINES, LANGUAGE_CHOICES, toggleEngine, endpointTestText, searchSpeedText, versionText, nextAgent, translateAgentOf, SAME_AS_ASK, shortcutRow,
  filterRows
} from '../src/settings/settings.mjs'
import { ACTIONS, settingKey } from '../src/shared/vim/keybinds.mjs'
import { DEFAULT_TIMEOUT_MS } from '../src/shared/vim/keymap.mjs'

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

test('the agent row is a dropdown; the short choices stay chips', () => {
  const rows = settingsRows(DEFAULTS, 'running', { agents: [{ id: 'claude', name: 'c' }], default: 'claude', configured: false })
  const control = key => rows.find(r => r.key === key).control
  assert.equal(control('chatAgent'), 'dropdown')
  assert.equal(control('resultsPerPage'), undefined)
  assert.equal(control('launcher'), undefined)
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

test('the page refuses a key another action has, and says which', () => {
  const rows = settingsRows(readSettings(''))
  const row = rows.find(row => row.key === 'normalKey')
  assert.match(checkRow(row, 'gx', rows).error, /Open link/)
  assert.equal(checkRow(row, 'gx', rows).value, null)
  assert.deepEqual(checkRow(row, 'ctrl+b', rows), { value: 'ctrl+b', error: '' })
  assert.deepEqual(checkRow(row, 'g n', rows), { value: 'gn', error: '' }, 'its own key is not a clash')
  assert.deepEqual(checkRow(row, '', rows), { value: 'gn', error: '' }, 'empty restores the default')
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
  assert.match(FIXED_KEYS.find(entry => entry.label === 'Settings').keys, /\/ filter the page/)
  // The two strips and the keys that walk them are a row each, not a clause
  // buried in a pane's line: they are how a reader finds out they exist.
  assert.match(FIXED_KEYS.find(entry => entry.label === 'Sessions (ask)').keys, /read in the answer and in the field/)
  assert.match(FIXED_KEYS.find(entry => entry.label === 'Pages (search)').keys, /5gp jumps to page 5/)
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

test('the shortcut row offers Add only while SUPER + D is free, and heads the keys', () => {
  const free = shortcutRow({ ok: true, state: 'free', key: 'SUPER + D' })
  assert.equal(free.type, 'action')
  assert.equal(free.action, 'add')
  assert.match(free.hint, /asks before writing/)

  const bound = shortcutRow({ ok: true, state: 'bound', key: 'SUPER + S' })
  assert.equal(bound.type, 'info', 'nothing to press once it is there')
  assert.match(bound.hint, /^SUPER \+ S/, 'a key the user chose is the one shown')

  const taken = shortcutRow({ ok: true, state: 'taken', key: 'SUPER + D', holder: 'o.bind("SUPER + D", "Notes", "obsidian")' })
  assert.equal(taken.type, 'info', 'a binding the user has is never offered for replacing')
  assert.match(taken.hint, /already opens Notes/)

  assert.equal(shortcutRow({ ok: true, state: 'missing' }).type, 'info')
  assert.match(shortcutRow(null).hint, /checking/)
  assert.match(shortcutRow({ ok: false }).hint, /could not read/)

  const rows = settingsRows(readSettings(''), 'running', null, null, null, null, null, null, { ok: true, state: 'free' })
  const keys = rows.findIndex(r => r.type === 'section' && r.label === 'Keys')
  assert.equal(rows[keys + 1].key, 'shortcut')
})

test('a typed filter keeps the matching rows under their section headings', () => {
  const rows = settingsRows(readSettings(''))
  assert.equal(filterRows(rows, ''), rows, 'an empty filter is the whole page')
  const effort = filterRows(rows, 'EFFORT')
  assert.ok(effort.length > 0 && effort.every(r => r.type === 'section' || /effort/i.test(r.label + ' ' + r.hint + ' ' + r.value)),
    'every row kept has the word — or its section does')
  assert.ok(effort.some(r => r.type === 'section' && r.label === 'Ask') && effort.some(r => r.type === 'section' && r.label === 'Translate'),
    'each section with a match keeps its heading')
  const keys = filterRows(rows, 'keys')
  assert.ok(keys.some(r => r.label === 'Look up keys'), 'the section name finds its rows')
  assert.ok(filterRows(rows, 'translate bar').some(r => r.label === 'Translate the bar'), 'every word must match, in any order')
  for (let i = 0; i < effort.length; i++) {
    if (effort[i].type === 'section') assert.ok(effort[i + 1] && effort[i + 1].type !== 'section', 'no heading is left with nothing under it')
  }
  assert.deepEqual(filterRows(rows, 'zzzz nothing'), [])
})

test('a choice of more than four options is a dropdown: as chips they run over the hint', () => {
  const agents = { agents: [{ id: 'claude' }, { id: 'codex' }, { id: 'opencode' }], default: 'claude' }
  for (const row of settingsRows(readSettings(''), 'running', agents)) {
    if (row.type !== 'choice' || row.control === 'dropdown') continue
    assert.ok(row.options.length <= 4, `${row.key} offers ${row.options.length} options as chips`)
  }
  const suggestions = settingsRows(readSettings('')).find(row => row.key === 'searchSuggestions')
  assert.equal(suggestions.control, 'dropdown')
})
