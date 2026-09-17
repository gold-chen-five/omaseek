import test from 'node:test'
import assert from 'node:assert/strict'
import { LIST_KEYS, ANSWER_KEYS, resolve, resolveCounted, readerKeys, bindingProblem } from '../src/lib/keys.mjs'
import { ACTIONS, settingKey } from '../src/lib/keybinds.mjs'
import { DEFAULTS } from '../src/lib/settings.mjs'

test('a bound chord is its command', () => {
  assert.deepEqual(resolve(LIST_KEYS, '', 'j'), { command: 'down', pending: '' })
  assert.deepEqual(resolve(LIST_KEYS, '', 'Down'), { command: 'down', pending: '' })
  assert.deepEqual(resolve(LIST_KEYS, '', 'C-d'), { command: 'halfPageDown', pending: '' })
})

test('reader panes return to the field with vim entry semantics', () => {
  for (const keys of [LIST_KEYS, ANSWER_KEYS]) {
    assert.equal(resolve(keys, 'g', 'i').command, 'insert', 'gi goes back typing')
    assert.equal(resolve(keys, 'g', 'n').command, 'fieldNormal', 'gn goes back in normal mode')
    assert.equal(resolve(keys, '', 'i').command, 'insert')
    assert.equal(resolve(keys, '', 'a').command, 'append')
    assert.equal(resolve(keys, '', 'Escape').command, 'cancel')
  }
})

test('/ searches the pane rather than going back to the field', () => {
  for (const keys of [LIST_KEYS, ANSWER_KEYS]) {
    assert.equal(resolve(keys, '', '/').command, 'findForward')
    assert.equal(resolve(keys, '', '?').command, 'findBackward')
    assert.equal(resolve(keys, '', 'n').command, 'findNext')
    assert.equal(resolve(keys, '', 'N').command, 'findPrevious')
  }
})

test('g waits for the second half, and gg is the top', () => {
  const first = resolve(LIST_KEYS, '', 'g')
  assert.deepEqual(first, { command: '', pending: 'g' })
  assert.deepEqual(resolve(LIST_KEYS, first.pending, 'g'), { command: 'top', pending: '' })
})

test('a sequence that goes nowhere is dropped, not left pending', () => {
  assert.deepEqual(resolve(LIST_KEYS, 'g', 'q'), { command: '', pending: '' })
  // gv reselects in the answer view; the list has no selection to restore.
  assert.deepEqual(resolve(LIST_KEYS, 'g', 'v'), { command: '', pending: '' })
  assert.deepEqual(resolve(ANSWER_KEYS, 'g', 'v'), { command: 'reselect', pending: '' })
})

test('a modifier on its own leaves the pending sequence alone', () => {
  // Reaching for shift halfway through a sequence must not cancel it: gA.
  assert.deepEqual(resolve(ANSWER_KEYS, 'g', ''), { command: '', pending: 'g' })
  assert.deepEqual(resolve(ANSWER_KEYS, '', ''), { command: '', pending: '' })
})

test('an unbound key clears whatever was pending', () => {
  assert.deepEqual(resolve(ANSWER_KEYS, '', 'Q'), { command: '', pending: '' })
})

test('q stops the reply being written in the answer, and means nothing in the results', () => {
  assert.equal(resolve(ANSWER_KEYS, '', 'q').command, 'stopAnswer')
  assert.equal(resolve(LIST_KEYS, '', 'q').command, '')
})

// The list's own, each for a reason: h and l page where the answer moves by
// character, and a row is one URL where a reply is text to operate on — so y
// there copies at once rather than waiting for a motion.
const LIST_ONLY = ['nextPage', 'previousPage', 'yankUrl', 'yankCitation', 'askAbout']

test('both panes agree on the keys they share; the rest are the list’s own', () => {
  for (const chord of Object.keys(LIST_KEYS)) {
    const command = LIST_KEYS[chord]
    if (LIST_ONLY.indexOf(command) !== -1) {
      assert.notEqual(ANSWER_KEYS[chord], command, `${chord} means this in the answer too`)
      continue
    }
    assert.equal(ANSWER_KEYS[chord], command, `${chord} means two things`)
  }
})

test('y copies a result at once, but still opens a yank in the answer', () => {
  assert.equal(LIST_KEYS['y'], 'yankUrl')
  assert.equal(ANSWER_KEYS['y'], 'yank')
  assert.equal(LIST_KEYS['Y'], 'yankCitation')
  assert.equal(ANSWER_KEYS['Y'], undefined, 'the answer leaves Y alone')
})

test('each half reaches the other: gc asks about a result, gs searches for a reply or a result', () => {
  assert.equal(resolve(LIST_KEYS, 'g', 'c').command, 'askAbout')
  assert.equal(resolve(ANSWER_KEYS, 'g', 'c').command, '', 'the answer has no result to ask about')
  assert.equal(resolve(ANSWER_KEYS, 'g', 's').command, 'searchFor')
  assert.equal(resolve(LIST_KEYS, 'g', 's').command, 'searchFor', 'a result’s title, searched in its own right')
})

