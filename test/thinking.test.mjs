import test from 'node:test'
import assert from 'node:assert/strict'
import { PULSE_MS, CLOCK_MS, elapsedText, thinkingLabel } from '../src/core/thinking.mjs'

test('the clock reads like a clock', () => {
  assert.equal(elapsedText(0), '0s')
  assert.equal(elapsedText(7400), '7s')
  assert.equal(elapsedText(67000), '1m 07s')
  assert.equal(elapsedText(723000), '12m 03s')
  assert.equal(elapsedText(-5), '0s')
  assert.equal(elapsedText('junk'), '0s')
})

test('the dot breathes slowly, and the clock keeps up with the seconds', () => {
  assert.ok(PULSE_MS >= 1200)
  assert.ok(CLOCK_MS <= 1000)
})

test('the label names who is working and for how long', () => {
  assert.equal(thinkingLabel('claude', 7400), 'claude is thinking · 7s')
  assert.equal(thinkingLabel('', 61000), 'the agent is thinking · 1m 01s')
})
