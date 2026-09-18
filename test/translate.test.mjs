import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  TRANSLATE_LANGUAGES, FOLLOW_SEARCH, defaultTarget, effectiveTarget, targetLabel, readTarget
} from '../src/translate/translate.mjs'

test('with nothing chosen, translations go into the language searches are made in', () => {
  assert.equal(defaultTarget('zh-TW'), 'zh-TW')
  assert.equal(defaultTarget('zh-CN'), 'zh-CN')
  assert.equal(defaultTarget('ja-JP'), 'ja', 'a region narrows to its language')
  assert.equal(defaultTarget('fr'), 'fr')
})

test('a search language that names none, or English, falls back to 繁體中文', () => {
  for (const code of ['default', 'auto', 'all', '', null, 'en', 'en-US', 'xx-YY']) {
    assert.equal(defaultTarget(code), 'zh-TW', String(code))
  }
})

test('a chosen target wins; following search is the default', () => {
  assert.equal(effectiveTarget({ translateLanguage: 'ja', searxngLanguage: 'zh-TW' }), 'ja')
  assert.equal(effectiveTarget({ translateLanguage: FOLLOW_SEARCH, searxngLanguage: 'ko-KR' }), 'ko')
  assert.equal(effectiveTarget({}), 'zh-TW')
  assert.equal(readTarget('nonsense'), FOLLOW_SEARCH, 'a typo follows search rather than guessing')
  assert.equal(readTarget('de'), 'de')
})

test('each target is named in its own script, and the codes match bin/ask', () => {
  assert.equal(targetLabel('zh-TW'), '繁體中文')
  assert.equal(targetLabel('en'), 'English')
  const codes = TRANSLATE_LANGUAGES.map(language => language.code)
  assert.deepEqual(codes, ['zh-TW', 'zh-CN', 'en', 'ja', 'ko', 'fr', 'de', 'es', 'it', 'pt', 'ru', 'vi', 'th'])
})