test('hand-off is ga and everything is gA, the same in both panes', () => {
  for (const keys of [LIST_KEYS, ANSWER_KEYS]) {
    assert.equal(resolve(keys, 'g', 'a').command, 'handOff')
    assert.equal(resolve(keys, 'g', 'A').command, 'handOffPage')
    assert.equal(resolve(keys, '', 'C-Return').command, '', 'no second, different spelling')
  }
})

test('the answer view adds motions and a selection', () => {
  assert.equal(resolve(ANSWER_KEYS, '', 'w').command, 'wordForward')
  assert.equal(resolve(ANSWER_KEYS, '', 'W').command, 'wordForwardBig')
  assert.equal(resolve(ANSWER_KEYS, '', '$').command, 'lineEnd')
  assert.equal(resolve(ANSWER_KEYS, '', 'V').command, 'selectLines')
  assert.equal(resolve(ANSWER_KEYS, '', 'y').command, 'yank')
  assert.equal(resolve(ANSWER_KEYS, '', 'l').command, 'right')
  // The list has none of them, so its keys stay free for later.
  assert.equal(resolve(LIST_KEYS, '', 'w').command, '')
  assert.equal(resolve(LIST_KEYS, '', 'l').command, 'nextPage')
  assert.equal(resolve(LIST_KEYS, '', 'Right').command, 'nextPage')
})

test('escape and enter are named keys, not their control characters', () => {
  assert.equal(resolve(LIST_KEYS, '', 'Escape').command, 'cancel')
  assert.equal(resolve(LIST_KEYS, '', 'Return').command, 'accept')
  assert.equal(resolve(LIST_KEYS, '', '\r').command, '')
})

test('gx opens a link in the answer; the list has no links to open', () => {
  assert.deepEqual(resolve(ANSWER_KEYS, '', 'g'), { command: '', pending: 'g' })
  assert.equal(resolve(ANSWER_KEYS, 'g', 'x').command, 'openLink')
  assert.equal(resolve(LIST_KEYS, 'g', 'x').command, '')
})

test('E reaches the end of a WORD in the answer, so vE selects a whole URL', () => {
  assert.equal(resolve(ANSWER_KEYS, '', 'E').command, 'wordEndBig')
})

function counted (chords) {
  let state = { pending: '', count: 0 }
  let step
  for (const chord of chords) {
    step = resolveCounted(LIST_KEYS, state, chord)
    state = step.state
  }
  return step
}

test('result navigation accepts multi-digit counts and resets after movement', () => {
  assert.equal(counted(['2', 'j']).command, 'down')
  assert.equal(counted(['2', 'j']).count, 2)
  assert.equal(counted(['1', '0', 'Up']).count, 10)
  assert.equal(counted(['2', 'C-d']).count, 2)
  assert.equal(counted(['2', 'j', 'k']).count, 1)
  assert.equal(counted(['2', '', 'j']).count, 2)
})

test('result counts cancel on escape and unknown keys without leaking into the next move', () => {
  assert.equal(counted(['2', 'Escape']).command, '')
  assert.equal(counted(['2', 'Escape', 'j']).count, 1)
  assert.equal(counted(['2', 'q', 'j']).count, 1)
  assert.equal(counted(['Escape']).command, 'cancel')
  assert.equal(counted(['g', 'Escape']).command, '')
  assert.equal(counted(['g', 'g']).command, 'top')
  assert.equal(counted(['G']).command, 'bottom')
})

test('a rebound key moves its command in both panes and frees the old key', () => {
  const binds = { ...DEFAULTS, handoffKey: 'ctrl+h', handoffAllKey: 'gt', openLinkKey: 'ctrl+o', nextPageKey: 'm' }
  for (const pane of ['results', 'answer']) {
    const keys = readerKeys(pane, binds)
    assert.equal(resolve(keys, '', 'C-h').command, 'handOff')
    assert.equal(resolve(keys, 'g', 't').command, 'handOffPage')
    assert.equal(resolve(keys, 'g', 'a').command, '')
    assert.equal(resolve(keys, 'g', 'A').command, '')
  }
  assert.equal(resolve(readerKeys('answer', binds), '', 'C-o').command, 'openLink')
  assert.equal(resolve(readerKeys('answer', binds), 'g', 'x').command, '')
  assert.equal(resolve(readerKeys('results', binds), '', 'm').command, 'nextPage')
  assert.equal(resolve(readerKeys('results', binds), '', 'l').command, '', 'l is free once paging moves')
  assert.equal(resolve(readerKeys('results', binds), '', 'Right').command, 'nextPage', 'the arrow stays')
})

