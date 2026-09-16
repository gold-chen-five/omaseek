import { test } from 'node:test'
import assert from 'node:assert/strict'
import { describeError, normalizeRow, mergeResults, statusText, modeLabel, confirmClearText } from '../src/lib/search.mjs'
import { VIEW, PANEL, FOCUS } from '../src/lib/states.mjs'

test('the backend message wins, because it names the port or the setting to fix', () => {
  assert.equal(
    describeError({ error: 'network', message: 'SearXNG is not reachable at http://localhost:8888' }),
    'SearXNG is not reachable at http://localhost:8888'
  )
  assert.equal(describeError({ error: 'network' }), 'No network connection', 'a bare kind still reads')
})


test('an unknown error falls back to the backend message, then a default', () => {
  assert.equal(describeError({ error: 'weird', message: 'boom' }), 'boom')
  assert.equal(describeError({}), 'Search failed')
  assert.equal(describeError(), 'Search failed')
})

test('rows are normalized to the delegate shape', () => {
  const row = normalizeRow({ title: 'T', url: 'https://x', display_url: 'x', icon: 'i' })
  assert.deepEqual(row, { title: 'T', url: 'https://x', snippet: '', display_url: 'x', icon: 'i' })
})

test('a missing row yields empty strings, never undefined', () => {
  assert.deepEqual(normalizeRow(), { title: '', url: '', snippet: '', display_url: '', icon: '' })
})

test('merging a page drops rows already on screen', () => {
  const existing = ['https://a', 'https://b']
  const added = mergeResults(existing, [
    { url: 'https://b', title: 'dupe' },
    { url: 'https://c', title: 'new' }
  ])
  assert.equal(added.length, 1)
  assert.equal(added[0].url, 'https://c')
})

test('merging de-duplicates within the incoming page too', () => {
  const added = mergeResults([], [
    { url: 'https://a', title: 'one' },
    { url: 'https://a', title: 'one again' }
  ])
  assert.equal(added.length, 1)
})

test('the same page under different canonical urls collapses', () => {
  const added = mergeResults([], [
    { url: 'https://doc.rust-lang.org/book/ch04.html', title: 'What is Ownership?', display_url: 'doc.rust-lang.org' },
    { url: 'https://doc.rust-lang.org/stable/book/ch04.html', title: 'What is Ownership?', display_url: 'doc.rust-lang.org' }
  ])
  assert.equal(added.length, 1, 'engines return /book/ and /stable/book/ as separate hits')
})

test('the same title on a different domain is kept', () => {
  const added = mergeResults([], [
    { url: 'https://a.com/x', title: 'Ownership', display_url: 'a.com' },
    { url: 'https://b.com/x', title: 'Ownership', display_url: 'b.com' }
  ])
  assert.equal(added.length, 2)
})

test('rows without a url are dropped', () => {
  assert.equal(mergeResults([], [{ title: 'no url' }]).length, 0)
})

test('a page of pure duplicates adds nothing', () => {
  const added = mergeResults(['https://a'], [{ url: 'https://a' }])
  assert.deepEqual(added, [], 'the panel uses this to skip ahead a page')
})

test('status line reflects each state', () => {
  assert.equal(statusText({ status: 'loading' }), 'Searching…')
  assert.equal(statusText({ status: 'error', errorMessage: 'nope' }), 'nope')
  assert.match(statusText({ status: 'empty', query: 'zz' }), /No results for “zz”/)
  assert.match(statusText({ status: 'idle' }), /enter searches/)
  assert.match(statusText({ status: 'idle' }), /ctrl\+s settings/, 'the settings key must be discoverable')
})




test('status line names the current page', () => {
  assert.match(statusText({ status: 'ok', count: 10, page: 2, hasNext: true }), /^page 2 · 10 results · h\/l pages/)
})

test('status line marks the last page', () => {
  assert.match(statusText({ status: 'ok', count: 6, page: 3, hasNext: false }), /page 3 · 6 results · end/)
  assert.doesNotMatch(statusText({ status: 'ok', count: 10, page: 1, hasNext: true }), / · end/)
})

test('fetching the next page announces the page being fetched', () => {
  assert.equal(statusText({ status: 'ok', count: 10, page: 2, loadingPage: true }), 'page 3 · loading…')
})

test('mode label follows focus, not just the editor mode', () => {
  assert.equal(modeLabel({ focusArea: FOCUS.RESULTS, mode: 'normal' }), 'RESULTS')
  assert.equal(modeLabel({ focusArea: FOCUS.FIELD, mode: 'insert' }), 'INSERT')
  assert.equal(modeLabel({ view: VIEW.SETTINGS, focusArea: FOCUS.RESULTS, mode: 'insert' }), 'SETTINGS')
  assert.equal(modeLabel({ view: VIEW.SETUP, focusArea: FOCUS.FIELD, mode: 'normal' }), 'SETUP')
})

test('the settings and setup views name their keys instead of search state', () => {
  assert.match(statusText({ view: VIEW.SETTINGS, status: 'ok', count: 10 }), /esc back/)
  assert.match(statusText({ view: VIEW.SETUP, status: 'error', errorMessage: 'x' }), /h\/l choose/)
  assert.match(statusText({ view: VIEW.SEARCH, status: 'ok', count: 10, page: 1 }), /^page 1/)
})

