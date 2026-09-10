// The user's settings: what the config file means, what the settings page
// offers, and how a change is written back.
//
// UI and backend must agree on the option lists, so they are declared once
// here. Pure, so the normalising rules run under node — see
// test/settings.test.mjs.

import { readKeymap, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from './keymap.mjs'

export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

// There is one backend — a SearXNG instance you run yourself — so there is no
// engine to choose. Its address lives in the config file as `searxng_url`,
// hand-edited, because it is set once per machine and never toggled.
export const DEFAULTS = {
  escapeSequence: DEFAULT_SEQUENCES[0],
  escapeTimeoutMs: DEFAULT_TIMEOUT_MS,
  resultsPerPage: 10
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
    sequences: keymap.sequences
  }
}

/**
 * Settings -> the JSON to persist, preserving anything else already in the
 * file so hand-written keys are never silently dropped.
 */
export function writeSettings (settings, source) {
  const config = parse(source)

  config.escape_sequence = normalizeSequence(settings.escapeSequence) ?? DEFAULTS.escapeSequence
  config.results_per_page = oneOf(settings.resultsPerPage, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage)

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
export function settingsRows (settings, engine = 'unknown') {
  const state = ENGINE_STATES.indexOf(engine) === -1 ? 'unknown' : engine
  const running = state === 'running'
  return [
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
      key: 'escapeSequence',
      type: 'text',
      label: 'Leave insert with',
      hint: 'any keys, typed within vim’s timeoutlen. Empty turns it off',
      placeholder: 'off',
      value: settings.escapeSequence
    },
    {
      key: 'resultsPerPage',
      type: 'choice',
      label: 'Results per page',
      hint: 'every page shows this many, however many SearXNG returns',
      options: PAGE_SIZE_CHOICES,
      value: settings.resultsPerPage
    }
  ]
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
