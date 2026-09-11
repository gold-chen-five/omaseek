import test from 'node:test'
import assert from 'node:assert/strict'
import { lineDown, lineUp } from '../src/lib/motions.mjs'

const text = 'first line\nab\nthird line'   // lines start at 0, 11, 14

test('down keeps the column, clamped to a shorter line', () => {
  assert.equal(lineDown(text, 1), 12)          // "i" -> "b"
  assert.equal(lineDown(text, 8), 13)          // past the end of "ab" -> its end
  assert.equal(lineDown(text, 12), 15)         // "b" -> "h"
})

test('up keeps the column the same way', () => {
  assert.equal(lineUp(text, 15), 12)
  assert.equal(lineUp(text, 20), 13)           // past the end of "ab" -> its end
  assert.equal(lineUp(text, 12), 1)
})

test('there is no line below the last, or above the first', () => {
  assert.equal(lineDown(text, 16), -1)
  assert.equal(lineDown('one line', 3), -1)
  assert.equal(lineUp(text, 3), -1)
  assert.equal(lineUp(text, 0), -1)
})

test('empty lines, and a text that starts with one', () => {
  assert.equal(lineDown('a\n\nb', 0), 2)
  assert.equal(lineDown('a\n\nb', 2), 3)
  assert.equal(lineUp('\nb', 1), 0)
  assert.equal(lineDown('\nb', 0), 1)
})