test('AI mode names the agent while it thinks and its keys once it has answered', () => {
  assert.equal(statusText({ panelMode: PANEL.AI, status: 'thinking', agent: 'claude' }), 'asking claude…')
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok' }), /v select/)
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok', selecting: true }), /enter hands off/)
  assert.equal(statusText({ panelMode: PANEL.AI, status: 'error', errorMessage: 'nope' }), 'nope')
  assert.match(statusText({ panelMode: PANEL.AI, status: 'idle' }), /tab search/)
  assert.match(statusText({ panelMode: PANEL.AI, view: VIEW.SETTINGS, status: 'ok' }), /esc back/, 'the settings view wins')
  assert.equal(modeLabel({ panelMode: PANEL.AI, focusArea: FOCUS.FIELD, mode: 'insert' }), 'AI · INSERT')
  assert.equal(modeLabel({ panelMode: PANEL.AI, focusArea: FOCUS.RESULTS, mode: 'normal' }), 'AI · ANSWER')
  assert.equal(modeLabel({ panelMode: PANEL.AI, focusArea: FOCUS.RESULTS, mode: 'normal', selecting: true }), 'AI · VISUAL')
})


test('on a link, the answer hint says gx and where it goes', () => {
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok', link: 'https://www.rust-lang.org/learn' }), /^gx opens rust-lang\.org · /)
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok', link: 'https://x.io', selecting: true }), /^gx opens x\.io · y yank/)
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok', selecting: true }), /enter hands off/)
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok' }), /^v select · yy yank · enter hands off/)
})


test('a hand-off is the selected result’s URL, or every URL on the page', async () => {
  const { handoffText } = await import('../src/lib/search.mjs')
  const rows = [{ title: 'One', url: 'https://one.test', snippet: 'first' },
                { title: 'Two', url: 'https://two.test', snippet: 'second' }]
  assert.equal(handoffText(rows, 1), 'https://two.test')
  assert.equal(handoffText(rows), 'https://one.test\nhttps://two.test')
  assert.equal(handoffText([]), '')
  assert.equal(handoffText(rows, 5), '')
  assert.equal(handoffText([{ title: 'No link', url: '' }], 0), '')
})

test('the AI line says where in the ring the conversation is, before the keys', () => {
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok', session: 'session 2/3' }),
    /^session 2\/3 · v select/)
  assert.match(statusText({ panelMode: PANEL.AI, status: 'ok', session: 'session 2/3' }),
    /ctrl\+n next/, 'walking the ring must be discoverable')
  assert.equal(statusText({ panelMode: PANEL.AI, status: 'thinking', agent: 'claude', session: '3 saved' }),
    '3 saved · asking claude…')
  assert.match(statusText({ panelMode: PANEL.AI, status: 'idle', session: '3 saved' }), /^3 saved · enter asks/)
})

// It elides from the right, so anything past the width teaches nothing. The
// panel is 820 wide at caption size; 70 characters is the room that leaves.
test('no AI status line is long enough to elide', () => {
  const lines = [
    statusText({ panelMode: PANEL.AI, status: 'ok', session: 'session 10/10' }),
    statusText({ panelMode: PANEL.AI, status: 'ok', selecting: true }),
    statusText({ panelMode: PANEL.AI, status: 'ok', selecting: true, link: 'https://doc.rust-lang.org/book/ch15.html' }),
    statusText({ panelMode: PANEL.AI, status: 'ok', link: 'https://doc.rust-lang.org/book/ch15.html' }),
    statusText({ panelMode: PANEL.AI, status: 'idle', session: '10 saved' }),
    statusText({ panelMode: PANEL.AI, status: 'thinking', agent: 'cursor-agent', session: 'session 10/10' })
  ]
  for (const line of lines) assert.ok(line.length <= 70, `${line.length}: ${line}`)
})

test('the destructive key names itself and what it will forget', () => {
  assert.equal(confirmClearText('ctrl+shift+x', 3), 'ctrl+shift+x again to forget all 3 conversations · anything else cancels')
  assert.match(confirmClearText('ctrl+shift+x', 1), /the saved conversation ·/)
  // Rebound, it must say the key that is actually bound.
  assert.match(confirmClearText('ctrl+alt+k', 2), /^ctrl\+alt\+k again/)
  assert.ok(confirmClearText('ctrl+shift+x', 10).length <= 74)
})

test('y yanks a result’s URL, Y the title above it', async () => {
  const { resultYankText, yankNotice } = await import('../src/lib/search.mjs')
  const row = { title: 'The Rust Book', url: 'https://doc.rust-lang.org/book/', display_url: 'doc.rust-lang.org' }

  assert.equal(resultYankText(row, false), 'https://doc.rust-lang.org/book/')
  assert.equal(resultYankText(row, true), 'The Rust Book\nhttps://doc.rust-lang.org/book/')
  // A row the page no longer holds yanks nothing rather than throwing.
  assert.equal(resultYankText(null, true), '')
  assert.equal(resultYankText({ title: 'no link' }, false), '')
  // A row whose title fell back to its domain still yanks something useful.
  assert.equal(resultYankText({ url: 'https://x.test', title: '' }, true), 'https://x.test')

  assert.equal(yankNotice(false), 'yanked the URL')
  assert.equal(yankNotice(true), 'yanked the title and URL')
  assert.ok(yankNotice(true).length <= 70)
})
