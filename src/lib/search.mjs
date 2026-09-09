// Search-result bookkeeping: normalising backend rows, merging pages, and
// turning state into the strings the status line shows.
//
// Pure functions only, so the paging and de-duplication rules can be tested
// under node rather than by clicking through a live search.

const ERROR_MESSAGES = {
  network: 'No network connection',
  blocked: 'DuckDuckGo declined the request — try again shortly'
}

/** Backend failure payload -> one line a person can act on. */
export function describeError ({ error, message } = {}) {
  return ERROR_MESSAGES[error] ?? message ?? 'Search failed'
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

/**
 * Merges a freshly fetched page into rows already on screen.
 *
 * DuckDuckGo repeats a few hits either side of a page boundary, so rows are
 * de-duplicated on URL. Returns the additions rather than a whole new list:
 * the caller appends to a live ListModel and needs to know whether the page
 * actually advanced anything.
 */
export function mergeResults (existingUrls, incoming = []) {
  const seen = new Set(existingUrls)
  const added = []

  for (const row of incoming) {
    const normalized = normalizeRow(row)
    if (!normalized.url || seen.has(normalized.url)) continue
    seen.add(normalized.url)
    added.push(normalized)
  }
  return added
}

/** Right-hand side of the status strip. */
export function statusText ({ status, count = 0, query = '', hasMore = false, loadingMore = false, errorMessage = '' } = {}) {
  switch (status) {
    case 'loading':
      return 'Searching…'
    case 'error':
      return errorMessage
    case 'empty':
      return `No results for “${query}”`
    case 'ok':
      if (loadingMore) return `${count} results · loading more…`
      if (errorMessage) return errorMessage
      return `${count} results${hasMore ? '' : ' · end'} · j/k move · enter opens`
    default:
      return 'enter searches · esc for normal mode'
  }
}

/** Left-hand side of the status strip. */
export function modeLabel ({ focusArea, mode }) {
  return focusArea === 'results' ? 'RESULTS' : String(mode).toUpperCase()
}
