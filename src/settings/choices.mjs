// Every option the settings page offers, and what each setting is when nothing
// was chosen. Declared once, here: the page reads them, and bin/search mirrors
// the ones it needs in backend/omaseek/search/config.py (PAGE_SIZE_CHOICES,
// DEFAULT_ENGINES, LANGUAGE_PATTERN) — change both.

import { DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS } from '../shared/vim/keymap.mjs'
import { ACTIONS, settingKey } from '../shared/vim/keybinds.mjs'
import { FOLLOW_SEARCH } from '../translate/translate.mjs'

export const LINE_NUMBER_CHOICES = ['relative', 'absolute', 'hide']

// The page squares under the results, absolute first: a page number is what the
// status line says and what 5gp asks for, so that is what a square shows until
// told otherwise. No 'hide': a square with no number on it would say nothing at
// all, and the strip is how the mouse pages.
export const PAGE_NUMBER_CHOICES = ['absolute', 'relative']

export const PAGE_SIZE_CHOICES = [5, 10, 15, 20]

// The SearXNG engines the page switches, mirrored as DEFAULT_ENGINES in
// backend/omaseek/search/config.py. Measured to answer, and fast; the rest mostly answer with a
// CAPTCHA or nothing. A name typed into searxng_engines by hand is kept.
// Measured against a local instance on 2026-09-18, three queries each: the
// defaults answer in 0.2-0.6 s, startpage brings the most rows but takes
// 1-2 s, yep 20 rows, yandex 10, yahoo 7. google and duckduckgo answer or
// CAPTCHA depending on the hour, which is why google is a switch rather than a
// default, and why Test SearXNG exists. duckduckgo is a default anyway: engines
// are asked together, so a quiet one costs the page nothing. mojeek and qwant refused every query
// here, and mwmbl suspended itself after one, so none of them is offered —
// SearXNG knows 58 general engines and any of them can still be named by hand
// in searxng_engines, which keeps its own switch.
export const ENGINE_CHOICES = ['google cse', 'bing', 'brave', 'google', 'duckduckgo',
  'startpage', 'yep', 'yandex', 'yahoo']
export const DEFAULT_ENGINES = ['google cse', 'bing', 'brave', 'duckduckgo']
// How a switch is labelled where capitalising the SearXNG name reads wrong.
export const ENGINE_LABELS = { 'google cse': 'Google CSE', duckduckgo: 'DuckDuckGo' }

// SearXNG's language/region codes. 'default' sends none, leaving the instance's
// own default; 'auto' asks SearXNG to guess from the query. Mirrored as the
// LANGUAGE_PATTERN in backend/omaseek/search/config.py, which accepts any well-formed code.
export const LANGUAGE_CHOICES = [
  'default', 'auto', 'all', 'en', 'en-US', 'en-GB', 'de', 'de-DE', 'fr', 'fr-FR',
  'es', 'es-ES', 'it-IT', 'nl-NL', 'pt-BR', 'pl-PL', 'sv-SE', 'ru-RU', 'ja-JP',
  'ko-KR', 'zh-CN', 'zh-TW'
]
export const LANGUAGE_PATTERN = /^(default|auto|all|[a-z]{2,3}(-[A-Z]{2})?)$/

// Where a hand-off opens the agent. Agents are discovered at runtime
// (bin/ask --agents), so they are not declared here.
export const LAUNCHER_CHOICES = ['terminal', 'tmux', 'herdr']
export const DEFAULT_AGENT = 'default'
// The reasoning-effort levels each agent's CLI takes on its command line, by
// agent id; one missing has no such flag. Mirrored as `efforts` in AGENTS in
// backend/omaseek/ask/agents.py; change both.
export const EFFORT_CHOICES = {
  claude: ['low', 'medium', 'high', 'xhigh', 'max'],
  codex: ['low', 'medium', 'high', 'xhigh', 'max'],
  opencode: ['minimal', 'low', 'medium', 'high', 'max'],
  copilot: ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']
}
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
  chatEfforts: {},
  launcher: LAUNCHER_CHOICES[0],
  stream: true,
  searxngEngines: DEFAULT_ENGINES,
  translateLanguage: FOLLOW_SEARCH,
  translateAgent: SAME_AS_ASK,
  translateModels: {},
  translateEfforts: {},
  searxngLanguage: LANGUAGE_CHOICES[0]
}
for (let i = 0; i < ACTIONS.length; i++) DEFAULTS[settingKey(ACTIONS[i])] = ACTIONS[i].default

// The keys settings cannot move, listed so the page is also the answer to
// "what can I press". KEYS.md has the long form.
export const FIXED_KEYS = [
  { label: 'Anywhere', keys: 'esc cancels a pending/active find first · otherwise steps back: insert → normal → the field → closed · ctrl+, settings · ctrl+shift+c copies · ctrl+v ctrl+shift+v paste into the bar' },
  { label: 'Field', keys: 'insert: ctrl+w ctrl+u delete back · ctrl+t translate the bar · ctrl+j new line (ask) · ↑ ↓ past queries (search), lines then past questions (ask) · normal: vim motions, U the query or question before, gg G first and last line (ask), gT translate the bar, gt the selection (visual), ga gA hand off, gd ask now, gj into the ask bar, gs search — the bar, or the selection in visual, gx opens the URL under the cursor, q or esc stops a reply being written (ask), o O open line (ask), f{char} then f/F repeats, r{char}, d c y, text objects, v V, p P, u undo (a whole change), ctrl+r redo, counts' },
  { label: 'Results', keys: 'j k ↓ ↑ move · ctrl+d ctrl+u half a screen · gg G first, last · → ← page · 5gp jumps to page 5 · y Y copy the URL, the title too · ctrl+l into the translation · counts (3j) · / ? n N search the rows · gn, or k on the first row, field normal · gi i a field insert' },
  { label: 'Answer', keys: 'q stops a reply being written · h j k l w b e 0 ^ _ $ move · f t ; , find · v V select · gv reselect · y{motion} yy yank · gd ask about the selection now · gj the selection into the ask bar, unsent · gt translate the selection or the word under the cursor · p P put in the ask bar · ctrl+l into the translation · / ? n N search · * # the word under the cursor · gn, or k on the first line, field normal · gi i a field insert' },
  { label: 'Sessions (ask)', keys: 'L and H above — the next saved conversation and the one before — are read in the answer and in the field’s normal mode · 3L walks three · the numbered squares under the status line do the same with a click' },
  { label: 'Pages (search)', keys: 'l h the next page and the one before · 5l 3h walk several · 5gp jumps to page 5 · the numbered squares do the same with a click, and › fetches the page after them' },
  { label: 'Translate', keys: 'gt gT or the translate button open it on the right · ctrl+l moves into it, ctrl+h or esc back · there the answer’s vim keys work, and ctrl+x or × closes it · in ask, ctrl+x elsewhere closes the conversation' },
  { label: 'Settings', keys: '/ filter the page · j k move, k on the first row back up to the filter · gg G first, last · h l change · enter edit · esc back' }
]

/** What the settings page knows about the SearXNG instance. */
export const ENGINE_STATES = ['unknown', 'running', 'stopped']
