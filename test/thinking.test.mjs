import test from 'node:test'
import assert from 'node:assert/strict'
import { FRAMES, VERBS, pickVerb, elapsedText, thinkingLine } from '../src/lib/thinking.mjs'

test('the clock reads like a clock', () => {
  assert.equal(elapsedText(0), '0s')
  assert.equal(elapsedText(7400), '7s')
  assert.equal(elapsedText(67000), '1m 07s')
  assert.equal(elapsedText(723000), '12m 03s')
  assert.equal(elapsedText(-5), '0s')
  assert.equal(elapsedText('junk'), '0s')
})

test('a verb is fixed for a seed and always one of the list', () => {
  assert.equal(pickVerb(3), pickVerb(3))
  assert.ok(VERBS.includes(pickVerb(123456789)))
  assert.ok(VERBS.includes(pickVerb('nonsense')))
})

test('the line cycles through the frames and carries the clock', () => {
  assert.equal(thinkingLine(0, 'Thinking', 3000), FRAMES[0] + ' Thinking… (3s)')
  assert.equal(thinkingLine(FRAMES.length, 'Thinking', 0), FRAMES[0] + ' Thinking… (0s)')
  assert.equal(thinkingLine(4, 'Brewing', 61000), FRAMES[4] + ' Brewing… (1m 01s)')
})
