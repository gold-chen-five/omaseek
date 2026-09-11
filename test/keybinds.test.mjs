import test from 'node:test'
import assert from 'node:assert/strict'
import {
  ACTIONS, parseChord, parseSequence, chordText, parseBinding, normalizeBinding, actionById
} from '../src/lib/keybinds.mjs'

test('a binding is written the way a person says it', () => {
  assert.equal(parseChord('ctrl+c'), 'C-c')
  assert.equal(parseChord('Ctrl+S'), 'C-s', 'ctrl+letter is lowercase, as chord.js spells it')
  assert.equal(parseChord('enter'), 'Return')
  assert.equal(parseChord('ESC'), 'Escape', 'named keys ignore case')
  assert.equal(parseChord('ctrl+enter'), 'C-Return')
  assert.equal(parseChord('space'), ' ', 'chord.js spells space by its text')
  assert.equal(parseChord('alt+x'), null, 'only ctrl, for now')
  assert.equal(parseChord('abc'), null)
  assert.equal(parseChord(''), null)
})

test('letters keep their case, so G is not g and gA is not ga', () => {
  assert.equal(parseChord('G'), 'G')
  assert.equal(parseSequence('gA'), 'g A')
  assert.equal(parseSequence('ga'), 'g a')
  assert.notEqual(parseSequence('gA'), parseSequence('ga'))
})

test('two keys in turn can be written together or apart', () => {
  assert.equal(parseSequence('gx'), 'g x')
  assert.equal(parseSequence('g x'), 'g x')
  assert.equal(parseSequence('  g   x '), 'g x')
  assert.equal(parseSequence('g enter'), 'g Return')
  assert.equal(parseSequence('gxy'), null, 'three keys is one too many')
  assert.equal(parseSequence('g space'), null, 'a space would read as the separator')
})

test('a binding reads back the way it was written', () => {
  for (const text of ['ctrl+c', 'enter', 'gx', 'gA', 'G', 'tab', 'ctrl+enter', 'space', 'g enter']) {
    const sequence = text === 'space' ? parseChord(text) : parseSequence(text)
    assert.equal(chordText(sequence), text)
  }
})

test('keys caught before the field types must be named keys or ctrl chords', () => {
  const search = actionById('search')
  assert.equal(parseBinding(search, 'enter'), 'Return')
  assert.equal(parseBinding(search, 'ctrl+enter'), 'C-Return')
  assert.equal(parseBinding(search, 'x'), null, 'x could never be typed into a search')
  assert.equal(parseBinding(search, 'space'), null)
  assert.equal(parseBinding(search, 'gx'), null, 'the field has no sequences')
  assert.equal(normalizeBinding(actionById('settings'), 'Ctrl+O'), 'ctrl+o')
})

test('reader keys may be letters or two keys', () => {
  assert.equal(normalizeBinding(actionById('handoff'), 'g a'), 'ga')
  assert.equal(normalizeBinding(actionById('nextPage'), 'n'), 'n')
  assert.equal(normalizeBinding(actionById('handoff'), 'nope'), '')
})

test('every action has a config key, a label and a hint, and ids are unique', () => {
  const ids = new Set()
  const configs = new Set()
  for (const action of ACTIONS) {
    assert.ok(action.label && action.hint && action.config && action.default, action.id)
    assert.ok(!ids.has(action.id) && !configs.has(action.config), action.id)
    ids.add(action.id)
    configs.add(action.config)
    assert.notEqual(parseBinding(action, action.default), null, `${action.id} default must parse`)
  }
})
