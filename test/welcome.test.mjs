import test from 'node:test'
import assert from 'node:assert/strict'
import { welcomeSteps, welcomeButtons } from '../src/panel/welcome.mjs'
import { VIEW } from '../src/shared/states.mjs'
import { statusText, modeLabel } from '../src/search/search.mjs'

const free = { ok: true, state: 'free', key: 'SUPER + d' }
const bound = { ok: true, state: 'bound', key: 'SUPER + d', managed: true }
const actions = step => step.buttons.map(button => button.action)

test('a fresh machine has both steps to do, the key with Add and Change key, then Start', () => {
  const steps = welcomeSteps('stopped', free)
  assert.deepEqual(steps.map(step => [step.key, step.done]), [['searxng', false], ['shortcut', false]])
  assert.match(steps[0].detail, /200 MB/)
  assert.equal(steps[1].title, 'SUPER + d, to open omaseek from anywhere')
  assert.deepEqual(welcomeButtons(steps), ['start', 'add', 'rebind', 'finish'])
})

test('a step already done offers only what can still change: the key omaseek wrote', () => {
  const steps = welcomeSteps('running', bound)
  assert.deepEqual(steps.map(step => step.done), [true, true])
  assert.deepEqual(welcomeButtons(steps), ['rebind', 'finish'])
  const byHand = welcomeSteps('running', { ...bound, managed: false })
  assert.deepEqual(actions(byHand[1]), [], 'a line the user wrote is theirs to change')
  assert.match(byHand[1].detail, /a line you wrote/)
})

test('another key asked for while one is bound: the change when it is free, another choice when not', () => {
  const change = welcomeSteps('running', { ...bound, wanted: 'SUPER + s' })[1]
  assert.deepEqual(change.buttons.map(button => button.label), ['Change to SUPER + s', 'Change key'])
  const taken = welcomeSteps('running', { ...bound, wanted: 'SUPER + SPACE', holder: 'o.bind("SUPER + SPACE", "Launcher", "walker")' })[1]
  assert.deepEqual(actions(taken), ['rebind'])
  assert.match(taken.detail, /SUPER \+ SPACE already opens Launcher/)
})

test('while checking there is nothing to press, and a taken key asks for another', () => {
  const steps = welcomeSteps('unknown', null)
  assert.deepEqual(steps.map(actions), [[], []])
  assert.match(steps[0].detail, /checking/)
  const taken = welcomeSteps('running', { ok: true, state: 'taken', key: 'SUPER + d', holder: 'o.bind("SUPER + D", "Dictation", "x")' })
  assert.deepEqual(actions(taken[1]), ['rebind'])
  assert.match(taken[1].detail, /already opens Dictation/)
})

test('the page has its own mode label and key hints', () => {
  assert.equal(modeLabel({ view: VIEW.WELCOME }), 'WELCOME')
  assert.match(statusText({ view: VIEW.WELCOME }), /esc starts searching/)
})
