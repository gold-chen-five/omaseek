// The user's settings: what the config file means, what the settings page
// offers, and how a change is written back.
//
// UI and backend must agree on the option lists, so they are declared once
// here. Pure, so the normalising rules run under node — see
// test/settings.test.mjs.

import { readKeymap, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from './keymap.mjs'

export const ENGINES = ['auto', 'duckduckgo', 'exa']
export const SEQUENCE_CHOICES = ['jk', 'kj', 'jj', 'off']
export const TIMEOUT_CHOICES = [150, 200, 300, 500]
export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

export const DEFAULTS = {
  engine: 'auto',
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
    engine: oneOf(config.engine, ENGINES, DEFAULTS.engine),
    // The keymap reader already handles strings, lists and "off"; the page
    // only offers single sequences, so show the first one it resolved.
    escapeSequence: keymap.sequences.length > 0 ? keymap.sequences[0] : 'off',
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

  config.engine = oneOf(settings.engine, ENGINES, DEFAULTS.engine)
  config.escape_sequence = settings.escapeSequence === 'off' ? '' : settings.escapeSequence
  config.escape_timeout_ms = oneOf(settings.escapeTimeoutMs, TIMEOUT_CHOICES, DEFAULTS.escapeTimeoutMs)
  config.results_per_page = oneOf(settings.resultsPerPage, PAGE_SIZE_CHOICES, DEFAULTS.resultsPerPage)

  return JSON.stringify(config, null, 2) + '\n'
}

/** The rows the settings page shows, in order. */
export function settingsRows (settings) {
  return [
    {
      key: 'engine',
      label: 'Search engine',
      hint: 'auto tries DuckDuckGo, then Exa if it is blocked',
      options: ENGINES,
      value: settings.engine
    },
    {
      key: 'escapeSequence',
      label: 'Leave insert with',
      hint: 'typed quickly, like vim’s inoremap jk <Esc>',
      options: SEQUENCE_CHOICES,
      value: settings.escapeSequence
    },
    {
      key: 'escapeTimeoutMs',
      label: 'Sequence window',
      hint: 'how long the two keys may take, in milliseconds',
      options: TIMEOUT_CHOICES,
      value: settings.escapeTimeoutMs
    },
    {
      key: 'resultsPerPage',
      label: 'Results per page',
      hint: 'every page shows this many, whichever engine answers',
      options: PAGE_SIZE_CHOICES,
      value: settings.resultsPerPage
    }
  ]
}

/** Move one row's value by `delta` positions, wrapping. */
export function cycle (row, delta) {
  const index = row.options.indexOf(row.value)
  const next = (index + delta + row.options.length) % row.options.length
  return row.options[next]
}
