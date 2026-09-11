// The indicator shown while an agent works: a dot sweeping across three, as
// if looking for something. omaseek's own mark, deliberately not Claude
// Code's sparkle and verbs, and slow on purpose: it says "still working".

export const FRAMES = ['●∙∙', '∙●∙', '∙∙●', '∙●∙']
export const FRAME_MS = 240

/** "7s", "1m 07s", "12m 03s" — a clock, not a stopwatch. */
export function elapsedText (ms) {
  const total = Math.max(0, Math.floor((Number(ms) || 0) / 1000))
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  if (minutes === 0) return seconds + 's'
  return minutes + 'm ' + (seconds < 10 ? '0' : '') + seconds + 's'
}

/** The line beside the dots: who is working, and for how long. */
export function thinkingLabel (agent, ms) {
  const who = String(agent == null ? '' : agent).trim() || 'the agent'
  return who + ' is thinking · ' + elapsedText(ms)
}
