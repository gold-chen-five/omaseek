// The dropdown under the search bar, as Google's: what it lists for the words
// typed so far, and how the arrows walk it. Pure and under test; the store is
// search/Suggestions.qml and the list search/SuggestionList.qml.

import { escapeHtml } from '../shared/html.mjs'

export const MAX_ROWS = 8

// Past searches lead, as Google's clock rows do, but only a few: the list is
// for finding something new as much as for coming back.
export const MAX_PAST = 3

function key (text) {
  return String(text ?? '').replace(/\s+/g, ' ').trim().toLowerCase()
}

/**
 * The rows for `typed`: past queries that begin with it (`past: true`), then
 * SearXNG's suggestions, each once, never the typed text itself — nothing to
 * complete there. `remote` answered `remoteFor`; while the answer for what is
 * typed now is on its way, only those of the older ones that still begin with
 * it stay, so the list narrows as a letter is typed instead of flickering empty.
 */
export function suggestionRows (typed, past, remote, remoteFor) {
  const typedKey = key(typed)
  if (!typedKey) return []
  const rows = []
  const seen = {}
  seen[' ' + typedKey] = true
  const add = (text, isPast) => {
    const k = key(text)
    if (!k || seen[' ' + k]) return false
    seen[' ' + k] = true
    rows.push({ text: String(text).replace(/\s+/g, ' ').trim(), past: isPast })
    return true
  }
  const queries = Array.isArray(past) ? past : []
  let pastCount = 0
  for (let i = 0; i < queries.length && pastCount < MAX_PAST; i++) {
    const text = queries[i] && typeof queries[i] === 'object' ? queries[i].text : queries[i]
    if (key(text).indexOf(typedKey) === 0 && add(text, true)) pastCount++
  }
  const offered = Array.isArray(remote) ? remote : []
  const fresh = key(remoteFor) === typedKey
  for (let i = 0; i < offered.length && rows.length < MAX_ROWS; i++) {
    if (fresh || key(offered[i]).indexOf(typedKey) === 0) add(offered[i], false)
  }
  return rows
}

/**
 * Where ↓ (+1) or ↑ (-1) lands from `index` among `count` rows. -1 is the bar
 * with what was typed, as in Google: ↓ from there is the first row, ↓ past the
 * last comes back to it, and ↑ from it goes to the last.
 */
export function stepSuggestion (index, count, delta) {
  if (count <= 0) return -1
  const at = index < -1 || index >= count ? -1 : index
  const next = at + (delta < 0 ? -1 : 1)
  if (next >= count) return -1
  if (next < -1) return count - 1
  return next
}

/** bin/search --suggest's answer -> the suggestions, or null when it is not one. */
export function readSuggestions (payload) {
  if (!payload || payload.ok !== true || !Array.isArray(payload.suggestions)) return null
  const list = []
  for (let i = 0; i < payload.suggestions.length; i++) {
    if (typeof payload.suggestions[i] === 'string' && payload.suggestions[i].trim()) list.push(payload.suggestions[i])
  }
  return list
}

/**
 * A row as the list draws it: what was typed plain and the rest in bold, as
 * Google shows what it adds. A row that does not begin with the typed text —
 * a spelling fixed — is bold throughout, since all of it is new.
 */
export function suggestionMarkup (text, typed) {
  const row = String(text ?? '')
  const lead = String(typed ?? '').replace(/\s+/g, ' ').trim()
  if (lead && row.toLowerCase().indexOf(lead.toLowerCase()) === 0) {
    const rest = row.slice(lead.length)
    return escapeHtml(row.slice(0, lead.length)) + (rest ? '<b>' + escapeHtml(rest) + '</b>' : '')
  }
  return '<b>' + escapeHtml(row) + '</b>'
}
