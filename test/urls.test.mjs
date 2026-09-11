import test from 'node:test'
import assert from 'node:assert/strict'
import { urlAt, isOpenable, hostOf } from '../src/lib/urls.mjs'

const book = 'Good places are (https://doc.rust-lang.org/book/), and Rustlings.'

test('a bare URL under the cursor, without the sentence around it', () => {
  const at = book.indexOf('rust-lang')
  assert.equal(urlAt(book, at), 'https://doc.rust-lang.org/book/')
  assert.equal(urlAt(book, book.indexOf('https')), 'https://doc.rust-lang.org/book/')
})

test('off the URL, or on the punctuation after it, is nothing', () => {
  assert.equal(urlAt(book, 0), '')
  assert.equal(urlAt(book, book.indexOf('),')), '')
  assert.equal(urlAt('', 0), '')
})

test('a closing bracket stays when the URL opened one', () => {
  const wiki = 'see https://en.wikipedia.org/wiki/Rust_(programming_language).'
  assert.equal(urlAt(wiki, wiki.indexOf('wiki')), 'https://en.wikipedia.org/wiki/Rust_(programming_language)')
})

test('only http and https are opened', () => {
  assert.ok(isOpenable('https://rust-lang.org'))
  assert.ok(isOpenable('http://localhost:8888/search'))
  assert.equal(isOpenable('file:///etc/passwd'), false)
  assert.equal(isOpenable('javascript:alert(1)'), false)
  assert.equal(isOpenable('/relative/path'), false)
  assert.equal(isOpenable(''), false)
})

test('the host, for the status line', () => {
  assert.equal(hostOf('https://www.rust-lang.org/learn'), 'rust-lang.org')
  assert.equal(hostOf('https://doc.rust-lang.org/book/'), 'doc.rust-lang.org')
  assert.equal(hostOf('not a url'), '')
})