test('an unreadable binding falls back to the default rather than vanishing', () => {
  const keys = readerKeys('results', { ...DEFAULTS, handoffKey: 'nonsense' })
  assert.equal(resolve(keys, 'g', 'a').command, 'handOff')
})

test('fixed reader keys survive a colliding persisted binding', () => {
  const keys = readerKeys('results', { ...DEFAULTS, nextPageKey: 'a' })
  assert.equal(resolve(keys, '', 'a').command, 'append')
})

test('no two default keys collide', () => {
  for (const action of ACTIONS) {
    assert.equal(bindingProblem(action.id, action.default, DEFAULTS), '', action.id)
  }
})

test('a key already taken is refused with what takes it', () => {
  assert.match(bindingProblem('handoff', 'gx', DEFAULTS), /Open link/)
  assert.match(bindingProblem('handoff', 'gg', DEFAULTS), /the top/)
  assert.match(bindingProblem('handoff', 'g', DEFAULTS), /the top/, 'g alone would swallow gg')
  assert.match(bindingProblem('handoff', 'f', DEFAULTS), /vim uses f/)
  assert.match(bindingProblem('handoff', '3', DEFAULTS), /count/)
  assert.match(bindingProblem('nextPage', 'j', DEFAULTS), /move down/)
  assert.match(bindingProblem('openLink', 'l', DEFAULTS), /move right/)
  assert.match(bindingProblem('nextPage', 'a', DEFAULTS), /insert after/)
  assert.match(bindingProblem('settings', 'ctrl+w', DEFAULTS), /delete a word/)
  assert.match(bindingProblem('settings', 'ctrl+d', DEFAULTS), /half a screen/)
  assert.match(bindingProblem('newSession', 'ctrl+s', DEFAULTS), /Settings/)
})

test('keys in panes that never meet may share a key', () => {
  // Enter searches from the field and opens from the lists; paging is only
  // the list's, so the answer's l does not stand in its way.
  assert.equal(bindingProblem('search', 'enter', DEFAULTS), '')
  assert.equal(bindingProblem('open', 'enter', DEFAULTS), '')
  assert.equal(bindingProblem('nextPage', 'l', DEFAULTS), '')
  assert.equal(bindingProblem('handoff', 'ctrl+h', DEFAULTS), '')
})

test('keys the field would type are refused for the keys it catches', () => {
  assert.match(bindingProblem('settings', 's', DEFAULTS), /could never be typed/)
  assert.match(bindingProblem('handoff', 'xyz', DEFAULTS), /not a key/)
})

test('a binding is checked against the others as they are now, not the defaults', () => {
  const binds = { ...DEFAULTS, [settingKey(ACTIONS.find(a => a.id === 'openLink'))]: 'go' }
  assert.equal(bindingProblem('handoff', 'gx', binds), '', 'gx was freed')
  assert.match(bindingProblem('handoff', 'go', binds), /Open link/)
})

test('the answer pane walks and closes sessions through its own table', () => {
  const keys = readerKeys('answer', DEFAULTS)
  assert.equal(resolve(keys, '', 'C-n').command, 'nextSession')
  assert.equal(resolve(keys, '', 'C-x').command, 'closeSession')
  // Rebinding moves it there too, and the old chord goes back to nothing.
  const moved = readerKeys('answer', { ...DEFAULTS, nextSessionKey: 'ctrl+o' })
  assert.equal(resolve(moved, '', 'C-o').command, 'nextSession')
  assert.equal(resolve(moved, '', 'C-n').command, '')
})

test('the session keys are refused where they would collide', () => {
  assert.match(bindingProblem('nextSession', 'ctrl+x', DEFAULTS), /Close session/)
  assert.match(bindingProblem('closeSession', 'ctrl+u', DEFAULTS), /delete to the line start|half a screen/)
  assert.equal(bindingProblem('nextSession', 'ctrl+n', DEFAULTS), '', 'its own key is not a clash')
})

test('ctrl+shift+x forgets the lot, without standing on ctrl+x', () => {
  const keys = readerKeys('answer', DEFAULTS)
  assert.equal(resolve(keys, '', 'C-S-x').command, 'clearSessions')
  assert.equal(resolve(keys, '', 'C-x').command, 'closeSession', 'the plainer chord is untouched')
  assert.match(bindingProblem('clearSessions', 'ctrl+x', DEFAULTS), /Close session/)
  assert.equal(bindingProblem('clearSessions', 'ctrl+shift+x', DEFAULTS), '')
  assert.equal(bindingProblem('closeSession', 'ctrl+shift+c', DEFAULTS), '', 'shift makes a chord of its own')
})

test('gs searches from the results too, and gx stays the answer pane’s', () => {
  assert.equal(resolve(LIST_KEYS, 'g', 's').command, 'searchFor')
  assert.equal(resolve(ANSWER_KEYS, 'g', 's').command, 'searchFor')
  assert.equal(resolve(LIST_KEYS, 'g', 'x').command, '')
})
