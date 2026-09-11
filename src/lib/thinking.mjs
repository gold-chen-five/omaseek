// The line shown while an agent works: spinner, verb and clock, as Claude Code does.

export const FRAMES = ['·', '✢', '✳', '✶', '✻', '✽', '✻', '✶', '✳', '✢']
export const FRAME_MS = 100

export const VERBS = [
  'Thinking', 'Pondering', 'Mulling', 'Cogitating', 'Ruminating', 'Musing',
  'Considering', 'Brewing', 'Percolating', 'Simmering', 'Marinating', 'Stewing',
  'Composing', 'Weighing', 'Reckoning', 'Working', 'Crunching', 'Noodling'
]

/** A verb for this question — deterministic for a seed, so a re-render keeps it. */
export function pickVerb (seed) {
  const n = Math.abs(Math.floor(Number(seed) || 0))
  return VERBS[n % VERBS.length]
}

/** "7s", "1m 07s", "12m 03s" — a clock, not a stopwatch. */
export function elapsedText (ms) {
  const total = Math.max(0, Math.floor((Number(ms) || 0) / 1000))
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  if (minutes === 0) return seconds + 's'
  return minutes + 'm ' + (seconds < 10 ? '0' : '') + seconds + 's'
}

/** The whole line: glyph, verb, clock. `tick` is any counter; it picks the frame. */
export function thinkingLine (tick, verb, ms) {
  const frame = FRAMES[Math.abs(Math.floor(Number(tick) || 0)) % FRAMES.length]
  return frame + ' ' + verb + '… (' + elapsedText(ms) + ')'
}
