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

test('the same page under different canonical urls collapses', () => {
  const added = mergeResults([], [
    { url: 'https://doc.rust-lang.org/book/ch04.html', title: 'What is Ownership?', display_url: 'doc.rust-lang.org' },
    { url: 'https://doc.rust-lang.org/stable/book/ch04.html', title: 'What is Ownership?', display_url: 'doc.rust-lang.org' }
  ])
  assert.equal(added.length, 1, 'Exa returns /book/ and /stable/book/ as separate hits')
})

test('the same title on a different domain is kept', () => {
  const added = mergeResults([], [
    { url: 'https://a.com/x', title: 'Ownership', display_url: 'a.com' },
    { url: 'https://b.com/x', title: 'Ownership', display_url: 'b.com' }
  ])
  assert.equal(added.length, 2)
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

test('a rejected Exa key gets a human message', () => {
  assert.equal(describeError({ error: 'auth' }), 'Exa rejected the API key')
})

test('results served by the fallback say so', () => {
  const line = statusText({ status: 'ok', count: 10, page: 1, hasNext: true, backend: 'exa' })
  assert.match(line, /· via Exa/)
})

test('the default backend is not called out', () => {
  const line = statusText({ status: 'ok', count: 10, page: 1, hasNext: true, backend: 'duckduckgo' })
  assert.doesNotMatch(line, /via/)
})

test('status line names the current page', () => {
  assert.match(statusText({ status: 'ok', count: 10, page: 2, hasNext: true }), /^page 2 · 10 results · h\/l pages/)
})

test('status line marks the last page', () => {
  assert.match(statusText({ status: 'ok', count: 6, page: 3, hasNext: false }), /page 3 · 6 results · end/)
  assert.doesNotMatch(statusText({ status: 'ok', count: 10, page: 1, hasNext: true }), / · end/)
})

test('fetching the next page announces the page being fetched', () => {
  assert.equal(statusText({ status: 'ok', count: 10, page: 2, loadingPage: true }), 'page 3 · loading…')
})

test('mode label follows focus, not just the editor mode', () => {
  assert.equal(modeLabel({ focusArea: 'results', mode: 'normal' }), 'RESULTS')
  assert.equal(modeLabel({ focusArea: 'search', mode: 'insert' }), 'INSERT')
})
