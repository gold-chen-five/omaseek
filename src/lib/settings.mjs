// Config text <-> settings, and the settings page rows. Option lists are declared
// once here so the page and bin/search agree; the keys come from ACTIONS in
// keybinds.mjs, so a new binding is one entry there.

import { parseObject } from './json.mjs'
import { readKeymap, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from './keymap.mjs'
import { ACTIONS, settingKey, normalizeBinding, actionById } from './keybinds.mjs'
import { bindingProblem } from './keys.mjs'
import { TRANSLATE_LANGUAGES, FOLLOW_SEARCH, defaultTarget, targetLabel, readTarget } from './translate.mjs'

export const LINE_NUMBER_CHOICES = ['relative', 'absolute', 'hide']

// The page squares under the results, absolute first: a page number is what the
// status line says and what 5gp asks for, so that is what a square shows until
// told otherwise. No 'hide': a square with no number on it would say nothing at
// all, and the strip is how the mouse pages.
export const PAGE_NUMBER_CHOICES = ['absolute', 'relative']

export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

// The SearXNG engines the page switches, mirrored as DEFAULT_ENGINES in
// bin/search. Measured to answer, and fast; the rest mostly answer with a
// CAPTCHA or nothing. A name typed into searxng_engines by hand is kept.
// Measured against a local instance on 2026-09-18, three queries each: the
// defaults answer in 0.2-0.6 s, startpage brings the most rows but takes
// 1-2 s, yep 20 rows, yandex 10, yahoo 7. google and duckduckgo answer or
// CAPTCHA depending on the hour, which is why they are switches rather than
// defaults, and why Test SearXNG exists. mojeek and qwant refused every query
// here, and mwmbl suspended itself after one, so none of them is offered —
// SearXNG knows 58 general engines and any of them can still be named by hand
// in searxng_engines, which keeps its own switch.
export const ENGINE_CHOICES = ['google cse', 'bing', 'brave', 'google', 'duckduckgo',
  'startpage', 'yep', 'yandex', 'yahoo']
export const DEFAULT_ENGINES = ['google cse', 'bing', 'brave', 'duckduckgo']
// How a switch is labelled where capitalising the SearXNG name reads wrong.
const ENGINE_LABELS = { 'google cse': 'Google CSE', duckduckgo: 'DuckDuckGo' }

// SearXNG's language/region codes. 'default' sends none, leaving the instance's
// own default; 'auto' asks SearXNG to guess from the query. Mirrored as the
// LANGUAGE pattern in bin/search, which accepts any well-formed code.
export const LANGUAGE_CHOICES = [
  'default', 'auto', 'all', 'en', 'en-US', 'en-GB', 'de', 'de-DE', 'fr', 'fr-FR',
  'es', 'es-ES', 'it-IT', 'nl-NL', 'pt-BR', 'pl-PL', 'sv-SE', 'ru-RU', 'ja-JP',
  'ko-KR', 'zh-CN', 'zh-TW'
]
const LANGUAGE_PATTERN = /^(default|auto|all|[a-z]{2,3}(-[A-Z]{2})?)$/

// Where a hand-off opens the agent. Agents are discovered at runtime
// (bin/ask --agents), so they are not declared here.
export const LAUNCHER_CHOICES = ['terminal', 'tmux', 'herdr']
export const DEFAULT_AGENT = 'default'
// Translate with: the first option, stored as 'same' — whoever Ask uses.
export const SAME_AS_ASK = 'same as Ask'

export const DEFAULTS = {
  escapeSequence: DEFAULT_SEQUENCES[0],
  escapeTimeoutMs: DEFAULT_TIMEOUT_MS,
  resultsPerPage: 10,
  lineNumbers: LINE_NUMBER_CHOICES[0],
  pageNumbers: PAGE_NUMBER_CHOICES[0],
  chatAgent: DEFAULT_AGENT,
  chatModels: {},
  launcher: LAUNCHER_CHOICES[0],
  stream: true,
  searxngEngines: DEFAULT_ENGINES,
  translateLanguage: FOLLOW_SEARCH,
  translateAgent: SAME_AS_ASK,
  translateModels: {},
  searxngLanguage: LANGUAGE_CHOICES[0]
}
for (let i = 0; i < ACTIONS.length; i++) DEFAULTS[settingKey(ACTIONS[i])] = ACTIONS[i].default

// The keys settings cannot move, listed so the page is also the answer to
// "what can I press". KEYS.md has the long form.
export const FIXED_KEYS = [
  { label: 'Anywhere', keys: 'esc cancels a pending/active find first · otherwise steps back: insert → normal → the field → closed · ctrl+, settings' },
  { label: 'Field', keys: 'insert: ctrl+w ctrl+u delete back · ctrl+t translate the bar · ctrl+j new line (ask) · ↑ ↓ past queries (search), lines then past questions (ask) · normal: vim motions, U the query or question before, gT translate the bar, gt the selection (visual), gx opens the URL under the cursor, q or esc stops a reply being written (ask), o O open line (ask), f{char} then f/F repeats, r{char}, d c y, text objects, v V, p P, u ctrl+r, counts' },
  { label: 'Results', keys: 'j k ↓ ↑ move · ctrl+d ctrl+u half a screen · gg G first, last · → ← page · 5gp jumps to page 5 · y Y copy the URL, the title too · counts (3j) · / ? n N search the rows · gn field normal · gi i a field insert' },
  { label: 'Answer', keys: 'q stops a reply being written · h j k l w b e 0 ^ _ $ move · f t ; , find · v V select · gv reselect · y{motion} yy yank · gc the selection into the ask bar, to ask about · gt translate the selection or the word under the cursor · p P put in the ask bar · / ? n N search · * # the word under the cursor · gn field normal · gi i a field insert' },
  { label: 'Sessions (ask)', keys: 'L and H above — the next saved conversation and the one before — are read in the answer and in the field’s normal mode · 3L walks three · the numbered squares under the status line do the same with a click' },
  { label: 'Pages (search)', keys: 'l h the next page and the one before · 5l 3h walk several · 5gp jumps to page 5 · the numbered squares do the same with a click, and › fetches the page after them' },
  { label: 'Translate', keys: 'gt gT or the translate button open it on the right · ctrl+x or × close it, before ctrl+x forgets anything · copy takes the translation' },
  { label: 'Settings', keys: 'j k move · h l change · enter edit · / field normal · esc back' }
]

function oneOf (value, choices, fallback) {
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
    launcher: oneOf(config.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher),
    // On unless it was deliberately turned off: an agent that cannot stream
    // falls back on its own, so this is only for turning the behaviour off.
    stream: config.stream !== false,
    searxngEngines: readEngines(config.searxng_engines),
    translateLanguage: readTarget(config.translate_language),
    translateAgent: config.translate_agent === undefined || config.translate_agent === 'same'
      ? SAME_AS_ASK : agentId(config.translate_agent),
    translateModels: readModels(config.translate_models),
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
function readEngines (value) {
  if (!Array.isArray(value)) return DEFAULT_ENGINES.slice(0)
  const names = []
  for (let i = 0; i < value.length; i++) {
    const name = typeof value[i] === 'string' ? value[i].trim() : ''
    if (name && names.indexOf(name) === -1) names.push(name)
  }
  return names
}

function readLanguage (value) {
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
function agentId (value) {
  const id = typeof value === 'string' ? value.trim() : ''
  return id === '' ? DEFAULT_AGENT : id
}

function modelId (value) {
  if (typeof value !== 'string') return ''
  const text = value.trim()
  return /[\x00-\x1f\x7f]/.test(text) ? '' : text
}

function readModels (value) {
  const models = {}
  if (!value || typeof value !== 'object' || Array.isArray(value)) return models
  for (const id of Object.keys(value)) {
    const model = modelId(value[id])
    if (model && id !== '__proto__') models[id] = model
  }
  return models
}

// Who answers, given what discovery found: the installed ids, and the one that
// stands in for 'default'. Read by the model row and by the model handed to the
// CLI, which must agree.
function agentChoices (agents) {
  const known = agents && Array.isArray(agents.agents) ? agents.agents : []
  const ids = []
  for (let i = 0; i < known.length; i++) ids.push(known[i].id)
  return {
    known: known,
    ids: ids,
    defaultId: agents && typeof agents.default === 'string' ? agents.default : ''
  }
}

function modelSelection (settings, agent, catalog, stored = 'chatModels') {
  const options = ['default']
  const discovered = catalog && catalog.agent === agent && Array.isArray(catalog.models) ? catalog.models : []
  for (const choice of discovered) {
    const id = modelId(choice)
    if (id && options.indexOf(id) === -1) options.push(id)
  }
  const saved = readModels(settings[stored])[agent] || ''
  return { options: options, value: options.indexOf(saved) !== -1 ? saved : 'default' }
}

/**
 * Shift+tab: the installed agent after the one answering now, wrapping. From
 * 'default' it counts from the agent that stands in for it, so the first press
 * always changes who answers. Null when there is nothing else to switch to.
 */
export function nextAgent (agents, chatAgent) {
  const { ids, defaultId } = agentChoices(agents)
  if (ids.length === 0) return null
  const current = agentId(chatAgent) === DEFAULT_AGENT ? defaultId : agentId(chatAgent)
  const at = ids.indexOf(current)
  const next = ids[(at + 1) % ids.length]
  return next === current ? null : next
}

/** The model the panel may pass to the CLI; empty deliberately means its default. */
export function selectedModel (settings, agents = null, catalog = null) {
  const choices = agentChoices(agents)
  const requested = agentId(settings.chatAgent)
  const agent = requested !== DEFAULT_AGENT && choices.ids.indexOf(requested) !== -1
    ? requested : choices.defaultId
  const selected = modelSelection(settings, agent, catalog).value
  return selected === 'default' ? '' : selected
}

/**
 * Who translates: the agent chosen under Translate, or — as it is by default —
 * whoever answers Ask. '' before discovery has found anyone.
 */
export function translateAgentOf (settings, agents = null) {
  const choices = agentChoices(agents)
  const chosen = settings ? settings.translateAgent : SAME_AS_ASK
  if (chosen && chosen !== SAME_AS_ASK && choices.ids.indexOf(chosen) !== -1) return chosen
  const ask = settings ? agentId(settings.chatAgent) : DEFAULT_AGENT
  return ask !== DEFAULT_AGENT && choices.ids.indexOf(ask) !== -1 ? ask : choices.defaultId
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
  config.launcher = oneOf(settings.launcher, LAUNCHER_CHOICES, DEFAULTS.launcher)
  config.stream = settings.stream !== false
  config.searxng_engines = readEngines(settings.searxngEngines)
  const target = readTarget(settings.translateLanguage)
  if (target === FOLLOW_SEARCH) delete config.translate_language   // absent follows the search language
  else config.translate_language = target
  config.translate_agent = !settings.translateAgent || settings.translateAgent === SAME_AS_ASK
    ? 'same' : agentId(settings.translateAgent)
  config.translate_models = readModels(settings.translateModels)
  const language = readLanguage(settings.searxngLanguage)
  if (language === LANGUAGE_CHOICES[0]) delete config.searxng_language   // absent is the instance's default
  else config.searxng_language = language
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i]
    config[action.config] = normalizeBinding(action, settings[settingKey(action)]) || action.default
  }

  return JSON.stringify(config, null, 2) + '\n'
}

/** What the settings page knows about the SearXNG instance. */
export const ENGINE_STATES = ['unknown', 'running', 'stopped']

/**
 * What the endpoint test found, from `bin/search --test`, as the Test row's
 * hint: how long a real query took and which engine gave what.
 */
// SearXNG prefixes an engine it has parked with "Suspended: "; inside the
// brackets after a row count, the prefix says nothing the brackets do not.
function shortReason (reason) {
  const text = String(reason)
  return text.indexOf('Suspended: ') === 0 ? text.slice('Suspended: '.length) : text
}

export function endpointTestText (test) {
  if (!test) return ''
  if (test.running) return 'asking each engine in turn…'
  if (!test.ok) return test.message || 'SearXNG did not answer'
  const parts = []
  const answers = test.engines || {}
  const named = {}
  for (const name in answers) {
    const answer = answers[name]
    // A count alone is what --test printed before it timed each engine.
    const rows = typeof answer === 'number' ? answer : answer.rows
    const ms = typeof answer === 'number' ? null : answer.ms
    const reason = typeof answer === 'number' ? '' : (answer.reason || '')
    named[name] = true
    // The reason rides along with the count: an engine that CAPTCHAs answers in
    // 3 ms with no rows, which on its own reads like the fastest of the lot.
    const timed = `${name} ${rows}` + (ms === null || ms === undefined ? '' : ` in ${ms} ms`)
    parts.push(reason ? `${timed} (${shortReason(reason)})` : timed)
  }
  const silent = test.unresponsive || []
  for (let i = 0; i < silent.length; i++) {
    // An engine that was asked is already listed, with its time and its reason.
    if (named[silent[i].engine]) continue
    parts.push(`${silent[i].engine}: ${silent[i].reason}`)
  }
  if (Object.keys(answers).length === 0 && silent.length === 0) parts.push('no rows')
  return parts.join(' · ')
}

/**
 * The Search speed row's hint, from `bin/search --time`: one real search, every
 * engine at once, which is the wait a keypress actually buys. The engine times
 * from the test row are each engine alone and never add up to this.
 */
export function searchSpeedText (speed) {
  if (!speed) return 'time one real search: every engine at once, as a keypress sends it'
  if (speed.running) return 'searching…'
  if (!speed.ok) return speed.message || 'SearXNG did not answer'
  const silent = speed.unresponsive || []
  const parts = [`${speed.ms} ms for ${speed.rows} rows`]
  for (let i = 0; i < silent.length; i++) parts.push(`${silent[i].engine}: ${silent[i].reason}`)
  return parts.join(' · ')
}

/**
 * The Update row's hint: the running version, and whether it is the newest
 * image, from `bin/search --version`. The date is the part a person compares;
 * the commit after it is only noise here.
 */
export function versionText (version) {
  if (!version) return 'pull the latest image; restart only when it changed'
  if (version.checking) return 'checking the running version…'
  if (!version.ok) return 'not running — start it to see its version'
  const running = version.version ? String(version.version).split('+')[0] : 'unknown version'
  const latest = version.latest ? String(version.latest).split('-')[0] : ''
  if (version.current === true) return `${running} — the latest`
  if (version.current === false) return `${running} running · ${latest} available — update`
  return `${running} running · could not check for a newer one`
}

/**
 * The settings page rows, in order. `engine` is the SearXNG switch: whether the
 * instance answers, not a stored setting. `test` is the last endpoint test, and
 * `version` the last version check; null before either ran.
 */
export function settingsRows (settings, engine = 'unknown', agents = null, catalog = null, test = null, version = null, speed = null, translateCatalog = null) {
  const state = ENGINE_STATES.indexOf(engine) === -1 ? 'unknown' : engine
  const running = state === 'running'
  const { known, ids, defaultId } = agentChoices(agents)
  const chatAgent = settings.chatAgent === DEFAULT_AGENT || ids.indexOf(settings.chatAgent) !== -1
    ? settings.chatAgent
    : DEFAULT_AGENT
  const modelAgent = chatAgent !== DEFAULT_AGENT ? chatAgent : defaultId
  const model = modelSelection(settings, modelAgent, catalog)
  const translator = translateAgentOf(settings, agents)
  const translateModel = modelSelection(settings, translator, translateCatalog, 'translateModels')
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
    }
  )
  rows.push(
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
      options: [DEFAULT_AGENT].concat(ids),
      value: chatAgent
    },
    {
      key: 'chatModel:' + modelAgent,
      type: 'choice',
      control: 'dropdown',
      label: 'Model',
      hint: modelAgent ? `${modelAgent} — default uses the CLI's choice; applies next turn and to hand-offs`
        + (catalog && catalog.agent === modelAgent && catalog.message ? ` · ${catalog.message}` : '')
        : 'choose an installed agent first',
      options: model.options,
      value: model.value
    },
    {
      key: 'stream',
      type: 'toggle',
      label: 'Answer as it is written',
      hint: settings.stream
        ? 'the reply appears word by word, where the agent can do that'
        : 'the reply appears whole, once the agent has finished',
      action: settings.stream ? 'off' : 'on',   // what flipping it does
      value: settings.stream !== false
    },
    {
      key: 'launcher',
      type: 'choice',
      label: 'Hand off to',
      hint: 'where a hand-off opens the agent, with the text waiting unsent in its input',
      options: LAUNCHER_CHOICES,
      value: settings.launcher
    },
    { type: 'section', label: 'Translate' },
    {
      key: 'translateLanguage',
      type: 'choice',
      control: 'dropdown',
      label: 'Translate into',
      hint: settings.translateLanguage === FOLLOW_SEARCH || !settings.translateLanguage
        ? 'into ' + targetLabel(defaultTarget(settings.searxngLanguage)) +
          ' — the search language, or 繁體中文 when that names none. Text already in it goes into English'
        : 'into ' + targetLabel(settings.translateLanguage) + '; text already in it goes into English',
      options: [FOLLOW_SEARCH].concat(TRANSLATE_LANGUAGES.map(language => language.code)),
      value: readTarget(settings.translateLanguage)
    },
    {
      key: 'translateAgent',
      type: 'choice',
      control: 'dropdown',
      label: 'Translate with',
      hint: translator
        ? (settings.translateAgent === SAME_AS_ASK || !settings.translateAgent
            ? translator + ' — whoever Ask uses; choose a quick one to translate faster'
            : translator + ' translates, whoever Ask uses')
        : 'no agent installed',
      options: [SAME_AS_ASK].concat(ids),
      value: settings.translateAgent && (settings.translateAgent === SAME_AS_ASK || ids.indexOf(settings.translateAgent) !== -1)
        ? settings.translateAgent : SAME_AS_ASK
    },
    {
      key: 'translateModel:' + translator,
      type: 'choice',
      control: 'dropdown',
      label: 'Translation model',
      hint: translator ? `${translator} — default uses the CLI's choice; a small, quick model translates fastest`
        + (translateCatalog && translateCatalog.agent === translator && translateCatalog.message ? ` · ${translateCatalog.message}` : '')
        : 'choose an installed agent first',
      options: translateModel.options,
      value: translateModel.value
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
    {
      key: 'pageNumbers',
      type: 'choice',
      label: 'Page numbers',
      hint: settings.pageNumbers === 'relative'
        ? 'the page squares count from the page on screen, so 3h and 5l read off the row'
        : 'the page squares carry their own page number',
      options: PAGE_NUMBER_CHOICES,
      value: settings.pageNumbers
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
  )
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
  // The engine switches sit below the keys: they are set once, when a search
  // feels slow, while every row above is changed more often.
  rows.push({ type: 'section', label: 'Engines' })
  rows.push(
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
  )
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
