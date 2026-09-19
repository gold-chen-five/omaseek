// Config text <-> settings: what config.json says, read with every unreadable
// or unknown value falling back to its default, and written back preserving
// the keys this does not own, so the file stays hand-editable.

import { parseObject } from '../shared/json.mjs'
import { readKeymap } from '../shared/vim/keymap.mjs'
import { ACTIONS, settingKey, normalizeBinding } from '../shared/vim/keybinds.mjs'
import { FOLLOW_SEARCH, readTarget } from '../translate/translate.mjs'
import {
  LINE_NUMBER_CHOICES, PAGE_NUMBER_CHOICES, PAGE_SIZE_CHOICES, DEFAULT_ENGINES, LANGUAGE_CHOICES,
  LANGUAGE_PATTERN, LAUNCHER_CHOICES, DEFAULT_AGENT, SAME_AS_ASK, EFFORT_CHOICES, DEFAULTS
} from './choices.mjs'

export function oneOf (value, choices, fallback) {
  return choices.indexOf(value) !== -1 ? value : fallback
}

/** Config text -> settings; anything unreadable or unknown falls back to its default. */
export function readSettings (source) {
  const config = parseObject(source)
  const keymap = readKeymap(source)

  const settings = {
    // Empty means off.
    escapeSequence: keymap.sequences.length > 0 ? keymap.sequences[0] : '',
    escapeTimeoutMs: keymap.timeoutMs,
    resultsPerPage: oneOf(config.resultsPerPage ?? config.results_per_page, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage),
    lineNumbers: oneOf(config.line_numbers, LINE_NUMBER_CHOICES, DEFAULTS.lineNumbers),
    pageNumbers: oneOf(config.page_numbers, PAGE_NUMBER_CHOICES, DEFAULTS.pageNumbers),
    chatAgent: agentId(config.chat_agent),
    chatModels: readModels(config.chat_models),
    chatEfforts: readEfforts(config.chat_efforts),
    launcher: oneOf(config.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher),
    // On unless it was deliberately turned off: an agent that cannot stream
    // falls back on its own, so this is only for turning the behaviour off.
    stream: config.stream !== false,
    searxngEngines: readEngines(config.searxng_engines),
    translateLanguage: readTarget(config.translate_language),
    translateAgent: config.translate_agent === undefined || config.translate_agent === 'same'
      ? SAME_AS_ASK : agentId(config.translate_agent),
    translateModels: readModels(config.translate_models),
    translateEfforts: readEfforts(config.translate_efforts),
    searxngLanguage: readLanguage(config.searxng_language),
    sequences: keymap.sequences
  }
  // An unparseable key falls back to its default.
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    // i was the old default and / was briefly configurable; both are fixed now,
    // and / searches the pane, so a config still holding it must not keep it.
    const oldFieldKey = action.id === 'insert' && (config[action.config] === 'i' || config[action.config] === '/')
    const raw = oldFieldKey ? action.default : config[action.config]
    settings[settingKey(action)] = normalizeBinding(action, raw) || action.default
  }
  return settings
}

// As bin/search reads it: absent or malformed is the defaults, and an explicit
// [] is kept, since it deliberately hands the choice back to SearXNG.
export function readEngines (value) {
  if (!Array.isArray(value)) return DEFAULT_ENGINES.slice(0)
  const names = []
  for (let i = 0; i < value.length; i++) {
    const name = typeof value[i] === 'string' ? value[i].trim() : ''
    if (name && names.indexOf(name) === -1) names.push(name)
  }
  return names
}

export function readLanguage (value) {
  const code = typeof value === 'string' ? value.trim() : ''
  return LANGUAGE_PATTERN.test(code) ? code : LANGUAGE_CHOICES[0]
}

/** One engine switched on or off; every other name, hand-typed ones too, keeps its place. */
export function toggleEngine (settings, name, on) {
  const names = readEngines(settings.searxngEngines)
  const at = names.indexOf(name)
  if (on && at === -1) names.push(name)
  if (!on && at !== -1) names.splice(at, 1)
  return names
}

// Any non-empty id is kept; bin/ask falls back when it isn't installed.
export function agentId (value) {
  const id = typeof value === 'string' ? value.trim() : ''
  return id === '' ? DEFAULT_AGENT : id
}

