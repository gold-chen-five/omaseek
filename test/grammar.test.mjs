import test from 'node:test'
import assert from 'node:assert/strict'
import { IDLE, feed, trimExclusive } from '../src/vim/grammar.mjs'
import { ANSWER_KEYS } from '../src/vim/keys.mjs'

// Types a run of chords and returns the last action and the state left behind.
const type = (chords, visual = false, activeFind = null) => {
  let state = IDLE
  let action = null
  for (const chord of chords) {
    const step = feed(state, chord, ANSWER_KEYS, visual, activeFind)
    state = step.state
    action = step.action
  }
  return { state, action }
}

test('a count repeats the motion that follows it', () => {
  assert.deepEqual(type(['3', 'w']).action, { type: 'command', command: 'wordForward', count: 3, operator: '' })
  assert.equal(type(['1', '0', 'j']).action.count, 10)
})

test('0 is the line start unless it continues a count', () => {
  assert.equal(type(['0']).action.command, 'lineStart')
})

test('y waits for its motion, and counts on both sides multiply', () => {
  assert.equal(type(['y']).action, null)
  assert.equal(type(['y']).state.operator, 'y')
  assert.deepEqual(type(['2', 'y', '3', 'w']).action, { type: 'command', command: 'wordForward', count: 6, operator: 'y' })
  assert.equal(type(['y', '$']).action.command, 'lineEnd')
})

test('yy carries a line count to the view', () => {
  assert.deepEqual(type(['y', 'y']).action, { type: 'line', operator: 'y', count: 1 })
  assert.deepEqual(type(['2', 'y', '3', 'y']).action, { type: 'line', operator: 'y', count: 6 })
})

test('yiw and ya( name a text object', () => {
  assert.deepEqual(type(['y', 'i', 'w']).action, { type: 'object', scope: 'i', object: 'w', operator: 'y' })
  assert.deepEqual(type(['y', 'a', '(']).action, { type: 'object', scope: 'a', object: '(', operator: 'y' })
})

test('in visual mode i and a start objects; outside it, they enter the field', () => {
  assert.deepEqual(type(['i', 'w'], true).action, { type: 'object', scope: 'i', object: 'w', operator: '' })
  assert.deepEqual(type(['a', '('], true).action, { type: 'object', scope: 'a', object: '(', operator: '' })
  assert.equal(type(['i']).action.command, 'insert')
  assert.equal(type(['a']).action.command, 'append')
})

test('y in visual mode yanks the selection at once', () => {
  assert.equal(type(['y'], true).action.command, 'yank')
})

test('f and t take the next key as their character', () => {
  assert.deepEqual(type(['f', 'x']).action, { type: 'find', command: 'f', char: 'x', count: 1, operator: '' })
  assert.deepEqual(type(['2', 'T', ' ']).action, { type: 'find', command: 'T', char: ' ', count: 2, operator: '' })
  assert.equal(type(['y', 't', ')']).action.operator, 'y')
  assert.equal(type(['f', '3']).action.char, '3')
})

test('; repeats the last find and , reverses it', () => {
  assert.equal(type([';']).action.reverse, false)
  assert.equal(type([',']).action.reverse, true)
})

test('f and F repeat an active character find without another target', () => {
  const active = { command: 'f', char: 'a' }
  assert.deepEqual(type(['f'], false, active).action,
    { type: 'repeatFind', command: 'f', count: 1, operator: '' })
  assert.deepEqual(type(['3', 'F'], false, active).action,
    { type: 'repeatFind', command: 'F', count: 3, operator: '' })
  assert.equal(type(['t'], false, active).action, null, 'a different find kind still waits for its target')
  assert.equal(type(['y', 'f'], false, active).action, null, 'an operator starts a fresh find')
})

test('g sequences still work, under an operator too', () => {
  assert.equal(type(['g', 'g']).action.command, 'top')
  assert.equal(type(['y', 'g', 'g']).action.operator, 'y')
  assert.equal(type(['g', 'x']).action.command, 'openLink')
})

test('esc drops a half-typed sequence, and only then means cancel', () => {
  for (const run of [['y', 'Escape'], ['3', 'Escape'], ['f', 'Escape'], ['y', 'i', 'Escape'], ['g', 'Escape']]) {
    const { state, action } = type(run)
    assert.equal(action, null, run.join(' '))
    assert.deepEqual(state, IDLE, run.join(' '))
  }
  assert.equal(type(['Escape']).action.command, 'cancel')
  assert.equal(type(['Escape'], false, { command: 'f', char: 'a' }).action, null,
    'the first esc ends an active clever-f without leaving normal mode')
})

test('a bare modifier keeps what is pending', () => {
  assert.equal(type(['y', 'i', '']).state.scope, 'i')
})

test('p and P put', () => {
  assert.equal(type(['p']).action.command, 'put')
  assert.equal(type(['P']).action.command, 'putBefore')
})

test('an exclusive motion ending at a line start stops before the break', () => {
  assert.equal(trimExclusive('foo\nbar', 0, 4), 3)
  assert.equal(trimExclusive('foo bar', 0, 4), 4)
  assert.equal(trimExclusive('\n', 0, 1), 0)
})
