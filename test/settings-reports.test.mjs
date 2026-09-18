// What the SearXNG rows say after running something: the engines test, a timed
// search, and the version check.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  readSettings, writeSettings, settingsRows, cycle, normalizeSequence, ENGINE_STATES,
  LAUNCHER_CHOICES, DEFAULT_AGENT,
  PAGE_SIZE_CHOICES, DEFAULTS, checkRow, FIXED_KEYS, changeSetting, selectedModel,
  ENGINE_CHOICES, DEFAULT_ENGINES, LANGUAGE_CHOICES, toggleEngine, endpointTestText, searchSpeedText, versionText, nextAgent, translateAgentOf, SAME_AS_ASK
} from '../src/settings/settings.mjs'
import { ACTIONS, settingKey } from '../src/vim/keybinds.mjs'
import { DEFAULT_TIMEOUT_MS } from '../src/vim/keymap.mjs'

test('the endpoint test is an action row whose hint is what the test found', () => {
  const row = test => settingsRows(readSettings(''), 'running', null, null, test).find(r => r.key === 'engineTest')
  assert.equal(row(null).type, 'action')
  assert.equal(row(null).action, 'test')
  assert.equal(row({ running: true }).busy, true)
  assert.equal(row({
    ok: true,
    ms: 1486,
    engines: { brave: { rows: 20, ms: 630 }, bing: { rows: 10, ms: 194 }, google: { rows: 0, ms: 3, reason: 'Suspended: CAPTCHA' } },
    unresponsive: [{ engine: 'google', reason: 'Suspended: CAPTCHA' }]
  }).hint,
  'brave 20 in 630 ms · bing 10 in 194 ms · google 0 in 3 ms (CAPTCHA)',
  'a blocked engine keeps its count and time, and says why in brackets')
  assert.equal(endpointTestText({ ok: true, ms: 312, engines: { brave: 20 }, unresponsive: [{ engine: 'google', reason: 'CAPTCHA' }] }),
    'brave 20 · google: CAPTCHA', 'counts alone, as an older --test printed them')
  assert.equal(endpointTestText({ ok: false, message: 'SearXNG is not reachable' }), 'SearXNG is not reachable')
  assert.equal(endpointTestText({ ok: true, ms: 5, engines: {}, unresponsive: [] }), 'no rows')
})

test('the search-speed row times one real search, as a keypress sends it', () => {
  const row = speed => settingsRows(readSettings(''), 'running', null, null, null, null, speed)
    .find(r => r.key === 'engineSpeed')
  assert.match(row(null).hint, /every engine at once/, 'before a run it says what the button does')
  assert.equal(row({ running: true }).busy, true)
  assert.equal(row({ ok: true, ms: 848, rows: 28, unresponsive: [] }).hint, '848 ms for 28 rows')
  assert.equal(row({ ok: true, ms: 720, rows: 18, unresponsive: [{ engine: 'google', reason: 'Suspended: CAPTCHA' }] }).hint,
    '720 ms for 18 rows · google: Suspended: CAPTCHA')
  assert.equal(searchSpeedText({ ok: false, message: 'SearXNG is not reachable' }), 'SearXNG is not reachable')
})

test('the update row says which version runs and whether a newer one exists', () => {
  const hint = version => settingsRows(readSettings(''), 'running', null, null, null, version)
    .find(r => r.key === 'engineUpdate').hint
  assert.match(hint(null), /pull the latest image/, 'before a check it says what the button does')
  assert.equal(hint({ checking: true }), 'checking the running version…')
  assert.equal(hint({ ok: true, version: '2026.9.16+461f174b0', latest: '2026.9.16-461f174b0', current: true }),
    '2026.9.16 — the latest')
  assert.equal(hint({ ok: true, version: '2026.9.8+3fdc6d753', latest: '2026.9.16-461f174b0', current: false }),
    '2026.9.8 running · 2026.9.16 available — update')
  assert.equal(versionText({ ok: true, version: '2026.9.8+3fdc6d753', latest: null, current: null }),
    '2026.9.8 running · could not check for a newer one')
  assert.equal(versionText({ ok: false, error: 'network', setup: true }), 'not running — start it to see its version')
})
