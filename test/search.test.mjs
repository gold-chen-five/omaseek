import { test } from 'node:test'
import assert from 'node:assert/strict'
import { describeError, normalizeRow, mergeResults, statusText, modeLabel } from '../src/lib/search.mjs'

test('known backend errors get a human message', () => {
  assert.equal(describeError({ error: 'network' }), 'No network connection')
  assert.match(describeError({ error: 'blocked' }), /declined the request/)
})

test('an unknown error falls back to the backend message, then a default', () => {
  assert.equal(describeError({ error: 'weird', message: 'boom' }), 'boom')
  assert.equal(describeError({}), 'Search failed')
  assert.equal(describeError(), 'Search failed')
})

test('rows are normalized to the delegate shape', () => {
  const row = normalizeRow({ title: 'T', url: 'https://x', display_url: 'x', icon: 'i' })
  assert.deepEqual(row, { title: 'T', url: 'https://x', snippet: '', display_url: 'x', icon: 'i' })
})

test('a missing row yields empty strings, never undefined', () => {
  assert.deepEqual(normalizeRow(), { title: '', url: '', snippet: '', display_url: '', icon: '' })
})

test('merging a page drops rows already on screen', () => {
  const existing = ['https://a', 'https://b']
  const added = mergeResults(existing, [
    { url: 'https://b', title: 'dupe' },
    { url: 'https://c', title: 'new' }
  ])
  assert.equal(added.length, 1)
  assert.equal(added[0].url, 'https://c')
})

test('merging de-duplicates within the incoming page too', () => {
  const added = mergeResults([], [
    { url: 'https://a', title: 'one' },
    { url: 'https://a', title: 'one again' }
  ])
  assert.equal(added.length, 1)
})

test('rows without a url are dropped', () => {
  assert.equal(mergeResults([], [{ title: 'no url' }]).length, 0)
})

test('a page of pure duplicates adds nothing', () => {
  const added = mergeResults(['https://a'], [{ url: 'https://a' }])
  assert.deepEqual(added, [], 'the panel uses this to skip ahead a page')
})

test('status line reflects each state', () => {
  assert.equal(statusText({ status: 'loading' }), 'Searching…')
  assert.equal(statusText({ status: 'error', errorMessage: 'nope' }), 'nope')
  assert.match(statusText({ status: 'empty', query: 'zz' }), /No results for “zz”/)
  assert.match(statusText({ status: 'idle' }), /enter searches/)
})

test('status line marks the end of pagination', () => {
  assert.match(statusText({ status: 'ok', count: 26, hasMore: false }), /26 results · end/)
  assert.match(statusText({ status: 'ok', count: 10, hasMore: true }), /^10 results · j\/k/)
})

test('loading more takes precedence over the result count line', () => {
  assert.equal(statusText({ status: 'ok', count: 10, loadingMore: true }), '10 results · loading more…')
})

test('mode label follows focus, not just the editor mode', () => {
  assert.equal(modeLabel({ focusArea: 'results', mode: 'normal' }), 'RESULTS')
  assert.equal(modeLabel({ focusArea: 'search', mode: 'insert' }), 'INSERT')
})
