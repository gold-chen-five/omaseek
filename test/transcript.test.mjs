import test from 'node:test'
import assert from 'node:assert/strict'
import { replyIndexAt, replyEnd, cut, exchangeText, conversationText } from '../src/lib/transcript.mjs'

const TURNS = [
  { role: 'user', text: 'rust site?' },
  { role: 'assistant', text: '- Official website: [rust-lang.org](https://www.rust-lang.org/)' },
  { role: 'user', text: 'and a book?' },
  { role: 'error', text: 'Codex: rate limit' },
  { role: 'user', text: 'a book, again' },
  { role: 'assistant', text: 'The Rust Programming Language.' }
]

test('a hand-off of one reply brings its question, as the agent wrote both', () => {
  assert.equal(exchangeText(TURNS, 1),
    'User: rust site?\n\nAssistant: - Official website: [rust-lang.org](https://www.rust-lang.org/)')
  assert.equal(exchangeText(TURNS, 5), 'User: a book, again\n\nAssistant: The Rust Programming Language.')
  assert.equal(exchangeText(TURNS, 9), '')
})

test('a hand-off of everything leaves failures and placeholder dots out', () => {
  const all = conversationText(TURNS)
  assert.ok(all.startsWith('User: rust site?\n\nAssistant: - Official'))
  assert.ok(!all.includes('rate limit'))
  assert.ok(!all.includes('●'))
  assert.equal(conversationText([]), '')
})

// "> q1\n● a1\n> q2\n● a2" — questions at 0 and 10, replies at 5 and 15.
const Q = [0, 10]
const R = [5, 15]

test('in a reply, that reply', () => {
  assert.equal(replyIndexAt(7, Q, R), 0)
  assert.equal(replyIndexAt(17, Q, R), 1)
})

test('on a question, the reply that answers it', () => {
  assert.equal(replyIndexAt(1, Q, R), 0)
  assert.equal(replyIndexAt(11, Q, R), 1)
})

test('on a question not yet answered, none', () => {
  assert.equal(replyIndexAt(21, [0, 10, 20], R), -1)
  assert.equal(replyIndexAt(0, [0], []), -1)
})

test('a reply ends where the next question, reply or placeholder begins', () => {
  assert.equal(replyEnd(0, Q, R, -1, 19), 10)
  assert.equal(replyEnd(1, Q, R, -1, 19), 19)
  assert.equal(replyEnd(1, [0, 10, 20], R, 23, 26), 20)
  assert.equal(replyEnd(0, [0], [5], 12, 14), 12)
})

test('copied text leaves the invisible marks out', () => {
  // "● hi\n> q" starting at 5, with the lead "● " at 5 and 6.
  assert.equal(cut('● hi\n> q', 5, [[5, 7]]), 'hi\n> q')
  assert.equal(cut('abcdef', 10, [[11, 12], [13, 15]]), 'acf')
  assert.equal(cut('abc', 0, []), 'abc')
})
