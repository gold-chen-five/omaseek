import test from 'node:test'
import assert from 'node:assert/strict'
import { lineDown, lineUp, lineBounds, lineRange, findInLine } from '../src/lib/motions.mjs'

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

test('lineBounds is the line holding the position, without its break', () => {
  assert.deepEqual(lineBounds(text, 0), { start: 0, end: 10 })
  assert.deepEqual(lineBounds(text, 10), { start: 0, end: 10 })   // on the break itself
  assert.deepEqual(lineBounds(text, 12), { start: 11, end: 13 })
  assert.deepEqual(lineBounds(text, 20), { start: 14, end: 24 })
})

test('findInLine stays on its line', () => {
  assert.equal(findInLine(text, 0, 'f', 'a'), -1)              // the a on the next line is out of reach
  assert.equal(findInLine(text, 0, 'f', 'i'), 1)
  assert.equal(findInLine(text, 15, 'F', 'i'), -1)
  assert.equal(findInLine(text, 20, 'F', 'i'), 16)
})

test('findInLine counts, and t lands beside', () => {
  const line = 'a,b,c,d'
  assert.equal(findInLine(line, 0, 'f', ',', 2), 3)
  assert.equal(findInLine(line, 0, 't', ',', 3), 4)
  assert.equal(findInLine(line, 6, 'T', ','), 6)
  assert.equal(findInLine(line, 0, 'f', ',', 9), -1)
})

test('a repeated t looks past the character it is already beside', () => {
  const line = 'a,b,c'
  assert.equal(findInLine(line, 0, 't', ','), 0)
  assert.equal(findInLine(line, 0, 't', ',', 1, true), 2)
  assert.equal(findInLine(line, 4, 'T', ',', 1, true), 2)
})


test('line operators stop at line boundaries, including empty and final lines', () => {
  assert.deepEqual(lineRange('one\ntwo\nthree', 5), { start: 4, end: 8 })
  assert.deepEqual(lineRange('one\ntwo\nthree', 5, 2), { start: 4, end: 13 })
  assert.deepEqual(lineRange('one\n\nthree', 4), { start: 4, end: 5 })
  assert.deepEqual(lineRange('one\ntwo', 5), { start: 4, end: 7 })
  assert.deepEqual(lineRange('one\n', 4), { start: 4, end: 4 })
  assert.deepEqual(lineRange('', 0), { start: 0, end: 0 })
})
