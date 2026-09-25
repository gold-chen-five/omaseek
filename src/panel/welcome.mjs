// The intro page the panel opens on after install: the two things omaseek needs
// before it is useful, each with whether it is done and the buttons that do
// it. Pure and under test; WelcomePage.qml draws it, and the buttons run what
// Settings runs (bin/searxng-up, bin/keybind) in a terminal.

import { shortcutRow } from '../settings/rows.mjs'
import { DEFAULT_OPEN_KEY } from '../settings/hyprkey.mjs'

/**
 * The steps, as the page lists them. Each has `buttons`, [{ action, label }]:
 * `start` sets SearXNG up, `add` binds (or changes) the key, `rebind` opens
 * the field to type another key. None when done, checking, or not ours.
 */
export function welcomeSteps (engineState, shortcutStatus) {
  return [engineStep(engineState), keyStep(shortcutStatus)]
}

function engineStep (engineState) {
  const running = engineState === 'running'
  return {
    key: 'searxng',
    title: 'SearXNG, the search engine',
    detail: engineState === 'unknown' ? 'checking whether it is running…'
      : running ? 'running on this machine — searches go through it'
      : 'runs on your own machine, in Podman or Docker. Set up opens a terminal: the first run downloads about 200 MB, and Docker may ask for your password',
    done: running,
    buttons: engineState === 'stopped' ? [{ action: 'start', label: 'Set up' }] : []
  }
}

function keyStep (status) {
  const state = status && status.ok ? status.state : status ? 'unreadable' : 'checking'
  const key = status && status.key ? status.key : DEFAULT_OPEN_KEY
  const step = { key: 'shortcut', title: key + ', to open omaseek from anywhere', done: false, buttons: [] }
  const holderName = /"[^"]*"\s*,\s*"([^"]*)"/.exec(status && status.holder ? status.holder : '')
  const holder = holderName ? holderName[1] : 'something else'
  if (state === 'bound') {
    step.done = true
    if (status.managed !== true) {
      step.detail = 'a line you wrote in your Hyprland bindings — change the key there'
      return step
    }
    // Asked about another key while one is bound: offer the change, if it is free.
    if (status.wanted) {
      step.detail = status.holder ? `${status.wanted} already opens ${holder} — choose another key`
        : `change it to ${status.wanted}? A terminal shows the change and asks`
      step.buttons = status.holder ? [{ action: 'rebind', label: 'Change key' }]
        : [{ action: 'add', label: 'Change to ' + status.wanted }, { action: 'rebind', label: 'Change key' }]
      return step
    }
    step.detail = 'in your Hyprland bindings'
    step.buttons = [{ action: 'rebind', label: 'Change key' }]
    return step
  }
  if (state === 'free') {
    step.detail = 'Add opens a terminal that shows the line, asks, and backs up your bindings first'
    step.buttons = [{ action: 'add', label: 'Add' }, { action: 'rebind', label: 'Change key' }]
    return step
  }
  if (state === 'taken') {
    step.detail = `${key} already opens ${holder} — choose another key`
    step.buttons = [{ action: 'rebind', label: 'Choose a key' }]
    return step
  }
  step.detail = shortcutRow(status).hint
  return step
}

/** The actions the keys walk, in order: each step's buttons, then Start. */
export function welcomeButtons (steps) {
  const buttons = []
  for (let i = 0; i < steps.length; i++) {
    for (let j = 0; j < steps[i].buttons.length; j++) buttons.push(steps[i].buttons[j].action)
  }
  buttons.push('finish')
  return buttons
}
