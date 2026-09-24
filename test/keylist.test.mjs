import { test } from 'node:test'
import assert from 'node:assert/strict'
import { keyEntries, filterEntries, GROUP_ORDER } from '../src/settings/keylist.mjs'
import { ACTIONS } from '../src/shared/vim/keybinds.mjs'

test('every rebindable key is listed, with the key it is bound to now', () => {
  const entries = keyEntries({})
  for (const action of ACTIONS) assert.ok(entries.some(e => e.label === action.label && e.hint === action.hint), action.id)
  const rebound = keyEntries({ askNowKey: 'gz' })
  assert.ok(rebound.some(e => e.keys === 'gz' && e.label === 'Ask about this'), 'a rebound key shows as bound')
  assert.ok(entries.some(e => e.keys === 'ctrl+k' && /Look up keys/.test(e.label)), 'the lookup lists itself')
})

test('a row is a settings row: a label, the key beside it, the hint under it', () => {
  const entries = keyEntries({})
  for (const entry of entries) {
    assert.equal(typeof entry.label, 'string')
    assert.equal(typeof entry.hint, 'string')
    assert.ok(entry.label !== '', 'every row says what it does')
    // A fixed key is a line of vim's own keys: it has no binding to show.
    if (entry.fixed) assert.equal(entry.keys, '')
    else assert.ok(entry.keys !== '', entry.label + ' shows its key')
  }
  assert.ok(entries.some(e => e.fixed), 'the fixed keys are listed too')
})

test('the keys come first, in the settings page’s own order, the fixed ones under them', () => {
  const entries = keyEntries({})
  const groups = entries.map(e => e.group)
  const seen = []
  for (const g of groups) if (seen[seen.length - 1] !== g) seen.push(g)
  assert.deepEqual(seen, GROUP_ORDER, 'two sections, as the page has them')
  const keys = entries.filter(e => e.group === 'Keys')
  assert.equal(keys[0].label, 'Leave insert with', 'the escape sequence opens the section, as it opens the page’s')
  assert.deepEqual(keys.slice(1).map(e => e.label), ACTIONS.map(a => a.label), 'then ACTIONS, in order')
})

test('typed words filter by key, meaning, hint or group, in any case', () => {
  const entries = keyEntries({})
  const translate = filterEntries(entries, 'TRANS')
  assert.ok(translate.some(e => e.keys === 'gt') && translate.some(e => e.keys === 'gT') && translate.some(e => e.keys === 'ctrl+t'))
  assert.ok(filterEntries(entries, 'ctrl+x').length > 0)
  const words = e => (e.keys + ' ' + e.label + ' ' + e.hint + ' ' + e.group).toLowerCase()
  assert.ok(filterEntries(entries, 'ask now').every(e => /ask/.test(words(e)) && /now/.test(words(e))), 'every word must match')
  const suggestions = filterEntries(entries, 'ctrl+p')
  assert.ok(suggestions.some(e => e.label === 'Suggestions (search)' && /ctrl\+n ctrl\+p/.test(e.hint)),
    'the suggestion keys have their own row')
  assert.ok(filterEntries(entries, 'suggestion ctrl+n').some(e => e.label === 'Suggestions (search)'))
  assert.equal(filterEntries(entries, '').length, entries.length)
  assert.equal(filterEntries(entries, 'zzzz nothing').length, 0)
})
