import { test } from 'node:test'
import assert from 'node:assert/strict'
import { pageWindow } from '../src/lib/pager.mjs'

test('every page shows while they fit in the row', () => {
  assert.deepEqual(pageWindow(0, 1), { start: 0, end: 1 })
  assert.deepEqual(pageWindow(3, 4), { start: 0, end: 4 })
  assert.deepEqual(pageWindow(9, 10), { start: 0, end: 10 })
})

test('past a rowful the window follows the page being read', () => {
  assert.deepEqual(pageWindow(0, 18), { start: 0, end: 10 }, 'the first pages stay put')
  assert.deepEqual(pageWindow(4, 18), { start: 0, end: 10 })
  assert.deepEqual(pageWindow(8, 18), { start: 3, end: 13 }, 'the current page sits mid-row')
  assert.deepEqual(pageWindow(17, 18), { start: 8, end: 18 }, 'the last page fills the row to the end')
})

test('nonsense cannot draw a broken row', () => {
  assert.deepEqual(pageWindow(0, 0), { start: 0, end: 0 })
  assert.deepEqual(pageWindow(-5, 12), { start: 0, end: 10 })
  assert.deepEqual(pageWindow(99, 12), { start: 2, end: 12 })
  assert.deepEqual(pageWindow(3, 12, 0), { start: 3, end: 4 })
})
