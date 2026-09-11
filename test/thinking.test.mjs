import test from 'node:test'
import assert from 'node:assert/strict'
import { FRAMES, FRAME_MS, elapsedText, thinkingLabel } from '../src/lib/thinking.mjs'

test('the clock reads like a clock', () => {
  assert.equal(elapsedText(0), '0s')
  assert.equal(elapsedText(7400), '7s')
  assert.equal(elapsedText(67000), '1m 07s')
  assert.equal(elapsedText(723000), '12m 03s')
  assert.equal(elapsedText(-5), '0s')
  assert.equal(elapsedText('junk'), '0s')
})

test('the frames are one dot sweeping across three, every frame the same width', () => {
  for (const frame of FRAMES) {
    assert.equal([...frame].length, 3, frame)
    assert.equal(frame.split('●').length - 1, 1, frame)
  }
})

test('the sweep is slow: well over a tenth of a second a frame', () => {
  assert.ok(FRAME_MS >= 200)
})

test('the label names who is working and for how long', () => {
  assert.equal(thinkingLabel('claude', 7400), 'claude is thinking · 7s')
  assert.equal(thinkingLabel('', 61000), 'the agent is thinking · 1m 01s')
})
