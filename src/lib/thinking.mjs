// The line shown while an agent works: one dot breathing slowly beside who is
// working and for how long. omaseek's own, deliberately not Claude Code's
// sparkle and verbs.

export const PULSE_MS = 1600      // one slow breath, out and back
export const CLOCK_MS = 500       // how often the clock is redrawn

/** "7s", "1m 07s", "12m 03s" — a clock, not a stopwatch. */
export function elapsedText (ms) {
  const total = Math.max(0, Math.floor((Number(ms) || 0) / 1000))
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  if (minutes === 0) return seconds + 's'
  return minutes + 'm ' + (seconds < 10 ? '0' : '') + seconds + 's'
}

/** The line beside the dot: who is working, and for how long. */
export function thinkingLabel (agent, ms) {
  const who = String(agent == null ? '' : agent).trim() || 'the agent'
  return who + ' is thinking · ' + elapsedText(ms)
}
