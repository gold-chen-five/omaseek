import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  MAX_QUERIES, readQueries, writeQueries, rememberQuery, stepQuery
} from '../src/lib/history.mjs'

function ring (count) {
  let queries = []
  for (let i = 0; i < count; i++) queries = rememberQuery(queries, 'query ' + i, 1000 + i)
  return queries
}

test('a query is recorded at the front, newest first', () => {
  const queries = rememberQuery(rememberQuery([], 'first', 10), 'second', 20)
  assert.deepEqual(queries.map(q => q.text), ['second', 'first'])
  assert.equal(queries[0].updated, 20)
})

test('searching the same thing again promotes it rather than repeating it', () => {
  let queries = ring(3)
  queries = rememberQuery(queries, 'query 0', 99)
  assert.deepEqual(queries.map(q => q.text), ['query 0', 'query 2', 'query 1'])
  assert.equal(queries[0].updated, 99)
})

test('the ring keeps twenty-five and drops the oldest', () => {
  const queries = ring(MAX_QUERIES + 4)
  assert.equal(queries.length, MAX_QUERIES)
  assert.equal(queries[0].text, 'query 28')
  assert.equal(queries[MAX_QUERIES - 1].text, 'query 4')
})

test('a blank query records nothing, and whitespace is folded', () => {
  assert.deepEqual(rememberQuery([], '   ', 10), [])
  assert.deepEqual(rememberQuery([], '\n\n', 10), [])
  assert.equal(rememberQuery([], '  two   words  ', 10)[0].text, 'two words')
})

test('the file round-trips', () => {
  const queries = ring(3)
  assert.deepEqual(readQueries(writeQueries(queries)), queries)
})

test('an unreadable file is no queries', () => {
  assert.deepEqual(readQueries(''), [])
  assert.deepEqual(readQueries('{'), [])
  assert.deepEqual(readQueries('null'), [])
  assert.deepEqual(readQueries('{"queries":"nope"}'), [])
  assert.deepEqual(readQueries(undefined), [])
})

test('reading drops blanks and duplicates and caps the list', () => {
  const source = JSON.stringify({
    queries: [{ text: 'a' }, { text: '  ' }, { text: 'a' }, { text: 'b', updated: 7 }, null]
  })
  assert.deepEqual(readQueries(source), [{ text: 'a', updated: 0 }, { text: 'b', updated: 7 }])
})

test('walking steps back through the queries and stops at the oldest', () => {
  const queries = ring(3)   // query 2, query 1, query 0
  const first = stepQuery(queries, -1, 1, 'draft')
  assert.deepEqual(first, { index: 0, text: 'query 2' })
  const second = stepQuery(queries, first.index, 1, 'draft')
  assert.deepEqual(second, { index: 1, text: 'query 1' })
  const third = stepQuery(queries, second.index, 1, 'draft')
  assert.deepEqual(third, { index: 2, text: 'query 0' })
  assert.deepEqual(stepQuery(queries, third.index, 1, 'draft'), third, 'the oldest stops')
})

test('walking back the other way lands on the draft and stays there', () => {
  const queries = ring(2)
  assert.deepEqual(stepQuery(queries, 1, -1, 'draft'), { index: 0, text: 'query 1' })
  assert.deepEqual(stepQuery(queries, 0, -1, 'draft'), { index: -1, text: 'draft' })
  assert.deepEqual(stepQuery(queries, -1, -1, 'draft'), { index: -1, text: 'draft' },
    'unchanged: the field steps into the results instead')
})

test('an empty ring leaves the draft alone', () => {
  assert.deepEqual(stepQuery([], -1, 1, 'draft'), { index: -1, text: 'draft' })
  assert.deepEqual(stepQuery(null, -1, -1, ''), { index: -1, text: '' })
})

test('an index the ring no longer holds is read as the draft', () => {
  const queries = ring(2)
  assert.deepEqual(stepQuery(queries, 9, 1, 'draft'), { index: 0, text: 'query 1' })
})
