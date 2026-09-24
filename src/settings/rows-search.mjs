// The Search and Engines sections: the instance itself, and which of its
// engines are asked. Row objects as the page draws them (SettingRow.qml).

import { ENGINE_CHOICES, ENGINE_LABELS, LANGUAGE_CHOICES, PAGE_SIZE_CHOICES, SUGGESTION_CHOICES } from './choices.mjs'
import { readEngines, readLanguage } from './config.mjs'
import { endpointTestText, searchSpeedText, versionText } from './reports.mjs'

/** SearXNG on or off, its update, and what it searches in: language, page size. */
export function searchRows (settings, state, version) {
  const running = state === 'running'
  const rows = [
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
      key: 'engineUpdate',
      type: 'action',
      label: 'Update SearXNG',
      hint: versionText(version),
      action: 'update',
      button: 'Update'
    }
  ]
  const language = readLanguage(settings.searxngLanguage)
  rows.push(
    {
      key: 'searxngLanguage',
      type: 'choice',
      control: 'dropdown',
      label: 'Language / region',
      hint: language === 'default' ? 'the instance’s own default'
        : language === 'auto' ? 'SearXNG guesses from the query'
        : language === 'all' ? 'every language' : 'results in ' + language + ' first',
      options: LANGUAGE_CHOICES.indexOf(language) === -1 ? LANGUAGE_CHOICES.concat([language]) : LANGUAGE_CHOICES,
      value: language
    },
    {
      key: 'resultsPerPage',
      type: 'choice',
      label: 'Results per page',
      hint: 'every page shows this many, however many SearXNG returns',
      options: PAGE_SIZE_CHOICES,
      value: settings.resultsPerPage
    },
    {
      key: 'searchSuggestions',
      type: 'choice',
      label: 'Suggestions',
      hint: settings.searchSuggestions === 'off'
        ? 'off — nothing typed leaves this machine until you search'
        : 'a list under the bar as you type, from ' + settings.searchSuggestions + ' through SearXNG, with your past searches first',
      options: SUGGESTION_CHOICES,
      value: settings.searchSuggestions
    }
  )
  return rows
}

/**
 * The engines, below the keys: set once, when a search feels slow. The two
 * reports first, then a switch per engine — the offered ones, and any name
 * typed into config.json by hand, which keeps its switch.
 */
export function engineRows (settings, test, speed) {
  const rows = [
    {
      key: 'engineSpeed',
      type: 'action',
      label: 'Search speed',
      hint: searchSpeedText(speed),
      action: 'time',
      button: 'Time',
      busy: !!(speed && speed.running)
    },
    {
      key: 'engineTest',
      type: 'action',
      label: 'Test engines',
      hint: test ? endpointTestText(test)
        : 'ask each engine below on its own: who answers, with how many rows, and what each one costs',
      action: 'test',
      button: 'Test',
      busy: !!(test && test.running)
    }
  ]
  const engines = readEngines(settings.searxngEngines)
  const choices = ENGINE_CHOICES.slice(0)
  for (let i = 0; i < engines.length; i++) if (choices.indexOf(engines[i]) === -1) choices.push(engines[i])
  for (let i = 0; i < choices.length; i++) {
    const name = choices[i]
    const on = engines.indexOf(name) !== -1
    rows.push({
      key: 'searxngEngine:' + name,
      type: 'toggle',
      label: ENGINE_LABELS[name] || name.charAt(0).toUpperCase() + name.slice(1),
      hint: engines.length === 0
        ? 'none chosen — SearXNG asks every engine it has enabled, which is slow'
        : ENGINE_CHOICES.indexOf(name) === -1 ? 'added by hand in config.json — switching it off removes it'
        : on ? 'asked on every search' : 'not asked',
      action: on ? 'off' : 'on',
      value: on
    })
  }
  return rows
}
