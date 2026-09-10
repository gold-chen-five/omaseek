// Search-result bookkeeping: normalising backend rows, merging pages, and
// turning state into the strings the status line shows.
//
// Pure functions only, so the paging and de-duplication rules can be tested
// under node rather than by clicking through a live search.

const ERROR_MESSAGES = {
  network: 'No network connection'
}

/**
 * Backend failure payload -> one line a person can act on.
 *
 * The backend's own message wins wherever it has one: it names the instance,
 * the port, or the exact settings.yml key to change, all of which a generic
 * line would throw away.
 */
export function describeError ({ error, message } = {}) {
  return message ?? ERROR_MESSAGES[error] ?? 'Search failed'
}

/** Backend row -> the exact shape the ListModel delegate expects. */
export function normalizeRow ({ title, url, snippet, display_url: displayUrl, icon } = {}) {
  return {
    title: title ?? '',
    url: url ?? '',
    snippet: snippet ?? '',
    display_url: displayUrl ?? '',
    icon: icon ?? ''
  }
}

/** Same page, different URL — /book/ and /stable/book/, http and https, ?utm=. */
function identity (row) {
  return `${row.display_url}|${row.title.toLowerCase()}`
}

/**
 * Merges a freshly fetched page into rows already on screen.
 *
 * Rows are de-duplicated twice over: on URL, because engines repeat hits
 * either side of a page boundary, and on domain+title, because engines return
 * the same document under several canonical paths and a URL comparison never
 * catches those.
 *
 * Returns the additions rather than a whole new list: the caller appends to a
 * live ListModel and needs to know whether the page advanced anything.
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

/**
 * Right-hand side of the status strip.
 *
 * Results are paged rather than scrolled, so this always names the page the
 * cursor is on and whether another one exists.
 */
export function statusText ({
  view = 'search', status, count = 0, query = '', page = 1,
  hasNext = false, loadingPage = false, errorMessage = '', backend = ''
} = {}) {
  // The other two views have no search state to report, only their keys.
  if (view === 'settings') return 'j/k rows · h/l change · enter press · saved as you go · esc back'
  if (view === 'setup') return 'h/l choose · enter confirm · esc not now'

  switch (status) {
    case 'loading':
      return 'Searching…'
    case 'error':
      return errorMessage
    case 'empty':
      return `No results for “${query}”`
    case 'ok':
      if (loadingPage) return `page ${page + 1} · loading…`
      if (errorMessage) return errorMessage
      return `page ${page} · ${count} results${hasNext ? '' : ' · end'} · h/l pages`
    default:
      // The empty panel is the only place a first-timer looks, so this is
      // where the settings key has to be named.
      return 'enter searches · esc normal · ctrl+s settings'
  }
}

/** Left-hand side of the status strip: the view, or the vim mode inside it. */
export function modeLabel ({ view = 'search', focusArea, mode }) {
  if (view === 'settings') return 'SETTINGS'
  if (view === 'setup') return 'SETUP'
  return focusArea === 'results' ? 'RESULTS' : String(mode).toUpperCase()
}
