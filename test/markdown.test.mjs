import test from 'node:test'
import assert from 'node:assert/strict'
import { toHtml, inline, escapeHtml, renderTranscript } from '../src/lib/markdown.mjs'

test('inline marks become tags and html is escaped', () => {
  assert.equal(inline('a **b** c'), 'a <b>b</b> c')
  assert.equal(inline('a *b* c'), 'a <i>b</i> c')
  assert.equal(inline('use `x < y` here'), 'use <code>x &lt; y</code> here')
  assert.equal(inline('see [docs](https://x.y/z)'), 'see <a href="https://x.y/z">docs</a>')
  assert.equal(inline('snake_case_name stays'), 'snake_case_name stays')
  assert.equal(inline('2 * 3 * 4'), '2 * 3 * 4', 'lone asterisks are arithmetic, not emphasis')
  assert.equal(escapeHtml('<b>&"'), '&lt;b&gt;&amp;&quot;')
})

test('blocks: paragraphs, fenced code, headings, lists, quotes', () => {
  assert.equal(toHtml('one\ntwo\n\nthree'), '<p>one two</p><p>three</p>')
  assert.equal(toHtml('```js\nlet a = 1 < 2\n```'), '<pre>let a = 1 &lt; 2</pre>')
  assert.equal(toHtml('# Title'), '<h2>Title</h2>', 'headings step down one level')
  assert.equal(toHtml('- a\n- b\n\n1. c\n2. d'), '<ul><li>a</li><li>b</li></ul><ol><li>c</li><li>d</li></ol>')
  assert.equal(toHtml('- a\n  continues'), '<ul><li>a continues</li></ul>')
  assert.equal(toHtml('> q'), '<blockquote>q</blockquote>')
})

test('a colour wraps every block and the lead lands once, on the first', () => {
  const html = toHtml('a\n\n- b\n- c', { color: '#abc', lead: '<s>●</s>' })
  assert.equal(html, '<p><span style="color:#abc"><s>●</s>a</span></p><ul><li><span style="color:#abc">b</span></li><li><span style="color:#abc">c</span></li></ul>')
  assert.equal(toHtml('```\nx\n```', { lead: 'L' }), '<pre>Lx</pre>')
})

test('the transcript colours questions and answers apart', () => {
  const html = renderTranscript(
    [{ role: 'user', text: 'why <this>?' }, { role: 'assistant', text: 'because **so**' }],
    { question: '#fff', answer: '#ccc', glyph: '#888', dotSize: 9 }
  )
  assert.match(html, /<span style="color:#888">&gt; <\/span><b><span style="color:#fff">why &lt;this&gt;\?<\/span><\/b>/)
  assert.match(html, /<p><span style="color:#ccc"><span style="color:#888;font-size:9px;">● <\/span>because <b>so<\/b><\/span><\/p>/)
  assert.equal(renderTranscript([]), '')
})

test('a failed turn is written where its answer would have been', () => {
  const html = renderTranscript([{ role: 'user', text: 'q' }, { role: 'error', text: 'Codex: You hit <a limit>' }], { error: '#f00' })
  assert.match(html, /<p><span style="color:#f00">⚠ Codex: You hit &lt;a limit&gt;<\/span><\/p>$/)
})


test('a link takes the colour it is given, so a TextEdit does not paint it Qt blue', () => {
  assert.equal(inline('see [docs](https://x.y)'), 'see <a href="https://x.y">docs</a>')
  assert.equal(inline('see [docs](https://x.y)', '#abc'), 'see <a href="https://x.y" style="color:#abc">docs</a>')
  const html = renderTranscript([{ role: 'assistant', text: 'read [this](https://x.y)' }], { link: '#abc' })
  assert.ok(html.includes('<a href="https://x.y" style="color:#abc">this</a>'))
})
