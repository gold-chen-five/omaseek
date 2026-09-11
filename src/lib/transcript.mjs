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
