// Config text <-> settings, and the settings page rows. Option lists are declared
// once here so the page and bin/search agree; the keys come from ACTIONS in
// keybinds.mjs, so a new binding is one entry there.

import { readKeymap, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from './keymap.mjs'
import { ACTIONS, settingKey, normalizeBinding, actionById } from './keybinds.mjs'
import { bindingProblem } from './keys.mjs'

export const LINE_NUMBER_CHOICES = ['relative', 'absolute', 'hide']

export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

// Where a hand-off opens the agent. Agents are discovered at runtime
// (bin/ask --agents), so they are not declared here.
export const LAUNCHER_CHOICES = ['terminal', 'tmux', 'herdr']
export const DEFAULT_AGENT = 'default'

export const DEFAULTS = {
  escapeSequence: DEFAULT_SEQUENCES[0],
  escapeTimeoutMs: DEFAULT_TIMEOUT_MS,
  resultsPerPage: 10,
  lineNumbers: LINE_NUMBER_CHOICES[0],
  chatAgent: DEFAULT_AGENT,
  launcher: LAUNCHER_CHOICES[0]
}
for (let i = 0; i < ACTIONS.length; i++) DEFAULTS[settingKey(ACTIONS[i])] = ACTIONS[i].default

// The keys settings cannot move, listed so the page is also the answer to
// "what can I press". KEYS.md has the long form.
export const FIXED_KEYS = [
  { label: 'Anywhere', keys: 'esc cancels a pending/active find first · otherwise steps back: insert → normal → the field → closed · ctrl+, settings · shift+tab switches' },
  { label: 'Field', keys: 'insert: ctrl+w ctrl+u delete back · ctrl+j new line (ask) · ↑ ↓ lines · normal: vim motions, f{char} then f/F repeats, r{char}, d c y, text objects, v V, p P, u ctrl+r, counts' },
  { label: 'Results', keys: 'j k ↓ ↑ move · ctrl+d ctrl+u half a screen · gg G first, last · → ← page · counts (3j) · / field normal · i a field insert' },
  { label: 'Answer', keys: 'h j k l w b e 0 ^ $ move · f t ; , find · v V select · gv reselect · y{motion} yy yank · p P put in the ask bar · / i a field' },
  { label: 'Settings', keys: 'j k move · h l change · enter edit · / field normal · esc back' }
]

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

  const settings = {
    // Empty means off.
    escapeSequence: keymap.sequences.length > 0 ? keymap.sequences[0] : '',
    escapeTimeoutMs: keymap.timeoutMs,
    resultsPerPage: oneOf(config.resultsPerPage ?? config.results_per_page, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage),
    lineNumbers: oneOf(config.line_numbers, LINE_NUMBER_CHOICES, DEFAULTS.lineNumbers),
    chatAgent: agentId(config.chat_agent),
    launcher: oneOf(config.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher),
    sequences: keymap.sequences
  }
  // An unparseable key falls back to its default.
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    settings[settingKey(action)] = normalizeBinding(action, config[action.config]) || action.default
  }
  return settings
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
  config.line_numbers = oneOf(settings.lineNumbers, LINE_NUMBER_CHOICES, DEFAULTS.lineNumbers)
  config.chat_agent = agentId(settings.chatAgent)
  config.launcher = oneOf(settings.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher)
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    config[action.config] = normalizeBinding(action, settings[settingKey(action)]) || action.default
  }

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
  const rows = [
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
      hint: 'where a hand-off opens the agent, with the text waiting unsent in its input',
      options: LAUNCHER_CHOICES,
      value: settings.launcher
    },
    { type: 'section', label: 'Display' },
    {
      key: 'lineNumbers',
      type: 'choice',
      label: 'Line numbers',
      hint: 'numbering in search results and AI responses',
      options: LINE_NUMBER_CHOICES,
      value: settings.lineNumbers
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
    }
  ]
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    rows.push({
      key: settingKey(action),
      type: 'text',
      normalize: 'bind',
      action: action.id,
      label: action.label,
      hint: action.hint,
      placeholder: action.default,
      value: settings[settingKey(action)] || action.default
    })
  }
  rows.push({ type: 'section', label: 'Fixed keys' })
  for (let i = 0; i < FIXED_KEYS.length; i++) {
    rows.push({ type: 'info', label: FIXED_KEYS[i].label, hint: FIXED_KEYS[i].keys })
  }
  return rows
}

/**
 * A typed row's text -> { value } to store, or { error } saying why it was
 * refused. A key is checked against every other key on the page, so two
 * actions can never share one.
 */
export function checkRow (row, raw, rows) {
  if (row && row.normalize === 'bind') {
    const action = actionById(row.action)
    const text = String(raw ?? '').trim() || action.default   // empty restores the default
    const binds = {}
    for (let i = 0; i < (rows || []).length; i++) if (rows[i].action) binds[rows[i].key] = rows[i].value
    const problem = bindingProblem(row.action, text, binds)
    if (problem) return { value: null, error: problem }
    return { value: normalizeBinding(action, text), error: '' }
  }
  const value = normalizeSequence(raw)
  return value === null
    ? { value: null, error: 'two keys or more: one alone could never be typed. Empty turns it off' }
    : { value: value, error: '' }
}

/** A typed row's text -> the value to store, or null when the row's rule refuses it. */
export function normalizeRow (row, raw, rows) {
  return checkRow(row, raw, rows).value
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
