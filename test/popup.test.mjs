import { test } from 'node:test'
import assert from 'node:assert/strict'
import { placePopup } from '../src/settings/popup.mjs'

// A 1536×864 logical screen (1920×1080 at 1.25), rows of 28, eight of them.
const screen = { windowHeight: 864, triggerHeight: 28, natural: 254, gap: 2, margin: 8, minimum: 28 }

test('a list with room below opens below at its full height', () => {
  assert.deepEqual(placePopup({ ...screen, triggerTop: 200 }), { y: 30, height: 254, above: false })
})

test('a list low on the screen opens above rather than running off the bottom', () => {
  const place = placePopup({ ...screen, triggerTop: 700 })
  assert.equal(place.above, true)
  assert.equal(place.height, 254)
  assert.equal(place.y, -256)
  assert.ok(700 + place.y >= screen.margin, 'its top is on screen')
})

test('with no side big enough it takes the roomier one and shrinks to fit, scrolling', () => {
  const place = placePopup({ ...screen, windowHeight: 300, triggerTop: 180 })
  assert.equal(place.above, true)
  assert.equal(place.height, 170)
  const bottomHeavy = placePopup({ ...screen, windowHeight: 300, triggerTop: 60 })
  assert.equal(bottomHeavy.above, false)
  assert.equal(60 + bottomHeavy.y + bottomHeavy.height, 300 - screen.margin, 'it ends at the margin')
})

test('a short list is never stretched, and a cramped one keeps a row', () => {
  assert.equal(placePopup({ ...screen, natural: 60, triggerTop: 800 }).height, 60)
  assert.equal(placePopup({ ...screen, windowHeight: 40, triggerTop: 6 }).height, 28)
})
