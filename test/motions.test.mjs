import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  charClass, wordForward, wordBackward, wordEnd,
  firstNonBlank, linesDown, charStep, find, findInLine, findMatchPosition, matchingCharsInLine,
  flipFind, clampToLine, insertExit, repeat, lineCount, lineStartAt, BLANK, WORD, PUNCT
} from '../src/shared/vim/motions.mjs'

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
  assert.equal(firstNonBlank('first\n  second', 9), 8, 'on the line holding the cursor')
  assert.equal(firstNonBlank('first\n   \nthird', 7), 6, 'an all-blank line falls back to its start')
})

test('a count on $ and _ reaches lines further down', () => {
  const text = 'one\ntwo\nthree'
  assert.equal(linesDown(text, 1, 1), 1, 'a count of one stays')
  assert.equal(linesDown(text, 1, 2), 5)
  assert.equal(linesDown(text, 1, 9), 9, 'stops on the last line')
})

test('f and t differ by one, F and T search backwards', () => {
  const text = 'alpha beta gamma'
  assert.equal(find(text, 0, 'f', 'b'), 6)
  assert.equal(find(text, 0, 't', 'b'), 5)
  assert.equal(find(text, 16, 'F', 'b'), 6)
  assert.equal(find(text, 16, 'T', 'b'), 7)
})

test('a repeated f starts after its current match', () => {
  const text = 'bananas'
  const first = find(text, 0, 'f', 'a')
  assert.equal(first, 1)
  assert.equal(find(text, first, 'f', 'a'), 3, 'semicolon repeats at the next match')
})

test('clever-f can reverse through the same matches with F', () => {
  const text = 'bananas'
  assert.equal(findInLine(text, 1, 'f', 'a', 1, true), 3)
  assert.equal(findInLine(text, 3, 'F', 'a', 1, true), 1)
})

test('find highlights name every match and the actual t/T target', () => {
  assert.deepEqual(matchingCharsInLine('a banana\na pear', 3, 'a'), [0, 3, 5, 7])
  assert.deepEqual(matchingCharsInLine('a banana\na pear', 10, 'a'), [9, 13])
  assert.equal(findMatchPosition(2, 'f'), 2)
  assert.equal(findMatchPosition(2, 't'), 3)
  assert.equal(findMatchPosition(2, 'T'), 1)
})

test('a find that misses returns -1', () => {
  assert.equal(find('alpha', 0, 'f', 'z'), -1)
  assert.equal(find('alpha', 4, 'f', 'a'), -1, 'searches strictly forward')
})

test(', flips the direction of the last find', () => {
  assert.equal(flipFind('f'), 'F')
  assert.equal(flipFind('T'), 't')
})

test('normal mode clamps within a logical line', () => {
  assert.equal(clampToLine('abc', 3), 2, 'never past the last character')
  assert.equal(clampToLine('abc', -1), 0)
  assert.equal(clampToLine('', 5), 0, 'empty line sits at 0')
  assert.equal(clampToLine('abc\n', 4), 4, 'an empty final line stays reachable')
  assert.equal(clampToLine('a\n\nb', 2), 2, 'an empty middle line stays reachable')
  assert.equal(clampToLine('abc\ndef', 3), 2, 'a line break clamps to the preceding character')
})

test('leaving insert mode steps left without crossing a line break', () => {
  assert.equal(insertExit('first\nsecond', 6), 6, 'first character of the second line')
  assert.equal(insertExit('first\nsecond', 8), 7, 'inside the second line')
  assert.equal(insertExit('first', 3), 2)
  assert.equal(insertExit('first', 0), 0)
})

test('counts repeat a motion', () => {
  const text = 'one two three four'
  const w = at => wordForward(text, at)
  assert.equal(repeat(w, 3, 0), 14, '3w')
  assert.equal(repeat(w, 1, 0), 4)
})

test('h and l stop at the line’s ends instead of running onto the next', () => {
  const text = 'first\nsecond\n\nfourth'
  assert.equal(charStep(text, 2, 1), 3, 'along the line')
  assert.equal(charStep(text, 4, 1), 4, 'l on the last character stays')
  assert.equal(charStep(text, 6, -1), 6, 'h on the first character stays')
  assert.equal(charStep(text, 7, 99), 11, 'a count stops at the last character')
  assert.equal(charStep(text, 11, -99), 6, 'and back at the first')
  assert.equal(charStep(text, 13, 1), 13, 'a blank line has one place')
  assert.equal(charStep(text, 13, -1), 13)
  assert.equal(charStep(text, 3, 9, true), 5, 'an operator may take the line to its end')
  assert.equal(charStep('', 0, 1), 0)
})

test('gg and G land on a line’s first non-blank, a count naming the line', () => {
  const text = 'first\n  second\n\nfourth'
  assert.equal(lineCount(text), 4)
  assert.equal(lineCount(''), 1, 'an empty question is still one line')
  assert.equal(lineStartAt(text, 1), 0)
  assert.equal(lineStartAt(text, 2), 8, 'past the indent')
  assert.equal(lineStartAt(text, 3), 15, 'a blank line is its start')
  assert.equal(lineStartAt(text, lineCount(text)), 16)
  assert.equal(lineStartAt(text, 99), 16, 'a count past the end stops on the last line')
  assert.equal(lineStartAt('one line', 1), 0)
})
