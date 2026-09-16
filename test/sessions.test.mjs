import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  MAX_SESSIONS, readSessions, writeSessions, record, removeSession, stepSession,
  sessionTitle, sessionLabel, isAnswered, indexOfSession, newId,
  stoppedTurn, endsStopped, retryPoint, promptTurns
} from '../src/lib/sessions.mjs'

const turns = question => [{ role: 'user', text: question }, { role: 'assistant', text: 'because.' }]

function ring (count) {
  let sessions = []
  for (let i = 0; i < count; i++) {
    sessions = record(sessions, -1, turns('question ' + i), 'claude', 1000 + i).sessions
  }
  return sessions
}

test('a conversation is named by its first question', () => {
  assert.equal(sessionTitle(turns('why is the sky blue')), 'why is the sky blue')
  assert.equal(sessionTitle([{ role: 'assistant', text: 'hi' }]), 'Empty conversation')
  assert.equal(sessionTitle([{ role: 'user', text: ' two\nlines  here ' }]), 'two lines here')
  assert.ok(sessionTitle([{ role: 'user', text: 'x'.repeat(200) }]).length <= 60)
})

test('recording a new conversation puts it at the front and keeps ten', () => {
  const sessions = ring(MAX_SESSIONS + 3)
  assert.equal(sessions.length, MAX_SESSIONS)
  assert.equal(sessions[0].title, 'question 12', 'newest first')
  assert.equal(sessions[MAX_SESSIONS - 1].title, 'question 3', 'the oldest three fell off')
})

test('a conversation being answered into keeps its place and its id', () => {
  const first = record([], -1, turns('one'), 'claude', 10)
  const second = record(first.sessions, -1, turns('two'), 'claude', 20)
  const again = record(second.sessions, 1, turns('one').concat([{ role: 'user', text: 'more' }]), 'claude', 30)

  assert.equal(again.index, 1)
  assert.equal(again.sessions.length, 2)
  assert.equal(again.sessions[1].id, first.sessions[0].id)
  assert.equal(again.sessions[1].turns.length, 3)
  assert.equal(again.sessions[1].updated, 30)
})

test('an empty conversation is never recorded', () => {
  const step = record(ring(2), -1, [], '', 40)
  assert.equal(step.sessions.length, 2)
  assert.equal(step.index, -1)
})

test('the next session walks towards the older ones and wraps', () => {
  const sessions = ring(3)
  assert.equal(stepSession(sessions, -1, 1), 0, 'an unsaved conversation steps to the newest')
  assert.equal(stepSession(sessions, 0, 1), 1)
  assert.equal(stepSession(sessions, 2, 1), 0)
  assert.equal(stepSession(sessions, 0, -1), 2)
  assert.equal(stepSession([], -1, 1), -1, 'nothing saved, nowhere to go')
  assert.equal(stepSession(ring(1), 0, 1), 0, 'the only one stays')
})

test('removing shows the one that takes its place, and the last leaves nothing', () => {
  const sessions = ring(3)
  const middle = removeSession(sessions, 1)
  assert.equal(middle.sessions.length, 2)
  assert.equal(middle.index, 1, 'the one below moved up into the cursor')
  assert.equal(middle.sessions[1].title, 'question 0')

  const last = removeSession(middle.sessions, 1)
  assert.equal(last.index, 0, 'removing the oldest steps back')

  assert.equal(removeSession(last.sessions, 0).index, -1)
  assert.equal(removeSession(sessions, -1).sessions.length, 3, 'an unsaved conversation removes nothing')
})

test('the file round-trips, and an unreadable one is no conversations', () => {
  const sessions = ring(2)
  const restored = readSessions(writeSessions(sessions))
  assert.deepEqual(restored, sessions)
  assert.deepEqual(readSessions(''), [])
  assert.deepEqual(readSessions('{not json'), [])
  assert.deepEqual(readSessions('null'), [])
  assert.deepEqual(readSessions('{"sessions":{}}'), [])
})

test('a hand-edited file is repaired rather than trusted', () => {
  const sessions = readSessions(JSON.stringify({
    sessions: [
      { turns: [{ role: 'user', text: 'kept' }, { role: 'nonsense', text: 'dropped' }] },
      { turns: [] },
      { title: 'no turns at all' },
      'not an object'
    ]
  }))
  assert.equal(sessions.length, 1)
  assert.equal(sessions[0].turns.length, 1)
  assert.equal(sessions[0].title, 'kept', 'a missing title is derived')
  assert.equal(sessions[0].updated, 0)
  assert.ok(sessions[0].id)
})

