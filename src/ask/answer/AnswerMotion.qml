import QtQuick
import "../../shared/vim/motions.mjs" as Motions

// Where a key takes the cursor. Every motion answers where it lands rather
// than moving, so one target moves the cursor, stretches a selection, or
// bounds a yank; go() does whichever was asked. Line motions use the TextEdit's
// layout: wrapped Markdown has no lines of its own to count.
Item {
  id: mover

  property var view: null

  // count lines down, or up when negative, aiming for the column j and k keep.
  function lineTarget (count) {
    if (view.preferredX < 0) view.preferredX = view.answer.positionToRectangle(view.cursor).x
    let pos = view.cursor
    for (let i = 0; i < Math.abs(count); i++) {
      const next = lineFrom(pos, count)
      if (next === -1) break
      pos = next
    }
    return pos
  }

  function halfPageTarget (direction) {
    const rect = view.answer.positionToRectangle(view.cursor)
    if (view.preferredX < 0) view.preferredX = rect.x
    const y = Math.max(0, Math.min(view.answer.contentHeight - 1, rect.y + direction * view.flick.height / 2))
    return view.answer.positionAt(view.preferredX, y)
  }

  // Where a motion lands, without going there: { pos, inclusive, linewise,
  // column }, or null for a command that is not a motion. The one answer moves
  // the cursor, stretches a selection, or bounds a yank.
  function motionTarget (command, count, operator) {
    const text = view.plain()
    const times = motion => Motions.repeat(motion, count, view.cursor)
    switch (command) {
    case "down":            return { pos: lineTarget(count), linewise: true, column: true }
    case "up":              return { pos: lineTarget(-count), linewise: true, column: true }
    case "halfPageDown":    return { pos: halfPageTarget(1), linewise: true, column: true }
    case "halfPageUp":      return { pos: halfPageTarget(-1), linewise: true, column: true }
    // Along the line and no further, as vim's h and l; a pending y may take
    // the line to its end (yl on the last character still yanks it).
    case "right":           return { pos: Motions.charStep(text, view.cursor, count, !!operator) }
    case "left":            return { pos: Motions.charStep(text, view.cursor, -count) }
    case "top":             return { pos: 0, linewise: true }
    case "bottom":          return { pos: view.answer.length, linewise: true }
    case "wordForward":     return { pos: times(at => Motions.wordForward(text, at)) }
    case "wordForwardBig":  return { pos: times(at => Motions.wordForward(text, at, true)) }
    case "wordBackward":    return { pos: times(at => Motions.wordBackward(text, at)) }
    case "wordBackwardBig": return { pos: times(at => Motions.wordBackward(text, at, true)) }
    case "wordEnd":         return { pos: times(at => Motions.wordEnd(text, at)), inclusive: true }
    case "wordEndBig":      return { pos: times(at => Motions.wordEnd(text, at, true)), inclusive: true }
    case "lineStart":       return { pos: lineStartAt(view.cursor) }
    case "lineEnd":         return { pos: Math.max(lineStartAt(view.cursor), lineEndAt(view.cursor) - 1), inclusive: true }  // on the last character, as vim puts it
    // A motion, so a count repeats it (3n) and an operator can take it (y2n).
    case "findNext":        return { pos: view.finder.target(false, view.cursor, count) }
    case "findPrevious":    return { pos: view.finder.target(true, view.cursor, count) }
    }
    return null
  }

  // f F t T look along the line under the cursor only, as vim's do.
  function findTarget (command, char, count, again) {
    return {
      pos: Motions.findInLine(view.plain(), view.cursor, command, char, count, again),
      inclusive: command === "f" || command === "t"
    }
  }

  function go (target, operator) {
    if (!target || target.pos < 0) return
    if (operator === "y") view.selector.yankMotion(target)
    else view.placeCursor(target.pos, target.column === true)
  }

  function ensureVisible () {
    const rect = view.answer.positionToRectangle(view.cursor)
    view.cursorRect = rect
    const overflow = view.flick.contentHeight - view.flick.height
    if (overflow <= 0) { view.flick.contentY = 0; return }
    const centred = rect.y + rect.height / 2 - view.flick.height / 2
    view.flick.contentY = Math.max(0, Math.min(overflow, centred))
  }

  function lineStartAt (pos) {
    const rect = view.answer.positionToRectangle(pos)
    return view.answer.positionAt(0, rect.y + rect.height / 2)
  }

  function lineEndAt (pos) {
    const rect = view.answer.positionToRectangle(pos)
    return view.answer.positionAt(view.answer.width, rect.y + rect.height / 2)
  }

  function lineFrom (pos, delta, column) {
    const rect = view.answer.positionToRectangle(pos)
    const step = Math.max(2, Math.round(rect.height / 4))
    let y = delta > 0 ? rect.y + rect.height + 1 : rect.y - 1
    while (y >= 0 && y <= view.answer.contentHeight) {
      const next = view.answer.positionAt(column === undefined ? view.preferredX : column, y)
      const landed = view.answer.positionToRectangle(next)
      if (delta > 0 ? landed.y > rect.y : landed.y < rect.y) return next
      y += delta > 0 ? step : -step
    }
    return -1
  }
}
