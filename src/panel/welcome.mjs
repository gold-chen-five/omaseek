// The intro page the panel opens on after install: the two things omaseek needs
// before it is useful, each with whether it is done and the button that does
// it. Pure and under test; WelcomePage.qml draws it, and the buttons run what
// Settings runs (bin/searxng-up, bin/keybind) in a terminal.

import { shortcutRow } from '../settings/rows.mjs'

/**
 * The steps, as the page lists them: `action` is what the button does, '' when
 * there is nothing to do (done, still checking, or not ours to fix).
 */
export function welcomeSteps (engineState, shortcutStatus) {
  const running = engineState === 'running'
  const key = shortcutStatus && shortcutStatus.key ? shortcutStatus.key : 'SUPER + D'
  const keyState = shortcutStatus && shortcutStatus.ok ? shortcutStatus.state : shortcutStatus ? 'unreadable' : 'checking'
  return [
    {
      key: 'searxng',
      title: 'SearXNG, the search engine',
      detail: engineState === 'unknown' ? 'checking whether it is running…'
        : running ? 'running on this machine — searches go through it'
        : 'runs on your own machine, in Docker. Set up opens a terminal: the first run downloads about 200 MB and may ask for your password',
      done: running,
      action: engineState === 'stopped' ? 'start' : '',
      button: 'Set up'
    },
    {
      key: 'shortcut',
      title: key + ', to open omaseek from anywhere',
      detail: keyState === 'bound' ? 'in your Hyprland bindings'
        : keyState === 'free' ? 'Add opens a terminal that shows the line, asks, and backs up your bindings first'
        : shortcutRow(shortcutStatus).hint,
      done: keyState === 'bound',
      action: keyState === 'free' ? 'add' : '',
      button: 'Add'
    }
  ]
}

/** The buttons the keys walk, in order: each step with something to do, then Start. */
export function welcomeButtons (steps) {
  const buttons = []
  for (let i = 0; i < steps.length; i++) if (steps[i].action) buttons.push(steps[i].action)
  buttons.push('finish')
  return buttons
}
