import test from 'node:test'
import assert from 'node:assert/strict'
import { urlAt, isOpenable, hostOf, urlFromSelection } from '../src/lib/urls.mjs'

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

test('a selection opens when it is a URL, cleaned of what surrounds it', () => {
  assert.equal(urlFromSelection('https://doc.rust-lang.org/book/'), 'https://doc.rust-lang.org/book/')
  assert.equal(urlFromSelection('(https://doc.rust-lang.org/book/),'), 'https://doc.rust-lang.org/book/')
  assert.equal(urlFromSelection('  https://rust-lang.org\u2029'), 'https://rust-lang.org')
})

test('a bare domain in a selection gets https', () => {
  assert.equal(urlFromSelection('rust-lang.org/learn'), 'https://rust-lang.org/learn')
  assert.equal(urlFromSelection('www.rust-lang.org'), 'https://www.rust-lang.org')
  assert.equal(urlFromSelection('localhost.dev:8080/x'), 'https://localhost.dev:8080/x')
})

test('a selection that is not a web URL opens nothing', () => {
  for (const s of ['Rust', 'hello world', 'v1.2', 'e.g', 'file:///etc/passwd', 'javascript:alert(1)', 'mailto:a@b.co', '']) {
    assert.equal(urlFromSelection(s), '', s)
  }
})


test('gx finds bare domains beside paragraph separators and skips surrounding prose', () => {
  const text = 'Official website: rust-lang.org\u2029Free beginner book: The Rust Programming Language.'
  assert.equal(urlAt(text, text.indexOf('rust-lang.org') + 3), 'https://rust-lang.org')
  assert.equal(urlAt(text, text.indexOf('website')), '')
  assert.equal(urlAt('(rust-lang.org).', 4), 'https://rust-lang.org')
  assert.equal(urlAt('javascript:rust-lang.org', 15), '')
})

test('cursor link metadata preserves the actual target and query parameters', async () => {
  const { hrefFromHtml } = await import('../src/lib/urls.mjs')
  assert.equal(hrefFromHtml('<p><a href="https://doc.rust-lang.org/book/?x=1&amp;y=2">R</a></p>'),
    'https://doc.rust-lang.org/book/?x=1&y=2')
  assert.equal(hrefFromHtml('<p>R</p>'), '')
})
