import { test } from 'node:test'
import assert from 'node:assert/strict'
import { resolve, resolveInLine, isTextObject } from '../src/vim/textobjects.mjs'

// Reads a range back as text, so the assertions say what the user would see.
const cut = (text, pos, scope, object) => {
  const range = resolve(text, pos, scope, object)
  return range === null ? null : text.slice(range.start, range.end)
}

test('iw takes the word under the cursor, from anywhere in it', () => {
  const text = 'rust ownership rules'
  assert.equal(cut(text, 5, 'i', 'w'), 'ownership')
  assert.equal(cut(text, 9, 'i', 'w'), 'ownership', 'mid-word')
  assert.equal(cut(text, 13, 'i', 'w'), 'ownership', 'last character')
})

test('iw on whitespace takes the whitespace run', () => {
  assert.equal(cut('a   b', 2, 'i', 'w'), '   ')
})

test('aw takes the trailing whitespace with the word', () => {
  assert.equal(cut('rust ownership rules', 0, 'a', 'w'), 'rust ')
})

test('aw takes leading whitespace when the word ends the line', () => {
  assert.equal(cut('rust ownership', 5, 'a', 'w'), ' ownership', 'so daw leaves one gap, not two')
})

test('w stops at punctuation, W does not', () => {
  assert.equal(cut('foo.bar baz', 0, 'i', 'w'), 'foo')
  assert.equal(cut('foo.bar baz', 0, 'i', 'W'), 'foo.bar')
})

test('i" takes what is inside the quotes, a" takes the quotes too', () => {
  const text = 'search "rust ownership" now'
  assert.equal(cut(text, 12, 'i', '"'), 'rust ownership')
  assert.equal(cut(text, 12, 'a', '"'), '"rust ownership" ', 'and the trailing space')
})

test('quotes pair from the start of the line, as vim does', () => {
  const text = '"one" and "two"'
  assert.equal(cut(text, 2, 'i', '"'), 'one')
  assert.equal(cut(text, 12, 'i', '"'), 'two')
})

test('a cursor before any quote reaches the next pair', () => {
  assert.equal(cut('go to "there"', 0, 'i', '"'), 'there')
})

test('an empty pair of quotes gives an empty range, not null', () => {
  assert.equal(cut('a "" b', 3, 'i', '"'), '')
})

test('single quotes and backticks work the same way', () => {
  assert.equal(cut("say 'hello' now", 6, 'i', "'"), 'hello')
  assert.equal(cut('run `cmd` now', 6, 'i', '`'), 'cmd')
})

test('i( takes the innermost enclosing pair', () => {
  const text = 'fn(a, g(b), c)'
  assert.equal(cut(text, 4, 'i', '('), 'a, g(b), c')
  assert.equal(cut(text, 9, 'i', '('), 'b', 'nested')
})

test('a( includes the brackets', () => {
  assert.equal(cut('fn(a, b)', 4, 'a', '('), '(a, b)')
})

test('either bracket key selects the same pair, and b and B alias', () => {
  const text = 'fn(a, b)'
  assert.equal(cut(text, 4, 'i', '('), cut(text, 4, 'i', ')'))
  assert.equal(cut(text, 4, 'i', 'b'), 'a, b')
  assert.equal(cut('x {y} z', 3, 'i', 'B'), 'y')
})

test('brackets, braces and angles each find their own kind', () => {
  assert.equal(cut('a [b] c', 3, 'i', '['), 'b')
  assert.equal(cut('a {b} c', 3, 'i', '{'), 'b')
  assert.equal(cut('a <b> c', 3, 'i', '<'), 'b')
})

test('an unclosed or absent pair resolves to nothing', () => {
  assert.equal(resolve('fn(a, b', 4, 'i', '('), null, 'never closed')
  assert.equal(resolve('plain text', 3, 'i', '('), null, 'no bracket at all')
  assert.equal(resolve('no quotes here', 3, 'i', '"'), null)
})

test('empty text is safe', () => {
  assert.equal(resolve('', 0, 'i', 'w'), null)
})

test('the object keys are exactly the ones we handle', () => {
  for (const key of ['w', 'W', '"', "'", '`', '(', ')', 'b', '[', ']', '{', '}', 'B', '<', '>']) {
    assert.ok(isTextObject(key), `${key} should be an object`)
  }
  for (const key of ['z', 'd', '1', '']) assert.ok(!isTextObject(key))
})

test('resolveInLine keeps an object to its line, in whole-text positions', () => {
  const text = 'say "one\n"two" ok'
  const take = pos => { const r = resolveInLine(text, pos, 'i', '"'); return r && text.slice(r.start, r.end) }
  assert.equal(take(11), 'two')
  assert.equal(take(5), null)                   // its closing quote is on the next line
  const word = resolveInLine('first\nsecond', 8, 'i', 'w')
  assert.deepEqual(word, { start: 6, end: 12 })
  assert.equal(resolveInLine('a\n\nb', 2, 'i', 'w'), null)   // an empty line
})
