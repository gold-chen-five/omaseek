import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  IDLE, openFind, feedFind, promptText, caseSensitive,
  matchPositions, matchFrom, nextMatch, matchingRows, markMatches, wordAt
} from '../src/shared/vim/find.mjs'

function type (state, text) {
  let current = state
  for (let i = 0; i < text.length; i++) current = feedFind(current, '', text[i]).state
  return current
}

test('the prompt collects what is typed and says so', () => {
  const state = type(openFind(false), 'rust')
  assert.equal(state.pattern, 'rust')
  assert.equal(promptText(state), '/rust')
  assert.equal(promptText(type(openFind(true), 'rust')), '?rust')
  assert.equal(promptText(IDLE), '')
})

test('enter accepts a pattern; escape and an empty enter drop it', () => {
  const state = type(openFind(false), 'rust')
  assert.deepEqual(feedFind(state, 'Return'), { state: IDLE, action: 'accept' })
  assert.deepEqual(feedFind(state, 'Escape'), { state: IDLE, action: 'cancel' })
  assert.deepEqual(feedFind(openFind(false), 'Return'), { state: IDLE, action: 'cancel' })
})

test('backspace erases, and past the start it closes the prompt', () => {
  const state = type(openFind(false), 'ru')
  const once = feedFind(state, 'Backspace')
  assert.equal(once.state.pattern, 'r')
  assert.equal(once.action, 'typing')
  const twice = feedFind(once.state, 'Backspace')
  assert.equal(twice.state.pattern, '')
  assert.deepEqual(feedFind(twice.state, 'Backspace'), { state: IDLE, action: 'cancel' })
})

test('control characters are not part of a pattern, and a closed prompt eats nothing', () => {
  const state = openFind(false)
  const control = String.fromCharCode(1)
  assert.deepEqual(feedFind(state, '', control), { state: state, action: '' })
  assert.deepEqual(feedFind(state, '', ''), { state: state, action: '' })
  assert.equal(feedFind(state, '', ' ').state.pattern, ' ', 'a space is typable')
  assert.deepEqual(feedFind(IDLE, '', 'r'), { state: IDLE, action: '' })
})

test('smartcase: lowercase matches either case, an uppercase pins it', () => {
  assert.equal(caseSensitive('rust'), false)
  assert.equal(caseSensitive('Rust'), true)
  assert.deepEqual(matchPositions('rust and Rust', 'rust'), [0, 9])
  assert.deepEqual(matchPositions('rust and Rust', 'Rust'), [9])
  assert.deepEqual(matchPositions('anything', ''), [])
})

test('a step lands on the next match and wraps around the text', () => {
  const at = matchPositions('a x b x c x', 'x')
  assert.deepEqual(at, [2, 6, 10])
  assert.equal(matchFrom(at, 0, false, false), 2)
  assert.equal(matchFrom(at, 2, false, false), 6, 'strictly after, so n moves off the one it is on')
  assert.equal(matchFrom(at, 10, false, false), 2, 'wraps to the first')
  assert.equal(matchFrom(at, 2, true, false), 10, 'backwards wraps to the last')
  assert.equal(matchFrom(at, 7, true, false), 6)
  assert.equal(matchFrom([], 0, false, false), -1)
})

test('the incremental jump counts a match under the cursor; n never does', () => {
  const at = matchPositions('rust', 'rust')
  assert.equal(matchFrom(at, 0, false, true), 0, 'typing shows the match where the reader is')
  assert.equal(matchFrom(at, 0, false, false), 0, 'one match: n wraps back to it')
})

test('a count repeats the step', () => {
  const at = matchPositions('x x x x', 'x')
  assert.equal(nextMatch(at, 0, false, 2), 4)
  assert.equal(nextMatch(at, 0, false, 3), 6)
  assert.equal(nextMatch(at, 0, false, 4), 0, 'all the way round')
  assert.equal(nextMatch(at, 6, true, 2), 2)
  assert.equal(nextMatch([], 0, false, 2), -1)
})