test('more than ten in the file are cut to ten on the way in and out', () => {
  const many = { sessions: [] }
  for (let i = 0; i < 14; i++) many.sessions.push({ turns: turns('q' + i) })
  assert.equal(readSessions(JSON.stringify(many)).length, MAX_SESSIONS)
  assert.equal(JSON.parse(writeSessions(readSessions(JSON.stringify(many)))).sessions.length, MAX_SESSIONS)
})

test('the status line names where in the ring the reader is', () => {
  assert.equal(sessionLabel(1, 3), 'session 2/3')
  assert.equal(sessionLabel(-1, 3), '3 saved')
  assert.equal(sessionLabel(-1, 1), '1 saved')
  assert.equal(sessionLabel(-1, 0), '')
  assert.equal(sessionLabel(0, 0), '')
})

test('a conversation counts as answered only once a reply lands', () => {
  assert.equal(isAnswered([{ role: 'user', text: 'in flight' }]), false)
  assert.equal(isAnswered([{ role: 'user', text: 'q' }, { role: 'error', text: 'the agent failed' }]), false)
  assert.equal(isAnswered(turns('q')), true)
  assert.equal(isAnswered([]), false)
  assert.equal(isAnswered(undefined), false)
})

test('a conversation can be given its id, so an answer still coming knows where home is', () => {
  const first = record([], -1, turns('one'), 'claude', 10, 'chosen-id')
  assert.equal(first.sessions[0].id, 'chosen-id')

  // The id belongs to the conversation, not to the write: answering it later
  // must not rename it.
  const again = record(first.sessions, 0, turns('one').concat([{ role: 'user', text: 'more' }]), 'claude', 20, 'something-else')
  assert.equal(again.sessions[0].id, 'chosen-id')

  assert.notEqual(record([], -1, turns('q'), '', 30).sessions[0].id, undefined, 'without one it still gets an id')
  assert.notEqual(newId(1), newId(1))
})

test('a conversation is found by id, wherever the ring has moved it', () => {
  const sessions = record(record([], -1, turns('older'), '', 10).sessions, -1, turns('newer'), '', 20).sessions
  assert.equal(indexOfSession(sessions, sessions[1].id), 1)
  assert.equal(indexOfSession(sessions, sessions[0].id), 0)
  assert.equal(indexOfSession(sessions, 'gone'), -1)
  assert.equal(indexOfSession(sessions, ''), -1, 'a conversation with no id is not the first one')
  assert.equal(indexOfSession(null, 'x'), -1)
})

test('stopping keeps the words so far as a marked reply, or says nothing had arrived', () => {
  assert.deepEqual(stoppedTurn('  half an answer '), { role: 'assistant', text: 'half an answer', stopped: true })
  const empty = stoppedTurn('')
  assert.equal(empty.role, 'error')
  assert.equal(empty.stopped, true)
  assert.equal(endsStopped([{ role: 'user', text: 'q' }, empty]), true)
  assert.equal(endsStopped([{ role: 'user', text: 'q' }, { role: 'error', text: 'boom' }]), false, 'a failure was not a decision')
})

test('the stopped mark survives the file, and nothing else rides along', () => {
  const turns = [{ role: 'user', text: 'q' }, { role: 'assistant', text: 'so far', stopped: true, junk: 1 }]
  const back = readSessions(writeSessions(record([], -1, turns, 'claude', 1).sessions))[0].turns
  assert.deepEqual(back, [{ role: 'user', text: 'q' }, { role: 'assistant', text: 'so far', stopped: true }])
})

test('a retry starts at the last question when only failures or a stop follow it', () => {
  const q = text => ({ role: 'user', text })
  const a = text => ({ role: 'assistant', text })
  assert.equal(retryPoint([q('1'), a('one'), q('2'), { role: 'error', text: 'quota' }]), 2)
  assert.equal(retryPoint([q('1'), a('one'), q('2'), stoppedTurn('half')]), 2)
  assert.equal(retryPoint([q('1'), stoppedTurn(''), { role: 'error', text: 'again' }]), 0)
  assert.equal(retryPoint([q('1'), a('one'), q('2')]), 2, 'a question the shell lost mid-answer')
  assert.equal(retryPoint([q('1'), a('one')]), -1, 'answered: nothing to retry')
  assert.equal(retryPoint([]), -1)
})

test('a prompt carries answered turns only, never a stopped half-reply', () => {
  const turns = [
    { role: 'user', text: '1' }, { role: 'assistant', text: 'one' },
    { role: 'user', text: '2' }, { role: 'assistant', text: 'tw', stopped: true },
    { role: 'user', text: '3' }, { role: 'error', text: 'boom' }
  ]
  assert.deepEqual(promptTurns(turns), [{ role: 'user', text: '1' }, { role: 'assistant', text: 'one' }])
})
