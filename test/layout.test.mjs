import { test } from 'node:test'
import assert from 'node:assert/strict'
import { cardSize, readingWidth, CARD_WIDTH, CARD_WIDTH_TRANSLATING, CARD_HEIGHT } from '../src/panel/layout.mjs'
import { snapToDevice } from '../src/shared/pixels.mjs'

// Common laptop and desktop panels with the scales people run them at, as
// physical width × height @ scale. What the panel sees is the logical size.
const SCREENS = [
  [1280, 720, 1], [1280, 720, 1.25], [1366, 768, 1], [1366, 768, 1.25],
  [1280, 800, 1], [1280, 800, 1.25], [1280, 800, 1.5], [1440, 900, 1], [1440, 900, 1.25],
  [1600, 900, 1], [1920, 1080, 1], [1920, 1080, 1.25], [1920, 1080, 1.5],
  [1920, 1200, 1], [1920, 1200, 1.25], [1920, 1200, 1.5], [2256, 1504, 1.5], [2256, 1504, 2],
  [2560, 1440, 1], [2560, 1440, 1.25], [2560, 1440, 1.5], [2560, 1440, 2],
  [2560, 1600, 1.6], [2560, 1600, 2], [2880, 1800, 2], [3024, 1964, 2],
  [3440, 1440, 1], [3840, 2160, 1.5], [3840, 2160, 2]
]
const GAP = 5              // Style.gapsOut, Hyprland's gaps_out
const INSETS = 2 * 18 + 2  // the card's padding (panel-padding) and its border, both sides
const SPLIT_GAP = 6        // Style.spacing.md between the two panes

for (const [w, h, scale] of SCREENS) {
  const screenW = w / scale
  const screenH = h / scale
  test(`the card fits a ${w}×${h} screen at ${scale}×`, () => {
    for (const translating of [false, true]) {
      const card = cardSize(screenW, screenH, translating, GAP)
      // As Search.qml places it: the inside snapped to whole monitor pixels.
      const width = snapToDevice(card.width - INSETS, scale) + INSETS
      assert.ok(width <= screenW - GAP, `${translating ? 'translating, ' : ''}${width} wide on ${screenW}`)
      assert.ok(card.height <= screenH - GAP * 2, `${card.height} tall on ${screenH}`)
      if (!translating) continue
      const inner = width - INSETS
      const reading = readingWidth(inner, true)
      const translation = inner - reading - SPLIT_GAP
      assert.ok(reading >= 450, `results or answer keep room to read: ${reading}`)
      assert.ok(translation >= 250, `the translation keeps room for a line: ${translation}`)
    }
  })
}

test('a screen with room gets the sizes asked for, and a theme scale grows them', () => {
  assert.deepEqual(cardSize(1536, 864, false, GAP), { width: CARD_WIDTH, height: CARD_HEIGHT })
  assert.deepEqual(cardSize(1536, 864, true, GAP), { width: CARD_WIDTH_TRANSLATING, height: CARD_HEIGHT })
  const roomy = cardSize(3840, 2160, true, GAP, px => Math.round(px * 1.2))
  assert.equal(roomy.width, 1200)
  // and a scale too big for the screen still stops at its edge
  assert.equal(cardSize(1280, 720, true, GAP, px => px * 2).width, 1280 - GAP * 2)
})

test('the reading pane is all of the card, or its share beside a translation', () => {
  assert.equal(readingWidth(800, false), 800)
  assert.equal(readingWidth(1000, true), 600)
})
