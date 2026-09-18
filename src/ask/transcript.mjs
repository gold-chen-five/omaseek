// The transcript's structure in plain-text positions: which reply the cursor is
// on, where a reply ends, and the invisible marks to leave out of copied text.
// The positions come from the TextEdit; the rules live here, under test.

/** The reply the cursor is in; on a question, the reply that answers it; -1 when none. */
export function replyIndexAt (pos, questionStarts, replyStarts) {
  let r = -1
  for (let i = 0; i < replyStarts.length; i++) if (replyStarts[i] <= pos) r = i
  const since = r === -1 ? -1 : replyStarts[r]
  for (let i = 0; i < questionStarts.length; i++) {
    const q = questionStarts[i]
    if (q > since && q <= pos) return r + 1 < replyStarts.length ? r + 1 : -1
  }
  return r
}

/** Where reply i's text ends: the next question or reply, the waiting placeholder, or the end. */
export function replyEnd (i, questionStarts, replyStarts, pendingAt, length) {
  const start = replyStarts[i]
  let end = length
  const later = questionStarts.concat(replyStarts, pendingAt >= 0 ? [pendingAt] : [])
  for (let k = 0; k < later.length; k++) if (later[k] > start && later[k] < end) end = later[k]
  return end
}

// A hand-off carries turns as the agent wrote them, spelled as bin/ask's
// build_prompt spells a conversation — not the rendered text, whose reply
// dots are placeholder characters.
function spoken (turn) {
  return (turn.role === 'user' ? 'User: ' : 'Assistant: ') + String(turn.text)
}

/** The reply at turn `index` and the question it answers, for a hand-off. */
export function exchangeText (turns, index) {
  const list = turns || []
  const reply = list[index]
  if (!reply) return ''
  for (let i = index - 1; i >= 0; i--) {
    if (list[i].role === 'user') return spoken(list[i]) + '\n\n' + spoken(reply)
  }
  return spoken(reply)
}

/** Every question and answer, failures left out, for handing off the whole conversation. */
export function conversationText (turns) {
  const parts = []
  for (let i = 0; i < (turns || []).length; i++) {
    const turn = turns[i]
    if (turn.role === 'user' || turn.role === 'assistant') parts.push(spoken(turn))
  }
  return parts.join('\n\n')
}

/** `text`, which began at position `base`, with the [start, end) ranges taken out. */
export function cut (text, base, ranges) {
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const pos = base + i
    let inside = false
    for (let k = 0; k < ranges.length; k++) if (pos >= ranges[k][0] && pos < ranges[k][1]) { inside = true; break }
    if (!inside) out += text.charAt(i)
  }
  return out
}

/**
 * Whether the turns are the reply to `question` landing: the question last
 * asked, then one assistant turn — an answer, a stop or an error. Anything else
 * is a different conversation on screen, and that one starts at its newest reply.
 */
export function replyLanded (question, turns) {
  if (!question || !Array.isArray(turns) || turns.length < 2) return false
  const last = turns[turns.length - 1]
  const asked = turns[turns.length - 2]
  return !!last && !!asked && last.role === 'assistant' && asked.role === 'user' &&
    String(asked.text) === String(question)
}
