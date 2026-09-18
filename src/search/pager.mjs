// Which page squares the strip shows. Pages accumulate as they are fetched, and
// the strip is one row under the status line, so past a dozen it has to show a
// window rather than every page. Pure; under test.

/**
 * The window of page squares to draw, as [start, end) 0-based, keeping the page
 * on screen inside it and the row full wherever there are enough pages.
 */
export function pageWindow (current, count, max = 10) {
  const total = Math.max(0, Math.floor(count) || 0)
  const size = Math.max(1, Math.floor(max) || 1)
  if (total <= size) return { start: 0, end: total }
  const at = Math.max(0, Math.min(Math.floor(current) || 0, total - 1))
  // Keep a couple of pages visible either side of the one being read, so
  // stepping with h or l moves within the window rather than redrawing it.
  const start = Math.max(0, Math.min(at - Math.floor(size / 2), total - size))
  return { start: start, end: start + size }
}

/**
 * What a page square says. With relative line numbers the squares count from the
 * page being read — `2 1 0 1 2` — so `3h` and `5l` can be read straight off the
 * row, spelled exactly as the rows above spell theirs: an unsigned distance,
 * nought on the one being read, which is filled anyway. Any other setting
 * numbers the pages plainly.
 */
export function pageLabel (page, current, numbering = 'absolute') {
  if (numbering !== 'relative') return String(page)
  return String(Math.abs(page - current))
}
