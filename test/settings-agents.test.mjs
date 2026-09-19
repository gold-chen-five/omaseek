// Who answers: the agent Ask uses and its model, who translates, and the next
// agent shift+tab moves to.

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

test('effort edits keep a level per agent, only one its flag takes', () => {
  const agents = { agents: [{ id: 'claude' }, { id: 'gemini' }, { id: 'cursor-agent' }], default: 'claude' }
  const source = '{"chat_efforts":{"claude":"high","codex":"ultra","gemini":"high"},"extra":1}'
  let settings = readSettings(source)
  assert.deepEqual(settings.chatEfforts, { claude: 'high' })
  const row = () => settingsRows(settings, 'running', agents, null).find(r => r.label === 'Effort')
  assert.equal(row().key, 'chatEffort:claude')
  assert.equal(row().value, 'high')
  assert.deepEqual(row().options, ['default', 'low', 'medium', 'high', 'xhigh', 'max'])
  settings = changeSetting(settings, 'chatEffort:claude', 'max')
  settings = changeSetting(settings, 'chatEffort:gemini', 'high')
  let saved = writeSettings(settings, source)
  assert.deepEqual(JSON.parse(saved).chat_efforts, { claude: 'max' })
  assert.equal(JSON.parse(saved).extra, 1)
  settings = changeSetting(readSettings(saved), 'chatEffort:claude', 'default')
  assert.deepEqual(JSON.parse(writeSettings(settings, saved)).chat_efforts, {})
  settings = changeSetting(settings, 'chatAgent', 'gemini')
  assert.deepEqual(row().options, ['default'])
  settings = changeSetting(settings, 'chatAgent', 'cursor-agent')
  assert.match(row().hint, /model name/)
})

test('translation effort is its own, for whoever translates', () => {
  const agents = { agents: [{ id: 'claude' }, { id: 'codex' }], default: 'claude' }
  const source = '{"chat_efforts":{"claude":"max"},"translate_efforts":{"codex":"low","claude":"bogus"}}'
  let settings = readSettings(source)
  assert.deepEqual(settings.translateEfforts, { codex: 'low' })
  const row = () => settingsRows(settings, 'running', agents, null).find(r => r.label === 'Translation effort')
  assert.equal(row().key, 'chatEffort:claude'.replace('chat', 'translate'))
  assert.equal(row().value, 'default', 'Ask\'s max is not the translation\'s')
  settings = changeSetting(settings, 'translateAgent', 'codex')
  assert.equal(row().key, 'translateEffort:codex')
  assert.equal(row().value, 'low')
  settings = changeSetting(settings, 'translateEffort:codex', 'medium')
  const saved = JSON.parse(writeSettings(settings, source))
  assert.deepEqual(saved.translate_efforts, { codex: 'medium' })
  assert.deepEqual(saved.chat_efforts, { claude: 'max' })
})
