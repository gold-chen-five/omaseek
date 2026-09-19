// The settings page, row by row: each section built by its own module, in the
// order the page lists them, and the checks a typed row runs before it is kept.

import { ACTIONS, settingKey, normalizeBinding, actionById } from '../shared/vim/keybinds.mjs'
import { bindingProblem } from '../shared/vim/keys.mjs'
import { ENGINE_STATES, FIXED_KEYS } from './choices.mjs'
import { normalizeSequence } from './config.mjs'
import { searchRows, engineRows } from './rows-search.mjs'
import { askRows, translateRows, displayRows } from './rows-ask.mjs'

/**
 * The settings page rows, in order. `engine` is the SearXNG switch: whether the
 * instance answers, not a stored setting. `test` is the last endpoint test, and
 * `version` the last version check; null before either ran.
 */
export function settingsRows (settings, engine = 'unknown', agents = null, catalog = null, test = null, version = null, speed = null, translateCatalog = null, shortcut = null) {
  const state = ENGINE_STATES.indexOf(engine) === -1 ? 'unknown' : engine
  return [].concat(
    [{ type: 'section', label: 'Search' }], searchRows(settings, state, version),
    [{ type: 'section', label: 'Ask' }], askRows(settings, agents, catalog),
    [{ type: 'section', label: 'Translate' }], translateRows(settings, agents, translateCatalog),
    [{ type: 'section', label: 'Display' }], displayRows(settings),
    [{ type: 'section', label: 'Keys' }], [shortcutRow(shortcut)], keyRows(settings),
    // The engine switches sit below the keys: they are set once, when a search
    // feels slow, while every row above is changed more often.
    [{ type: 'section', label: 'Engines' }], engineRows(settings, test, speed),
    [{ type: 'section', label: 'Fixed keys' }], fixedRows()
  )
}

/**
 * The key that opens the panel, as bin/keybind --status found it. A plugin
 * cannot bind one itself, so this is the only row that offers to change the
 * user's own Hyprland config — and only while the key is free: a key already
 * bound is described, never replaced. null before the check has answered.
 */
export function shortcutRow (status) {
  const row = { key: 'shortcut', label: 'Open omaseek with' }
  const state = status && status.ok ? status.state : status ? 'unreadable' : 'checking'
  const key = status && status.key ? status.key : 'SUPER + D'
  if (state === 'free') {
    return Object.assign(row, {
      type: 'action',
      hint: `${key} is free — Add shows the line for your Hyprland bindings and asks before writing it`,
      action: 'add',
      button: 'Add'
    })
  }
  const holder = status && status.holder ? /"[^"]*"\s*,\s*"([^"]*)"/.exec(status.holder) : null
  const hints = {
    checking: 'checking your Hyprland bindings…',
    bound: `${key} — in your Hyprland bindings`,
    taken: `${key} already opens ${holder ? holder[1] : 'something else'} — bind another key to omarchy-shell shell toggle omaseek`,
    missing: 'no ~/.config/hypr/bindings.lua to add a key to — the bar icon opens it',
    unreadable: 'could not read your Hyprland bindings — the bar icon opens it'
  }
  return Object.assign(row, { type: 'info', hint: hints[state] || hints.unreadable })
}

/** The escape sequence, then a row per rebindable key, in ACTIONS' order. */
function keyRows (settings) {
  const rows = [
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
  return rows
}

/** The keys settings cannot move, as read-only rows closing the page. */
function fixedRows () {
  const rows = []
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

/** Move one row's value by `delta` positions, wrapping. */
export function cycle (row, delta) {
  const index = row.options.indexOf(row.value)
  const next = (index + delta + row.options.length) % row.options.length
  return row.options[next]
}
