import { test } from 'node:test'
import assert from 'node:assert/strict'
import { snapToDevice } from '../src/shared/pixels.mjs'

test('a size snaps to whole device pixels at a fractional scale', () => {
  // 30 logical is 37.5 device pixels at 1.25: the bar whose bottom border drew two rows thick.
  const snapped = snapToDevice(30, 1.25)
  assert.equal(snapped * 1.25, Math.round(snapped * 1.25), 'a whole number of device pixels')
  assert.ok(Math.abs(snapped - 30) <= 0.4, 'and as near the asked size as a device pixel allows')
  assert.equal(snapToDevice(28, 1.25), 28, 'a size already whole is left alone')
  assert.equal(snapToDevice(30, 1), 30)
  assert.equal(snapToDevice(30, 2), 30)
  assert.equal(snapToDevice(30.3, 2), 30.5)
  assert.equal(snapToDevice(30, 0), 30, 'an unknown ratio is taken as 1')
})
