// Config text <-> settings, and the settings page rows. Option lists are declared
// once here so the page and bin/search agree.

import { readKeymap, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from './keymap.mjs'
import { DEFAULT_BINDS, normalizeBind } from './keybinds.mjs'

export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

// Where a hand-off opens the agent. Agents are discovered at runtime
// (bin/ask --agents), so they are not declared here.
export const LAUNCHER_CHOICES = ['terminal', 'tmux', 'herdr']
export const DEFAULT_AGENT = 'default'

export const DEFAULTS = {
  escapeSequence: DEFAULT_SEQUENCES[0],
  escapeTimeoutMs: DEFAULT_TIMEOUT_MS,
  resultsPerPage: 10,
  chatAgent: DEFAULT_AGENT,
  launcher: LAUNCHER_CHOICES[0],
  searchKey: DEFAULT_BINDS.search,
  newSessionKey: DEFAULT_BINDS.newSession
}

function parse (source) {
  if (typeof source !== 'string' || source.trim() === '') return {}
  try {
    const parsed = JSON.parse(source)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch (error) {
    return {}
  }
}

function oneOf (value, choices, fallback) {
  return choices.indexOf(value) !== -1 ? value : fallback
}

/** Config text -> settings; anything unreadable or unknown falls back to its default. */
export function readSettings (source) {
  const config = parse(source)
  const keymap = readKeymap(source)

  return {
    // Empty means off.
    escapeSequence: keymap.sequences.length > 0 ? keymap.sequences[0] : '',
    escapeTimeoutMs: keymap.timeoutMs,
    resultsPerPage: oneOf(config.resultsPerPage ?? config.results_per_page, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage),
    chatAgent: agentId(config.chat_agent),
    launcher: oneOf(config.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher),
    searchKey: bind(config.search_key, DEFAULTS.searchKey),
    newSessionKey: bind(config.new_session_key, DEFAULTS.newSessionKey),
    sequences: keymap.sequences
  }
}

// An unparseable chord falls back to the default.
function bind (value, fallback) {
  return normalizeBind(value) || fallback
}

// Any non-empty id is kept; bin/ask falls back when it isn't installed.
function agentId (value) {
  const id = typeof value === 'string' ? value.trim() : ''
  return id === '' ? DEFAULT_AGENT : id
}

/** Settings -> JSON, preserving keys this module does not own. */
export function writeSettings (settings, source) {
  const config = parse(source)

  config.escape_sequence = normalizeSequence(settings.escapeSequence) ?? DEFAULTS.escapeSequence
  config.results_per_page = oneOf(settings.resultsPerPage, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage)
  config.chat_agent = agentId(settings.chatAgent)
  config.launcher = oneOf(settings.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher)
  config.search_key = bind(settings.searchKey, DEFAULTS.searchKey)
  config.new_session_key = bind(settings.newSessionKey, DEFAULTS.newSessionKey)

  return JSON.stringify(config, null, 2) + '\n'
}

/** What the settings page knows about the SearXNG instance. */
export const ENGINE_STATES = ['unknown', 'running', 'stopped']

/**
 * The settings page rows, in order. `engine` is the SearXNG switch: whether the
 * instance answers, not a stored setting.
 */
export function settingsRows (settings, engine = 'unknown', agents = null) {
  const state = ENGINE_STATES.indexOf(engine) === -1 ? 'unknown' : engine
  const running = state === 'running'
  const known = agents && Array.isArray(agents.agents) ? agents.agents : []
  const agentIds = known.map(agent => agent.id)
  const defaultId = agents && typeof agents.default === 'string' ? agents.default : ''
  const chatAgent = settings.chatAgent === DEFAULT_AGENT || agentIds.indexOf(settings.chatAgent) !== -1
    ? settings.chatAgent
    : DEFAULT_AGENT
  return [
    { type: 'section', label: 'Search' },
    {
      key: 'engine',
      type: 'toggle',
      label: 'SearXNG',
      hint: state === 'unknown' ? 'checking whether the instance answers…'
        : running ? 'running — searches go through it'
        : 'not running — start it to search',
      action: running ? 'stop' : 'start',   // what flipping it does
      busy: state === 'unknown',            // the probe has not answered yet
      value: running
    },
    {
      key: 'resultsPerPage',
      type: 'choice',
      label: 'Results per page',
      hint: 'every page shows this many, however many SearXNG returns',
      options: PAGE_SIZE_CHOICES,
      value: settings.resultsPerPage
    },
    { type: 'section', label: 'Ask' },
    {
      key: 'chatAgent',
      type: 'choice',
      control: 'dropdown',       // seven-plus options: a list, not a row of chips
      label: 'Agent',
      hint: agents === null ? 'finding installed agents…'
        : known.length === 0 ? 'nothing installed — pick one with: omarchy default agent <name>'
        : agents.configured ? `default is ${defaultId}, from omarchy default agent`
        : `default is ${defaultId} — omarchy default agent is unset, so the first installed stands in`,
      options: [DEFAULT_AGENT].concat(agentIds),
      value: chatAgent
    },
    {
      key: 'launcher',
      type: 'choice',
      label: 'Hand off to',
      hint: 'where enter on an answer opens the agent with it',
      options: LAUNCHER_CHOICES,
      value: settings.launcher
    },
    { type: 'section', label: 'Keys' },
    {
      key: 'escapeSequence',
      type: 'text',
      normalize: 'sequence',
      label: 'Leave insert with',
      hint: 'any keys, typed within vim’s timeoutlen. Empty turns it off',
      placeholder: 'off',
      value: settings.escapeSequence
    },
    {
      key: 'searchKey',
      type: 'text',
      normalize: 'bind',
      label: 'Search',
      hint: 'runs the query, the same as the button beside the field',
      placeholder: DEFAULTS.searchKey,
      value: settings.searchKey
    },
    {
      key: 'newSessionKey',
      type: 'text',
      normalize: 'bind',
      label: 'New session',
      hint: 'forgets the conversation and starts one, from the field or the transcript',
      placeholder: DEFAULTS.newSessionKey,
      value: settings.newSessionKey
    }
  ]
}

/** A typed row's text -> the value to store, or null when the row's rule refuses it. */
export function normalizeRow (row, raw) {
  if (row && row.normalize === 'bind') return normalizeBind(raw) || null
  return normalizeSequence(raw)
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

/** Move one row's value by `delta` positions, wrapping. */
export function cycle (row, delta) {
  const index = row.options.indexOf(row.value)
  const next = (index + delta + row.options.length) % row.options.length
  return row.options[next]
}
