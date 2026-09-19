import { test } from 'node:test'
import assert from 'node:assert/strict'
import { keyEntries, filterEntries, GROUP_ORDER } from '../src/settings/keylist.mjs'
import { ACTIONS } from '../src/shared/vim/keybinds.mjs'

test('every rebindable key is listed, with the key it is bound to now', () => {
  const entries = keyEntries({})
  for (const action of ACTIONS) assert.ok(entries.some(e => e.text.indexOf(action.label + ' — ') === 0), action.id)
  const rebound = keyEntries({ askNowKey: 'gz' })
  assert.ok(rebound.some(e => e.keys === 'gz' && e.text.indexOf('Ask about this') === 0), 'a rebound key shows as bound')
  assert.ok(entries.some(e => e.keys === 'ctrl+k' && /Look up keys/.test(e.text)), 'the lookup lists itself')
})

test('groups come in one order, each together', () => {
  const groups = keyEntries({}).map(e => e.group)
  const seen = []
  for (const g of groups) if (seen[seen.length - 1] !== g) seen.push(g)
  assert.equal(new Set(seen).size, seen.length, 'no group is split in two')
  const known = seen.filter(g => GROUP_ORDER.indexOf(g) !== -1)
  assert.deepEqual(known, [...known].sort((a, b) => GROUP_ORDER.indexOf(a) - GROUP_ORDER.indexOf(b)))
})

test('typed words filter by key, meaning or group, in any case', () => {
  const entries = keyEntries({})
  const translate = filterEntries(entries, 'TRANS')
  assert.ok(translate.some(e => e.keys === 'gt') && translate.some(e => e.keys === 'gT') && translate.some(e => e.keys === 'ctrl+t'))
  assert.ok(filterEntries(entries, 'ctrl+x').length > 0)
  assert.ok(filterEntries(entries, 'ask now').every(e => /ask/i.test(e.keys + e.text + e.group) && /now/i.test(e.keys + e.text + e.group)), 'every word must match')
  assert.equal(filterEntries(entries, '').length, entries.length)
  assert.equal(filterEntries(entries, 'zzzz nothing').length, 0)
})
