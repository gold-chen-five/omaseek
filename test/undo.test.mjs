import { test } from 'node:test'
import assert from 'node:assert/strict'
import { start, record, undo, redo, changeStart, LIMIT } from '../src/shared/vim/undo.mjs'

test('what changed between two boundaries is one step', () => {
  let s = start('rust ownership')
  // ciw, a word typed, the j of jk typed and taken back: no boundary in between
  s = record(s, 'rust borrowing')
  const back = undo(s, 'rust borrowing')
  assert.equal(back.text, 'rust ownership', 'u goes back to before ciw, not to the stray j')
  assert.equal(undo(back.state, back.text), null, 'and that was the only step')
})

test('an unrecorded edit is recorded by the undo itself', () => {
  const s = start('a')
  assert.equal(undo(s, 'ab').text, 'a')
})

test('a boundary with nothing changed is not a step', () => {
  const s = record(start('same'), 'same')
  assert.equal(undo(s, 'same'), null)
})

test('ctrl+r redoes, and a new edit clears the redo', () => {
  let s = record(record(start('one'), 'one two'), 'one two three')
  const back = undo(s, 'one two three', 2)
  assert.equal(back.text, 'one', 'a count undoes several')
  const again = redo(back.state, back.text)
  assert.equal(again.text, 'one two')
  const edited = record(again.state, 'one two!')
  assert.equal(redo(edited, 'one two!'), null)
  assert.equal(undo(edited, 'one two!').text, 'one two')
})

test('the stack keeps the last hundred steps', () => {
  let s = start('')
  for (let i = 1; i <= LIMIT + 20; i++) s = record(s, String(i))
  assert.equal(s.undo.length, LIMIT)
})

test('the cursor lands where the undone change began', () => {
  assert.equal(changeStart('rust borrowing', 'rust ownership'), 5)
  assert.equal(changeStart('abc', 'abc'), 3)
  assert.equal(changeStart('', 'x'), 0)
})
