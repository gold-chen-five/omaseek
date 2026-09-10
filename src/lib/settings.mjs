// The user's settings: what the config file means, what the settings page
// offers, and how a change is written back.
//
// UI and backend must agree on the option lists, so they are declared once
// here. Pure, so the normalising rules run under node — see
// test/settings.test.mjs.

import { readKeymap, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from './keymap.mjs'
import { DEFAULT_BINDS, normalizeBind } from './keybinds.mjs'

export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

// There is one backend — a SearXNG instance you run yourself — so there is no
// engine to choose. Its address lives in the config file as `searxng_url`,
// hand-edited, because it is set once per machine and never toggled.
// Where a hand-off from the AI answer opens the agent: a fresh terminal
// window (omarchy-agent's own way), a new tmux window in the Work session,
// or a new herdr tab. The chat agent is 'default' — whatever `omarchy default
// agent` is — or one id from bin/ask --agents; that list is discovered at
// runtime, so it is not declared here.
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

/**
 * Config text -> the settings the panel runs on.
 *
 * Every unreadable or unknown value falls back to its default rather than
 * failing: a typo in the config should cost that one setting, not the panel.
 */
export function readSettings (source) {
  const config = parse(source)
  const keymap = readKeymap(source)

  return {
    // Empty means off. The keymap reader already handles strings, lists and
    // "", so show the first sequence it resolved.
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

// An unparseable chord costs that one binding, not the button: the default
// stands in, and the settings row shows what is actually bound.
function bind (value, fallback) {
  return normalizeBind(value) || fallback
}

// Any non-empty id is kept: which agents exist is only known at runtime, and
// bin/ask falls back to the default when the named one is not installed.
function agentId (value) {
  const id = typeof value === 'string' ? value.trim() : ''
  return id === '' ? DEFAULT_AGENT : id
}

/**
 * Settings -> the JSON to persist, preserving anything else already in the
 * file so hand-written keys are never silently dropped.
 */
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
 * The rows the settings page shows, in order.
 *
 * `engine` is not a setting — it is whether the instance answered the last
 * probe — but it belongs on the same page, because starting and stopping it is
 * the one thing about the backend a person does from the panel. The row is
 * `type: 'action'`: no value to store, only a button to press.
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
      type: 'action',
      label: 'SearXNG',
      hint: state === 'unknown' ? 'checking whether the instance answers…'
        : running ? 'running — searches go through it'
        : 'not running — start it to search',
      action: running ? 'stop' : 'start',
      actionLabel: running ? 'Stop' : 'Start',
      value: state
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
    // The keys a person is most likely to want their own spelling of: the
    // one that leaves insert, and the two the buttons carry.
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

/**
 * A typed row's text -> what to store, or null when the row refuses it.
 *
 * The settings page does not know what makes a value good, only which rule
 * a row named, so the rules stay here with the rows that name them.
 */
export function normalizeRow (row, raw) {
  if (row && row.normalize === 'bind') return normalizeBind(raw) || null
  return normalizeSequence(raw)
}

/**
 * A typed escape sequence -> what to store, or null when it cannot be used.
 *
 * Empty turns the sequence off. A single character is refused rather than
 * accepted, because binding one key would make that key untypable — the
 * keymap reader drops it anyway, so accepting it would silently mean "off".
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
