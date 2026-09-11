import test from 'node:test'
import assert from 'node:assert/strict'
import { VIEW, PANEL, FOCUS } from '../src/lib/states.mjs'
import { modeLabel, statusText } from '../src/lib/search.mjs'

test('the state tables cannot be changed from outside', () => {
  for (const table of [VIEW, PANEL, FOCUS]) {
    assert.ok(Object.isFrozen(table))
    assert.throws(() => { 'use strict'; table.EXTRA = 'x' })
  }
})

test('a misspelt state is undefined, which QML reports, not a string it would accept', () => {
  assert.equal(VIEW.SETINGS, undefined)
})

test('every view, in either panel mode, has a mode label and a status line', () => {
  for (const view of Object.values(VIEW)) {
    for (const panelMode of Object.values(PANEL)) {
      for (const focusArea of Object.values(FOCUS)) {
        const label = modeLabel({ view, panelMode, focusArea, mode: 'normal' })
        assert.equal(typeof label, 'string')
        assert.ok(label.length > 0, `${view}/${panelMode}/${focusArea} has no mode label`)
        assert.equal(typeof statusText({ view, panelMode, status: 'idle' }), 'string')
      }
    }
  }
})

test('the labels still say what they said when the states were bare strings', () => {
  assert.equal(modeLabel({ view: VIEW.SETTINGS }), 'SETTINGS')
  assert.equal(modeLabel({ view: VIEW.SETUP }), 'SETUP')
  assert.equal(modeLabel({ view: VIEW.SEARCH, panelMode: PANEL.AI, focusArea: FOCUS.RESULTS }), 'AI · ANSWER')
  assert.equal(modeLabel({ view: VIEW.SEARCH, panelMode: PANEL.SEARCH, focusArea: FOCUS.RESULTS }), 'RESULTS')
  assert.equal(modeLabel({ view: VIEW.SEARCH, panelMode: PANEL.SEARCH, focusArea: FOCUS.FIELD, mode: 'insert' }), 'INSERT')
})
