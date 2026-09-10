import test from 'node:test'
import assert from 'node:assert/strict'
import { LIST_KEYS, ANSWER_KEYS, resolve } from '../src/lib/keys.mjs'

test('a bound chord is its command', () => {
  assert.deepEqual(resolve(LIST_KEYS, '', 'j'), { command: 'down', pending: '' })
  assert.deepEqual(resolve(LIST_KEYS, '', 'Down'), { command: 'down', pending: '' })
  assert.deepEqual(resolve(LIST_KEYS, '', 'C-d'), { command: 'halfPageDown', pending: '' })
})

test('g waits for the second half, and gg is the top', () => {
  const first = resolve(LIST_KEYS, '', 'g')
  assert.deepEqual(first, { command: '', pending: 'g' })
  assert.deepEqual(resolve(LIST_KEYS, first.pending, 'g'), { command: 'top', pending: '' })
})

test('a sequence that goes nowhere is dropped, not left pending', () => {
  assert.deepEqual(resolve(LIST_KEYS, 'g', 'x'), { command: '', pending: '' })
  // gv reselects in the answer view; the list has no selection to restore.
  assert.deepEqual(resolve(LIST_KEYS, 'g', 'v'), { command: '', pending: '' })
  assert.deepEqual(resolve(ANSWER_KEYS, 'g', 'v'), { command: 'reselect', pending: '' })
})

test('a modifier on its own leaves the pending sequence alone', () => {
  // Reaching for shift halfway through a sequence must not cancel it.
  assert.deepEqual(resolve(ANSWER_KEYS, 'g', ''), { command: '', pending: 'g' })
  assert.deepEqual(resolve(ANSWER_KEYS, '', ''), { command: '', pending: '' })
})

test('an unbound key clears whatever was pending', () => {
  assert.deepEqual(resolve(ANSWER_KEYS, '', 'q'), { command: '', pending: '' })
})

test('both panes agree on the keys they share', () => {
  for (const chord of Object.keys(LIST_KEYS)) {
    assert.equal(ANSWER_KEYS[chord], LIST_KEYS[chord], `${chord} means two things`)
  }
})

test('the answer view adds motions and a selection', () => {
  assert.equal(resolve(ANSWER_KEYS, '', 'w').command, 'wordForward')
  assert.equal(resolve(ANSWER_KEYS, '', 'W').command, 'wordForwardBig')
  assert.equal(resolve(ANSWER_KEYS, '', '$').command, 'lineEnd')
  assert.equal(resolve(ANSWER_KEYS, '', 'V').command, 'selectLines')
  assert.equal(resolve(ANSWER_KEYS, '', 'y').command, 'yank')
  // The list has none of them, so its keys stay free for later.
  assert.equal(resolve(LIST_KEYS, '', 'w').command, '')
})

test('escape and enter are named keys, not their control characters', () => {
  assert.equal(resolve(LIST_KEYS, '', 'Escape').command, 'cancel')
  assert.equal(resolve(LIST_KEYS, '', 'Return').command, 'accept')
  assert.equal(resolve(LIST_KEYS, '', '\r').command, '')
})

test('the answer view can start a new conversation, the list has no session to end', () => {
  assert.equal(resolve(ANSWER_KEYS, '', 'C-n').command, 'newSession')
  assert.equal(resolve(LIST_KEYS, '', 'C-n').command, '')
})
