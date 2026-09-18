import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readKeymap, advance, isTypedKey, DEFAULT_SEQUENCES, DEFAULT_TIMEOUT_MS
} from '../src/shared/vim/keymap.mjs'

test('jk completes the sequence and takes back the j already typed', () => {
  const first = advance('', 'j', ['jk'])
  assert.deepEqual(first, { pending: 'j', escaped: false, strip: 0 }, 'j types normally')

  const second = advance(first.pending, 'k', ['jk'])
  assert.equal(second.escaped, true)
  assert.equal(second.strip, 1, 'the j is removed, the k never types')
  assert.equal(second.pending, '')
})

test('any other key ends the run', () => {
  assert.deepEqual(advance('j', 'a', ['jk']), { pending: '', escaped: false, strip: 0 })
})

test('a broken run keeps the longest tail that still opens a sequence', () => {
  assert.equal(advance('j', 'j', ['jk']).pending, 'j', 'jjk still escapes on the second j')
  assert.equal(advance('j', 'k', ['jkl']).pending, 'jk', 'longer sequences keep building')
})

test('sequences longer than two keys strip everything before the last', () => {
  const step = advance('jk', 'l', ['jkl'])
  assert.equal(step.escaped, true)
  assert.equal(step.strip, 2)
})

test('several sequences can be live at once', () => {
  const sequences = ['jk', 'kj']
  assert.equal(advance('', 'k', sequences).pending, 'k')
  assert.equal(advance('k', 'j', sequences).escaped, true)
  assert.equal(advance('j', 'k', sequences).escaped, true)
})

test('no sequences means every key types', () => {
  assert.equal(advance('', 'j', []).escaped, false)
  assert.equal(advance('j', 'k', []).escaped, false)
  assert.equal(advance('j', 'k', undefined).escaped, false)
})

test('only printable keys build a sequence', () => {
  assert.equal(isTypedKey('j'), true)
  assert.equal(isTypedKey(' '), true)
  assert.equal(isTypedKey('\u001b'), false, 'Esc')
  assert.equal(isTypedKey('\b'), false, 'Backspace')
  assert.equal(isTypedKey('\u007f'), false, 'Delete')
  assert.equal(isTypedKey('jk'), false)
  assert.equal(advance('j', '\b', ['jk']).pending, '', 'Backspace drops the pending j')
})

test('an absent or unreadable config falls back to the defaults', () => {
  for (const source of ['', '   ', 'not json', '[1,2]', '"jk"']) {
    assert.deepEqual(readKeymap(source), {
      sequences: DEFAULT_SEQUENCES,
      timeoutMs: DEFAULT_TIMEOUT_MS
    }, `defaults for ${JSON.stringify(source)}`)
  }
  assert.deepEqual(readKeymap('{"exa_api_key": "x"}').sequences, DEFAULT_SEQUENCES,
    'an unrelated config keeps jk')
})

test('the config picks the sequence and the timeout', () => {
  assert.deepEqual(readKeymap('{"escape_sequence": "kj"}').sequences, ['kj'])
  assert.deepEqual(readKeymap('{"escape_sequence": ["jk", "kj"]}').sequences, ['jk', 'kj'])
  assert.equal(readKeymap('{"escape_timeout_ms": 500}').timeoutMs, 500)
})

test('the config can turn the sequence off', () => {
  for (const raw of ['""', 'null', '[]', 'false', '"j"']) {
    assert.deepEqual(readKeymap(`{"escape_sequence": ${raw}}`).sequences, [],
      `${raw} disables it — a single key would be untypable`)
  }
})

test('a nonsense timeout is clamped rather than obeyed', () => {
  assert.equal(readKeymap('{"escape_timeout_ms": 0}').timeoutMs, 20)
  assert.equal(readKeymap('{"escape_timeout_ms": -50}').timeoutMs, 20)
  assert.equal(readKeymap('{"escape_timeout_ms": 999999}').timeoutMs, 5000)
  assert.equal(readKeymap('{"escape_timeout_ms": "fast"}').timeoutMs, DEFAULT_TIMEOUT_MS)
})
