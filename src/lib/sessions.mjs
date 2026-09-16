// The saved AI conversations: a ring of at most ten, newest first, and the
// rules for recording, walking and forgetting one. Pure and under test; the
// file itself is read and written by components/SessionStore.qml.
//
// A conversation keeps the place it was given, so that walking the ring with
// the next-session key stays predictable while it is answered into; `updated`
// records when it last moved, for anyone reading the file.

export const MAX_SESSIONS = 10
export const TITLE_LENGTH = 60

const ROLES = ['user', 'assistant', 'error']

function asText (value) {
  return typeof value === 'string' ? value : ''
}

function asTurns (value) {
  const turns = []
  if (!value || !Array.isArray(value)) return turns
  for (let i = 0; i < value.length; i++) {
    const turn = value[i]
    if (!turn || typeof turn !== 'object') continue
    if (ROLES.indexOf(turn.role) === -1) continue
    turns.push({ role: turn.role, text: asText(turn.text) })
  }
  return turns
}

/** A conversation's name: its first question, on one line and cut short. */
export function sessionTitle (turns) {
  const list = asTurns(turns)
  for (let i = 0; i < list.length; i++) {
    if (list[i].role !== 'user') continue
    const line = list[i].text.replace(/\s+/g, ' ').trim()
    if (!line) continue
    return line.length > TITLE_LENGTH ? line.slice(0, TITLE_LENGTH - 1) + '…' : line
  }
  return 'Empty conversation'
}

// Unique enough to tell two conversations apart in the file, and to address one
// whose answer is still on its way; nothing reads it back as a key.
export function newId (now) {
  return String(now) + '-' + Math.random().toString(36).slice(2, 8)
}

/** File text -> the conversations it holds; anything unreadable is no conversations. */
export function readSessions (source) {
  let parsed = null
  if (typeof source === 'string' && source.trim() !== '') {
    try {
      parsed = JSON.parse(source)
    } catch (error) {
      parsed = null
    }
  }
  const list = parsed && Array.isArray(parsed.sessions) ? parsed.sessions : []
  const sessions = []
  for (let i = 0; i < list.length && sessions.length < MAX_SESSIONS; i++) {
    const entry = list[i]
    if (!entry || typeof entry !== 'object') continue
    const turns = asTurns(entry.turns)
    if (turns.length === 0) continue           // an empty conversation is not one
    sessions.push({
      id: asText(entry.id) || newId(Date.now()),
      title: asText(entry.title) || sessionTitle(turns),
      agent: asText(entry.agent),
      updated: typeof entry.updated === 'number' ? entry.updated : 0,
      turns: turns
    })
  }
  return sessions
}

/** The conversations -> the file's text. */
export function writeSessions (sessions) {
  const list = sessions && Array.isArray(sessions) ? sessions.slice(0, MAX_SESSIONS) : []
  return JSON.stringify({ version: 1, sessions: list }, null, 2) + '\n'
}

/**
 * The live conversation written back into the ring: in place when it already
 * has a place, otherwise at the front, dropping the oldest past ten. Returns
 * the ring and where the live conversation now sits.
 */
export function record (sessions, index, turns, agent, now, id) {
  const kept = sessions && Array.isArray(sessions) ? sessions.slice(0) : []
  const live = asTurns(turns)
  if (live.length === 0) return { sessions: kept, index: index }

  const existing = index >= 0 && index < kept.length ? kept[index] : null
  const entry = {
    // A conversation keeps the id it was given: an answer still on its way is
    // addressed by it, so the ring must not rename it underneath.
    id: existing ? existing.id : (id || newId(now)),
    title: sessionTitle(live),
    agent: asText(agent),
    updated: now,
    turns: live
  }
  if (existing) {
    kept[index] = entry
    return { sessions: kept, index: index }
  }
  kept.unshift(entry)
  if (kept.length > MAX_SESSIONS) kept.length = MAX_SESSIONS
  return { sessions: kept, index: 0 }
}

/**
 * Whether a conversation was ever answered. One that was not is a question in
 * flight: worth keeping while it runs, not worth a square once it is walked
 * away from.
 */
export function isAnswered (turns) {
  const list = turns || []
  for (let i = 0; i < list.length; i++) if (list[i].role === 'assistant') return true
  return false
}

/** The ring without conversation `index`, and which one takes its place (-1 when none is left). */
export function removeSession (sessions, index) {
  const kept = sessions && Array.isArray(sessions) ? sessions.slice(0) : []
  if (index < 0 || index >= kept.length) return { sessions: kept, index: index }
  kept.splice(index, 1)
  return { sessions: kept, index: kept.length === 0 ? -1 : Math.min(index, kept.length - 1) }
}

/** Where conversation `id` sits in the ring, or -1. */
export function indexOfSession (sessions, id) {
  const list = sessions && Array.isArray(sessions) ? sessions : []
  if (!id) return -1
  for (let i = 0; i < list.length; i++) if (list[i].id === id) return i
  return -1
}

/**
 * Where the next-session key lands from `index`, wrapping. An unsaved
 * conversation (-1) steps to the newest saved one, so one keypress reaches the
 * last thing that was asked. -1 when nothing is saved.
 */
export function stepSession (sessions, index, delta) {
  const count = sessions && Array.isArray(sessions) ? sessions.length : 0
  if (count === 0) return -1
  if (index < 0 || index >= count) return delta < 0 ? count - 1 : 0
  return ((index + delta) % count + count) % count
}

/** What the status line says about the ring: "session 2/3", "3 saved", or ''. */
export function sessionLabel (index, count) {
  if (!count) return ''
  if (index < 0 || index >= count) return count === 1 ? '1 saved' : count + ' saved'
  return 'session ' + (index + 1) + '/' + count
}
