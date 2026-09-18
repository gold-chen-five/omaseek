// The queries that were searched before: a ring of the last twenty-five, newest
// first, and the rules for recording one and walking back through them. Pure and
// under test; the file itself is read and written by search/HistoryStore.qml.
//
// The shape of sessions.mjs, with one difference that matters: walking does not
// wrap. Past the oldest it stops, and past the newest it lands back on the draft
// the reader had typed — readline's behaviour, and wrapping would lose that draft.

import { asText, listUnder } from '../shared/json.mjs'

export const MAX_QUERIES = 25

function oneLine (value) {
  return asText(value).replace(/\s+/g, ' ').trim()
}

/** File text -> the queries it holds; anything unreadable is no queries. */
export function readQueries (source) {
  const list = listUnder(source, 'queries')
  const queries = []
  const seen = {}
  for (let i = 0; i < list.length && queries.length < MAX_QUERIES; i++) {
    const entry = list[i]
    const text = oneLine(entry && typeof entry === 'object' ? entry.text : entry)
    if (!text) continue                        // a blank query is not one
    if (seen[' ' + text]) continue             // the space keeps __proto__ out of the way
    seen[' ' + text] = true
    queries.push({
      text: text,
      updated: entry && typeof entry.updated === 'number' ? entry.updated : 0
    })
  }
  return queries
}

/** The queries -> the file's text. */
export function writeQueries (queries) {
  const list = queries && Array.isArray(queries) ? queries.slice(0, MAX_QUERIES) : []
  return JSON.stringify({ version: 1, queries: list }, null, 2) + '\n'
}

/**
 * A query recorded at the front. Searching the same thing again promotes it
 * rather than filling the ring with one query, and past twenty-five the oldest
 * drops. A blank query records nothing.
 */
export function rememberQuery (queries, raw, now) {
  const kept = queries && Array.isArray(queries) ? queries.slice(0) : []
  const text = oneLine(raw)
  if (!text) return kept
  const rest = []
  for (let i = 0; i < kept.length; i++) if (kept[i].text !== text) rest.push(kept[i])
  rest.unshift({ text: text, updated: typeof now === 'number' ? now : 0 })
  if (rest.length > MAX_QUERIES) rest.length = MAX_QUERIES
  return rest
}

/**
 * Where a walk lands from `index`, and the text to show there. `index` is -1 for
 * the draft the reader had typed, 0 for the newest query. `delta` is +1 for one
 * step older and -1 for one step newer. Both ends stop rather than wrap, so an
 * unchanged index means the walk had nowhere to go — which is how the field
 * knows a Down at the draft should step into the results instead.
 */
export function stepQuery (queries, index, delta, draft) {
  const list = queries && Array.isArray(queries) ? queries : []
  const text = asText(draft)
  if (list.length === 0) return { index: -1, text: text }
  const at = index < -1 || index >= list.length ? -1 : index
  const next = Math.max(-1, Math.min(list.length - 1, at + (delta < 0 ? -1 : 1)))
  return { index: next, text: next === -1 ? text : list[next].text }
}