export function modelId (value) {
  if (typeof value !== 'string') return ''
  const text = value.trim()
  return /[\x00-\x1f\x7f]/.test(text) ? '' : text
}

export function readModels (value) {
  const models = {}
  if (!value || typeof value !== 'object' || Array.isArray(value)) return models
  for (const id of Object.keys(value)) {
    const model = modelId(value[id])
    if (model && id !== '__proto__') models[id] = model
  }
  return models
}

// Only a level the agent's flag takes is kept; the rest is its CLI's own.
export function readEfforts (value) {
  const efforts = {}
  if (!value || typeof value !== 'object' || Array.isArray(value)) return efforts
  const ids = Object.keys(value)
  for (let i = 0; i < ids.length; i++) {
    const levels = EFFORT_CHOICES[ids[i]]
    if (Array.isArray(levels) && levels.indexOf(value[ids[i]]) !== -1) efforts[ids[i]] = value[ids[i]]
  }
  return efforts
}

/** A model row targets the resolved agent, even when Agent is set to default. */
export function changeSetting (settings, key, value) {
  const next = Object.assign({}, settings)
  if (key.indexOf('translateModel:') === 0) {
    const id = key.slice('translateModel:'.length)
    next.translateModels = readModels(settings.translateModels)
    if (id && id !== '__proto__') {
      const model = value === 'default' ? '' : modelId(value)
      if (model) next.translateModels[id] = model
      else delete next.translateModels[id]
    }
    return next
  }
  const effortKeys = { 'chatEffort:': 'chatEfforts', 'translateEffort:': 'translateEfforts' }
  for (const prefix of Object.keys(effortKeys)) {
    if (key.indexOf(prefix) !== 0) continue
    const id = key.slice(prefix.length)
    const stored = effortKeys[prefix]
    next[stored] = readEfforts(settings[stored])
    const levels = EFFORT_CHOICES[id]
    if (Array.isArray(levels) && levels.indexOf(value) !== -1) next[stored][id] = value
    else delete next[stored][id]
    return next
  }
  if (key.indexOf('chatModel:') === 0) {
    const id = key.slice('chatModel:'.length)
    next.chatModels = readModels(settings.chatModels)
    if (id && id !== '__proto__') {
      const model = value === 'default' ? '' : modelId(value)
      if (model) next.chatModels[id] = model
      else delete next.chatModels[id]
    }
  } else next[key] = value
  return next
}

/** Settings -> JSON, preserving keys this module does not own. */
export function writeSettings (settings, source) {
  const config = parseObject(source)

  config.escape_sequence = normalizeSequence(settings.escapeSequence) ?? DEFAULTS.escapeSequence
  config.results_per_page = oneOf(settings.resultsPerPage, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage)
  config.line_numbers = oneOf(settings.lineNumbers, LINE_NUMBER_CHOICES, DEFAULTS.lineNumbers)
  config.page_numbers = oneOf(settings.pageNumbers, PAGE_NUMBER_CHOICES, DEFAULTS.pageNumbers)
  config.chat_agent = agentId(settings.chatAgent)
  config.chat_models = readModels(settings.chatModels)
  config.chat_efforts = readEfforts(settings.chatEfforts)
  config.launcher = oneOf(settings.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher)
  config.stream = settings.stream !== false
  config.searxng_engines = readEngines(settings.searxngEngines)
  const target = readTarget(settings.translateLanguage)
  if (target === FOLLOW_SEARCH) delete config.translate_language   // absent follows the search language
  else config.translate_language = target
  config.translate_agent = !settings.translateAgent || settings.translateAgent === SAME_AS_ASK
    ? 'same' : agentId(settings.translateAgent)
  config.translate_models = readModels(settings.translateModels)
  config.translate_efforts = readEfforts(settings.translateEfforts)
  const language = readLanguage(settings.searxngLanguage)
  if (language === LANGUAGE_CHOICES[0]) delete config.searxng_language   // absent is the instance's default
  else config.searxng_language = language
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    config[action.config] = normalizeBinding(action, settings[settingKey(action)]) || action.default
  }

  return JSON.stringify(config, null, 2) + '\n'
}

/**
 * Escape sequence text -> the value to store, or null. Empty turns it off; one
 * character is refused because it would make that key untypable.
 */
export function normalizeSequence (raw) {
  const value = String(raw ?? '').trim()
  if (value === '') return ''
  return value.length >= 2 ? value : null
}
