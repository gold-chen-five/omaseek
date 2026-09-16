// Measuring inside a TextEdit, for the things drawn over its text. A .js file so
// it can see Qt; both panes that light a character need the same answer, and a
// wrapped rich-text layout makes it fiddly enough to be worth one copy.

// The rectangle of the character at `pos`. positionToRectangle gives a caret —
// a zero-width line — so the width comes from the next character's caret, and
// falls back to the font's average where there is no next one on this line.
function characterRect (edit, pos, fallbackWidth) {
  const start = edit.positionToRectangle(pos)
  const next = edit.positionToRectangle(Math.min(edit.length, pos + 1))
  const width = Math.abs(next.y - start.y) < 1 && next.x > start.x
    ? next.x - start.x : fallbackWidth
  return Qt.rect(start.x, start.y, Math.max(1, width), start.height)
}
