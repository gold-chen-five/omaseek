import test from 'node:test'
import assert from 'node:assert/strict'
import { welcomeSteps, welcomeButtons } from '../src/panel/welcome.mjs'
import { VIEW } from '../src/shared/states.mjs'
import { statusText, modeLabel } from '../src/search/search.mjs'

const free = { ok: true, state: 'free', key: 'SUPER + D' }
const bound = { ok: true, state: 'bound', key: 'SUPER + D' }

test('a fresh machine has both steps to do, each with its button, then Start', () => {
  const steps = welcomeSteps('stopped', free)
  assert.deepEqual(steps.map(step => [step.key, step.done, step.action]), [['searxng', false, 'start'], ['shortcut', false, 'add']])
  assert.match(steps[0].detail, /200 MB/)
  assert.equal(steps[1].title, 'SUPER + D, to open omaseek from anywhere')
  assert.deepEqual(welcomeButtons(steps), ['start', 'add', 'finish'])
})

test('a step already done offers nothing, so the keys land on Start', () => {
  const steps = welcomeSteps('running', bound)
  assert.deepEqual(steps.map(step => step.done), [true, true])
  assert.deepEqual(welcomeButtons(steps), ['finish'])
})

test('while checking, or when the key is taken, there is no button to press', () => {
  const steps = welcomeSteps('unknown', null)
  assert.deepEqual(steps.map(step => step.action), ['', ''])
  assert.match(steps[0].detail, /checking/)
  const taken = welcomeSteps('running', { ok: true, state: 'taken', key: 'SUPER + D', holder: 'o.bind("SUPER + D", "Dictation", "x")' })
  assert.equal(taken[1].action, '')
  assert.match(taken[1].detail, /already opens Dictation/)
})

test('the page has its own mode label and key hints', () => {
  assert.equal(modeLabel({ view: VIEW.WELCOME }), 'WELCOME')
  assert.match(statusText({ view: VIEW.WELCOME }), /esc starts searching/)
})
