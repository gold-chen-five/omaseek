import test from 'node:test'
import assert from 'node:assert/strict'
import { terminalEnding, summonCommand } from '../src/shared/terminal.mjs'

test('a terminal waits for a key, and from the welcome page brings the panel back after it', () => {
  assert.equal(terminalEnding(''), "echo; read -n1 -r -p 'press any key to close'")
  assert.equal(terminalEnding(undefined), "echo; read -n1 -r -p 'press any key to close'")
  assert.equal(terminalEnding("omarchy-shell shell summon omaseek '{}'"),
    "echo; read -n1 -r -p 'press any key to go back to omaseek'; omarchy-shell shell summon omaseek '{}'")
})

test('the panel is summoned by its plugin id, and nothing else reaches the shell line', () => {
  assert.equal(summonCommand('omaseek'), "omarchy-shell shell summon omaseek '{}'")
  assert.equal(summonCommand('io.github.me.omaseek'), "omarchy-shell shell summon io.github.me.omaseek '{}'")
  assert.equal(summonCommand('x; rm -rf ~'), "omarchy-shell shell summon xrm-rf '{}'")
  assert.equal(summonCommand(''), '')
})
