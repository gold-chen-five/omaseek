// Result normalising, page merging, and the status line's strings. Pure, under test.

import { VIEW, PANEL, FOCUS } from './states.mjs'
import { hostOf } from './urls.mjs'

const ERROR_MESSAGES = {
  network: 'No network connection'
}

/** Backend failure -> one line a person can act on; the backend's own message wins. */
export function describeError ({ error, message } = {}) {
  return message ?? ERROR_MESSAGES[error] ?? 'Search failed'
}

/** Backend row -> the exact shape the ListModel delegate expects. */
export function normalizeRow ({ title, url, snippet, display_url: displayUrl, icon, engines } = {}) {
  return {
    title: title ?? '',
    url: url ?? '',
    snippet: snippet ?? '',
    display_url: displayUrl ?? '',
    icon: icon ?? '',
    // Which SearXNG engines found it, "brave, bing". A string, not a list: a
    // ListModel turns an array role into a nested model. Old buffers have none.
    engines: typeof engines === 'string' ? engines : ''
  }
}

/** Same page, different URL — /book/ and /stable/book/, http and https, ?utm=. */
function identity (row) {
  return `${row.display_url}|${row.title.toLowerCase()}`
}

/**
 * Merge a fetched page into the rows on screen, de-duplicating on URL and on
 * domain+title (engines return one document under several paths). Returns the
 * additions, since the caller appends to a live ListModel.
 */
export function mergeResults (existing = [], incoming = []) {
  const urls = new Set()
  const identities = new Set()

  for (const row of existing) {
    if (typeof row === 'string') {
      urls.add(row)                       // callers may pass URLs alone
      continue
    }
    urls.add(row.url)
    identities.add(identity(normalizeRow(row)))
  }

  const added = []
  for (const row of incoming) {
    const normalized = normalizeRow(row)
    if (!normalized.url || urls.has(normalized.url)) continue
    const key = identity(normalized)
    if (identities.has(key)) continue
    urls.add(normalized.url)
    identities.add(key)
    added.push(normalized)
  }
  return added
}

/** Right-hand side of the status strip. */
export function statusText ({
  view = VIEW.SEARCH, panelMode = PANEL.SEARCH, status, count = 0, query = '', page = 1,
  hasNext = false, loadingPage = false, errorMessage = '', backend = '',
  pageError = '', nextPageKey = 'l',
  agent = '', selecting = false, link = '', session = '',
  stopKey = 'esc', retryKey = 'ctrl+shift+r', canRetry = false
} = {}) {
  if (view === VIEW.SETTINGS) return 'j/k rows · h/l change · enter opens · saved as you go · esc back'
  if (view === VIEW.SETUP) return 'h/l choose · enter confirm · esc not now'
  if (panelMode === PANEL.AI) return askStatusText({ status, errorMessage, agent, selecting, link, session, stopKey, retryKey, canRetry })

  switch (status) {
    case 'loading':
      return 'Searching…'
    case 'error':
      return errorMessage
    case 'empty':
      return `No results for “${query}”`
    case 'ok':
      if (loadingPage) return `page ${page + 1} · loading…`
      // A failed page is not the end: its continuation is kept for a retry.
      if (pageError) return `page ${page} · ${count} results · page failed · ${nextPageKey || 'l'} retries`
      if (errorMessage) return errorMessage
      return `page ${page} · ${count} results${hasNext ? '' : ' · end'} · h/l pages`
    default:
      // The empty panel is where a first-timer looks, so it names the settings key.
      return 'enter searches · esc normal · ctrl+s settings'
  }
}

/**
 * The AI half's status line. Where the reader is in the ring leads, when there
 * is one. Kept short on purpose: the strip shows the conversations and KEYS.md
 * has the rest, so a line that elides teaches nothing.
 */
function askStatusText ({ status, errorMessage, agent, selecting, link, session, stopKey, retryKey, canRetry }) {
  const where = session ? session + ' · ' : ''
  const retry = canRetry && retryKey ? ` · ${retryKey} retries` : ''
  switch (status) {
    case 'thinking':
      return where + (agent ? `asking ${agent}…` : 'asking…') + (stopKey ? ` · ${stopKey} stops` : '')
    case 'error':
      return errorMessage + retry
    case 'stopped':
      return where + 'stopped' + retry
    case 'ok':
      if (selecting && link) return `gx opens ${hostOf(link)} · y yank · p to ask · esc drops`
      if (selecting) return 'enter hands off · y yank · p to ask · esc drops'
      if (link) return `gx opens ${hostOf(link)} · v select · yy yank`
      return where + 'v select · yy yank · enter hands off · ctrl+n next'
    default:
      // An interrupted question — the shell restarted under it — still retries.
      if (canRetry) return where + 'not answered' + retry
      return where + 'enter asks · tab search · ctrl+s settings'
  }
}

/**
 * The line a destructive key shows while it waits for its second press. The key
 * is rebindable, so it names itself.
 */
export function confirmClearText (keyText, count) {
  const what = count === 1 ? 'the saved conversation' : `all ${count} conversations`
  return `${keyText} again to forget ${what} · anything else cancels`
}

/** Left-hand side of the status strip: the view, or the vim mode inside it. */
export function modeLabel ({ view = VIEW.SEARCH, panelMode = PANEL.SEARCH, focusArea, mode, selecting = false }) {
  if (view === VIEW.SETTINGS) return 'SETTINGS'
  if (view === VIEW.SETUP) return 'SETUP'
  if (panelMode === PANEL.AI) {
    if (focusArea === FOCUS.RESULTS) return selecting ? 'AI · VISUAL' : 'AI · ANSWER'
    return 'AI · ' + String(mode).toUpperCase()
  }
  return focusArea === FOCUS.RESULTS ? 'RESULTS' : String(mode).toUpperCase()
}

/**
 * What y and Y put on the clipboard: the bare URL, or the title above it — a
 * citation to paste somewhere that wants both.
 */
export function resultYankText (row, withTitle = false) {
  if (!row) return ''
  const normalized = normalizeRow(row)
  if (!normalized.url) return ''
  if (!withTitle || !normalized.title) return normalized.url
  return normalized.title + '\n' + normalized.url
}

/** What the status line says for a beat after a yank, so it is clear which ran. */
export function yankNotice (withTitle) {
  return withTitle ? 'yanked the title and URL' : 'yanked the URL'
}

/**
 * URLs for an editable agent draft: the selected result, or every result on the
 * page one per line. The draft is editable, so the reader types the question
 * around the links; a title and a snippet in front of them only get in the way.
 */
export function handoffText (rows, index = -1) {
  const selected = index >= 0 ? rows.slice(index, index + 1) : rows
  const urls = []
  for (let i = 0; i < selected.length; i++) {
    const row = selected[i]
    if (row && row.url) urls.push(row.url)
  }
  return urls.join('\n')
}
