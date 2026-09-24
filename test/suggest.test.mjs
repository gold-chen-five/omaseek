import test from 'node:test'
import assert from 'node:assert/strict'
import { suggestionRows, stepSuggestion, readSuggestions, suggestionMarkup, MAX_ROWS, MAX_PAST } from '../src/search/suggest.mjs'

const past = [{ text: 'youtube music' }, { text: 'rust async' }, { text: 'You Know' }]

test('past searches that begin with the typed text lead, then SearXNG’s', () => {
  const rows = suggestionRows('you', past, ['youtube', 'youtube music', 'youbike'], 'you')
  assert.deepEqual(rows, [
    { text: 'youtube music', past: true },
    { text: 'You Know', past: true },
    { text: 'youtube', past: false },
    { text: 'youbike', past: false }
  ], 'a suggestion already among the past searches is listed once, as past')
})

test('nothing typed lists nothing, and the typed text is never offered back', () => {
  assert.deepEqual(suggestionRows('', past, ['youtube'], ''), [])
  assert.deepEqual(suggestionRows('  ', past, ['youtube'], '  '), [])
  assert.deepEqual(suggestionRows('youtube', [], ['YouTube', 'youtube kids'], 'youtube'),
    [{ text: 'youtube kids', past: false }], 'the same words in another case are the typed text')
})

test('the list is capped, and past searches take no more than their share', () => {
  const many = Array.from({ length: 20 }, (_, i) => 'you ' + i)
  const history = Array.from({ length: 10 }, (_, i) => ({ text: 'you past ' + i }))
  const rows = suggestionRows('you', history, many, 'you')
  assert.equal(rows.length, MAX_ROWS)
  assert.equal(rows.filter(row => row.past).length, MAX_PAST)
})

test('while the next answer is on its way, older suggestions narrow instead of vanishing', () => {
  const rows = suggestionRows('yout', [], ['youtube', 'youbike', 'you are'], 'you')
  assert.deepEqual(rows.map(row => row.text), ['youtube'])
  const fresh = suggestionRows('yout', [], ['youtube', 'yout spelled oddly'], 'yout')
  assert.equal(fresh.length, 2, 'an answer for exactly this is taken whole')
})

test('the arrows walk the rows and come back to what was typed, as Google’s do', () => {
  assert.equal(stepSuggestion(-1, 3, 1), 0, '↓ from the bar: the first row')
  assert.equal(stepSuggestion(2, 3, 1), -1, '↓ past the last: back to what was typed')
  assert.equal(stepSuggestion(-1, 3, -1), 2, '↑ from the bar: the last row')
  assert.equal(stepSuggestion(0, 3, -1), -1)
  assert.equal(stepSuggestion(5, 3, 1), 0, 'an index from a longer list starts over')
  assert.equal(stepSuggestion(-1, 0, 1), -1, 'no rows, nowhere to go')
})

test('an answer is read defensively', () => {
  assert.deepEqual(readSuggestions({ ok: true, suggestions: ['a', '', 3, 'b'] }), ['a', 'b'])
  assert.equal(readSuggestions({ ok: false }), null)
  assert.equal(readSuggestions(null), null)
})

test('what a row adds to the typed text is bold, and nothing in it is markup', () => {
  assert.equal(suggestionMarkup('youtube music', 'you'), 'you<b>tube music</b>')
  assert.equal(suggestionMarkup('YouTube', 'you'), 'You<b>Tube</b>', 'the row keeps its own case')
  assert.equal(suggestionMarkup('rust async', 'rust  asy'), 'rust asy<b>nc</b>', 'spaces typed twice are one')
  assert.equal(suggestionMarkup('youtube', 'yuotube'), '<b>youtube</b>', 'a spelling fixed is all new')
  assert.equal(suggestionMarkup('a<b>&c', 'a'), 'a<b>&lt;b&gt;&amp;c</b>')
})
