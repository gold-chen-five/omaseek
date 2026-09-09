import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  charClass, wordForward, wordBackward, wordEnd,
  firstNonBlank, find, flipFind, clampToLine, repeat, BLANK, WORD, PUNCT
} from '../src/lib/motions.mjs'

test('charClass separates blanks, word characters and punctuation', () => {
  assert.equal(charClass('a b', 0), WORD)
  assert.equal(charClass('a b', 1), BLANK)
  assert.equal(charClass('a.b', 1), PUNCT)
  assert.equal(charClass('a_1', 2), WORD, 'digits and underscore are word chars')
  assert.equal(charClass('abc', 99), BLANK, 'out of range reads as blank')
  assert.equal(charClass('a.b', 1, true), WORD, 'WORD motions fold punctuation in')
})

test('w steps to the start of the next word', () => {
  const text = 'rust ownership rules'
  assert.equal(wordForward(text, 0), 5)
  assert.equal(wordForward(text, 5), 15)
  assert.equal(wordForward(text, 15), text.length, 'stops at end of line')
})

test('w treats punctuation as its own word, W does not', () => {
  const text = 'foo.bar baz'
  assert.equal(wordForward(text, 0), 3, 'w stops on the dot')
  assert.equal(wordForward(text, 0, true), 8, 'W skips the whole blob')
})

test('b steps back to the start of the previous word', () => {
  const text = 'rust ownership rules'
  assert.equal(wordBackward(text, 19), 15)
  assert.equal(wordBackward(text, 15), 5)
  assert.equal(wordBackward(text, 0), 0, 'clamps at the start')
})

test('b from inside a word lands on that word start', () => {
  assert.equal(wordBackward('rust ownership', 9), 5)
})

test('e moves to the end of the current or next word', () => {
  const text = 'rust ownership'
  assert.equal(wordEnd(text, 0), 3)
  assert.equal(wordEnd(text, 3), 13)
  assert.equal(wordEnd('', 0), 0, 'empty text is safe')
})

test('^ finds the first non-blank', () => {
  assert.equal(firstNonBlank('   indented'), 3)
  assert.equal(firstNonBlank('flush'), 0)
  assert.equal(firstNonBlank('    '), 0, 'all blanks falls back to 0')
})

test('f and t differ by one, F and T search backwards', () => {
  const text = 'alpha beta gamma'
  assert.equal(find(text, 0, 'f', 'b'), 6)
  assert.equal(find(text, 0, 't', 'b'), 5)
  assert.equal(find(text, 16, 'F', 'b'), 6)
  assert.equal(find(text, 16, 'T', 'b'), 7)
})

test('a find that misses returns -1', () => {
  assert.equal(find('alpha', 0, 'f', 'z'), -1)
  assert.equal(find('alpha', 4, 'f', 'a'), -1, 'searches strictly forward')
})

test(', flips the direction of the last find', () => {
  assert.equal(flipFind('f'), 'F')
  assert.equal(flipFind('T'), 't')
})

test('normal mode clamps the cursor onto a character', () => {
  assert.equal(clampToLine('abc', 3), 2, 'never past the last character')
  assert.equal(clampToLine('abc', -1), 0)
  assert.equal(clampToLine('', 5), 0, 'empty line sits at 0')
})

test('counts repeat a motion', () => {
  const text = 'one two three four'
  const w = at => wordForward(text, at)
  assert.equal(repeat(w, 3, 0), 14, '3w')
  assert.equal(repeat(w, 1, 0), 4)
})