test('the result list matches a row on anything it shows', () => {
  const rows = [
    { title: 'The Rust Book', snippet: 'ownership', display_url: 'doc.rust-lang.org', url: 'https://doc.rust-lang.org/book/' },
    { title: 'Go by Example', snippet: 'goroutines', display_url: 'gobyexample.com', url: 'https://gobyexample.com/' },
    { title: 'Crates', snippet: 'the rust registry', display_url: 'crates.io', url: 'https://crates.io/' }
  ]
  assert.deepEqual(matchingRows(rows, 'rust'), [0, 2])
  assert.deepEqual(matchingRows(rows, 'goroutines'), [1])
  assert.deepEqual(matchingRows(rows, 'crates.io'), [2], 'the domain counts')
  assert.deepEqual(matchingRows(rows, 'nothing'), [])
  assert.deepEqual(matchingRows(rows, ''), [])
  assert.deepEqual(matchingRows(null, 'rust'), [])
})

test('matching rows step with the same walk text offsets use', () => {
  assert.equal(nextMatch([0, 2], 0, false, 1), 2)
  assert.equal(nextMatch([0, 2], 2, false, 1), 0, 'wraps to the first row')
  assert.equal(nextMatch([0, 2], 0, true, 1), 2, 'backwards wraps to the last')
  assert.equal(nextMatch([], 0, false, 1), -1)
})

test('a matched row marks the words it matched, in the text itself', () => {
  assert.equal(markMatches('The Rust Book', 'rust', '#7daea3'),
    'The <font color="#7daea3"><b>Rust</b></font> Book')
  // The cursor row is already painted in the accent, so there the weight alone marks it.
  assert.equal(markMatches('The Rust Book', 'rust', ''), 'The <b>Rust</b> Book')
  assert.equal(markMatches('rust and rust', 'rust', ''), '<b>rust</b> and <b>rust</b>')
})

test('marking escapes everything, matched or not', () => {
  // The string is read as markup from here on: a result titled with an
  // ampersand or a tag must not become one.
  assert.equal(markMatches('Tom & Jerry <b>', '', ''), 'Tom &amp; Jerry &lt;b&gt;')
  assert.equal(markMatches('Tom & Jerry', 'jerry', ''), 'Tom &amp; <b>Jerry</b>')
  assert.equal(markMatches('a <i> b', '<i>', ''), 'a <b>&lt;i&gt;</b> b')
  assert.equal(markMatches('"quoted"', 'quoted', ''), '&quot;<b>quoted</b>&quot;')
})

test('nothing to mark is just the escaped text', () => {
  assert.equal(markMatches('nothing here', 'zzz', '#fff'), 'nothing here')
  assert.equal(markMatches('nothing here', '', '#fff'), 'nothing here')
  assert.equal(markMatches(null, 'x', ''), '')
})

test('overlapping matches are marked once, not nested', () => {
  // matchPositions counts overlaps; marking must not reopen inside a mark.
  assert.equal(markMatches('aaaa', 'aa', ''), '<b>aa</b><b>aa</b>')
  assert.equal(markMatches('aaa', 'aa', ''), '<b>aa</b>a')
})

test('* takes the word under the cursor, or the next one along the line', () => {
  const text = 'rust is fast'
  assert.equal(wordAt(text, 0), 'rust')
  assert.equal(wordAt(text, 2), 'rust', 'from inside the word')
  assert.equal(wordAt(text, 3), 'rust', 'from its last character')
  // On a space, vim's * takes the next word rather than doing nothing.
  assert.equal(wordAt(text, 4), 'is')
  assert.equal(wordAt('snake_case2 x', 0), 'snake_case2', 'digits and underscores are word characters')
})

test('* looks no further than the end of its line', () => {
  assert.equal(wordAt('hi   ', 3), '', 'nothing left on this line')
  assert.equal(wordAt('hi ...\nnext', 3), '', 'a word on the next line is not under the cursor')
  assert.equal(wordAt('', 0), '')
  assert.equal(wordAt(null, 5), '')
  assert.equal(wordAt('hi', 99), '', 'past the end')
})

test('* will not match inside a longer word, which is what makes it different from /', () => {
  const text = 'rust and rusty and Rust and trust'
  assert.deepEqual(matchPositions(text, 'rust'), [0, 9, 19, 29], 'typed: every occurrence')
  assert.deepEqual(matchPositions(text, 'rust', true), [0, 19], 'starred: whole words only')
  // The ends of the text bound a word just as a space does.
  assert.deepEqual(matchPositions('rust', 'rust', true), [0])
  assert.deepEqual(matchPositions('arusta', 'rust', true), [])
  // Punctuation is not a word character, so it bounds one.
  assert.deepEqual(matchPositions('(rust)', 'rust', true), [1])
})
