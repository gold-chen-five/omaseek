import QtQuick
import Quickshell
import "../transcript.mjs" as Transcript
import "../../shared/vim/grammar.mjs" as Grammar
import "../../shared/vim/textobjects.mjs" as TextObjects

// Visual mode and every yank: starting, stretching and dropping a selection,
// reading it back as the agent wrote it, and copying a selection, a motion, a
// text object, lines or a whole reply to the clipboard — each lit for a beat.
Item {
  id: selector

  property var view: null

  function startSelecting (byLine) {
    yankFlash.stop()
    endFlash()
    view.anchor = view.cursor
    view.linewise = byLine
    view.placeCursor(view.cursor, true)
  }

  function stopSelecting () {
    yankFlash.stop()
    if (view.selecting) view.lastVisual = { anchor: view.anchor, cursor: view.cursor, linewise: view.linewise }
    view.anchor = -1
    view.linewise = false
    view.answer.deselect()
    view.answer.cursorPosition = view.cursor
    view.cursorLink = view.linkUnder(view.cursor)
  }

  function reselect () {
    if (!view.lastVisual) return
    view.anchor = view.lastVisual.anchor
    view.linewise = view.lastVisual.linewise
    view.placeCursor(view.lastVisual.cursor, true)
  }

  // Charwise visual includes the character under the cursor, as vim's does;
  // TextEdit.select(a, b) stops before b, so the text is read directly.
  function selection () {
    if (!view.selecting) return ""
    const from = view.linewise ? view.mover.lineStartAt(Math.min(view.anchor, view.cursor)) : Math.min(view.anchor, view.cursor)
    const to = view.linewise ? view.mover.lineEndAt(Math.max(view.anchor, view.cursor)) : Math.min(view.answer.length, Math.max(view.anchor, view.cursor) + 1)
    return Transcript.cut(view.plain().substring(from, to), from, leadRanges())
  }

  // The ● before each reply, and the waiting placeholder: present in the text
  // only to hold a drawn dot's place, so copied text leaves them out.
  function leadRanges () {
    const ranges = []
    for (let i = 0; i < view.replyStarts.length; i++) ranges.push([view.replyStarts[i], view.replyStarts[i] + 2])
    if (view.pendingAt !== -1) ranges.push([view.pendingAt, view.pendingAt + 3])
    return ranges
  }

  function copy (value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  function yank () {
    if (!view.selecting) return yankReply()
    copy(selection())
    yankFlash.restart()                        // lit for a beat, as LazyVim does
  }

  // yy follows the displayed lines used by j/k and the number gutter.
  function yankLines (count) {
    const from = view.mover.lineStartAt(view.cursor)
    let last = view.cursor
    for (let i = 1; i < count; i++) {
      const next = view.mover.lineFrom(last, 1, 0)
      if (next < 0) break
      last = next
    }
    const next = view.mover.lineFrom(last, 1, 0)
    const to = next < 0 ? view.answer.length : view.mover.lineStartAt(next)
    yankRange(from, to)
  }

  // The reply under the cursor, as the agent wrote it — Markdown, so a
  // link or a code block survives the paste. On a question, the reply that
  // answers it.
  function yankReply () {
    let r = Transcript.replyIndexAt(view.cursor, view.questionStarts, view.replyStarts)
    if (r === -1) r = view.replyStarts.length - 1
    if (r === -1) return
    copy(String(view.turns[view.replyTurns[r]].text))
    // Lit by a band behind its lines, not by selecting it: a selection
    // appearing on the text is taken for a mouse drag and starts visual mode.
    const from = view.replyStarts[r] + 2
    const to = Transcript.replyEnd(r, view.questionStarts, view.replyStarts, view.pendingAt, view.answer.length)
    const top = view.answer.positionToRectangle(from)
    const bottom = view.answer.positionToRectangle(Math.max(from, to - 1))
    view.yankBand = { y: top.y, height: bottom.y + bottom.height - top.y }
    replyFlash.restart()
  }

  // y with a motion. Linewise motions take whole lines, as V does; an
  // exclusive one stops short of the character it lands on.
  function yankMotion (target) {
    const low = Math.min(view.cursor, target.pos)
    const high = Math.max(view.cursor, target.pos)
    if (target.linewise) yankRange(view.mover.lineStartAt(low), view.mover.lineEndAt(high))
    else if (target.inclusive) yankRange(low, Math.min(view.answer.length, high + 1))
    else yankRange(low, Grammar.trimExclusive(view.plain(), low, high))
  }

  // [from, to) to the clipboard, lit for a beat; the cursor goes to its start,
  // as vim's does.
  function yankRange (from, to) {
    if (to <= from) return
    copy(Transcript.cut(view.plain().substring(from, to), from, leadRanges()))
    view.placeCursor(from)
    flash(from, to)
  }

  // Lit by selecting it, flagged: a selection appearing on the text is
  // otherwise taken for a mouse drag and starts visual mode.
  function flash (from, to) {
    view.flashing = true
    view.answer.select(from, to)
    rangeFlash.restart()
  }

  function endFlash () {
    rangeFlash.stop()
    if (!view.flashing) return
    view.flashing = false
    if (!view.selecting) {
      view.answer.deselect()
      view.answer.cursorPosition = view.cursor
    }
  }

  // iw, a", i( … on the line under the cursor: yanked after y, selected in
  // visual mode.
  function takeObject (scope, object, operator) {
    const range = TextObjects.isTextObject(object) ? TextObjects.resolveInLine(view.plain(), view.cursor, scope, object) : null
    if (!range) return
    if (operator === "y") {
      yankRange(range.start, range.end)
      return
    }
    if (!view.selecting) return
    view.linewise = false
    view.anchor = range.start
    view.placeCursor(Math.max(range.start, range.end - 1), true)
  }

  // A reply yanked whole is lit for a beat; so is a range, and a selection
  // yanked from visual mode, which then ends.
  Timer {
    id: replyFlash
    interval: 250
    onTriggered: selector.view.yankBand = null
  }

  Timer {
    id: rangeFlash
    interval: 250
    onTriggered: selector.endFlash()
  }

  Timer {
    id: yankFlash
    interval: 250
    onTriggered: selector.stopSelecting()
  }
}
