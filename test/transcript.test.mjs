import test from 'node:test'
import assert from 'node:assert/strict'
import { replyIndexAt, replyEnd, cut } from '../src/lib/transcript.mjs'

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
