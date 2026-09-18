import QtQuick
import qs.Commons
import "../markdown.mjs" as Markdown
import "../transcript.mjs" as Transcript
import "../../shared/html.mjs" as Html

// The transcript rendered, and where things landed in it: the text the
// TextEdit shows, rebuilt when a turn arrives or a reply streams in, then the
// question bars, reply dots, numbered lines and the waiting placeholder found
// in its layout. Reads and writes the view's state (`view`).
Item {
  id: renderer

  property var view: null

  // The question's arrow, measured, so a reply's dot can end where it does.
  TextMetrics {
    id: arrowMetrics
    font: renderer.view ? renderer.view.answer.font : Qt.font({})
    text: ">"
  }

  FontMetrics {
    id: labelMetrics
    font.family: renderer.view ? renderer.view.fontFamily : ""
    font.pixelSize: Style.font.body
  }

  // An answer lands as two changes in one handler — the history, then the
  // status — and callLater folds them into one render.
  function refresh () {
    // The reply the reader was waiting on has landed, and they had already
    // moved off to read: leave them where they are. Settling would throw them
    // back to the top of the reply they were halfway through.
    if (view.thinking) {
      const last = view.turns.length > 0 ? view.turns[view.turns.length - 1] : null
      view.waitingFor = last && last.role === "user" ? String(last.text) : ""
    }
    const stay = !view.thinking && !view.following && Transcript.replyLanded(view.waitingFor, view.turns)
    const at = view.cursor
    if (!view.thinking) view.waitingFor = ""
    view.anchor = -1
    view.preferredX = -1
    if (!stay) view.following = true
    view.repeatFindReady = false
    view.currentFindHit = -1
    view.answer.text = render()
    // The layout settles after the text lands.
    if (stay) Qt.callLater(() => {
      findMarks()
      view.placeCursor(Math.min(at, view.answer.length))
    })
    else Qt.callLater(settle)
  }

  // Find the bars and dots, then land at the start of the newest reply so j
  // reads down through it (or at the end, under the question, while waiting).
  function settle () {
    findMarks()
    view.placeCursor(view.plainDocument ? 0 : startOfNewest())
  }

  function startOfNewest () {
    const last = view.turns.length > 0 ? view.turns[view.turns.length - 1] : null
    if (!last || last.role !== "assistant" || view.replyStarts.length === 0) return view.answer.length
    return Math.min(view.answer.length, view.replyStarts[view.replyStarts.length - 1] + 2)
  }

  function render () {
    // A document is shown as written: escaped, its line breaks kept.
    if (view.plainDocument) {
      return '<div style="color:' + view.questionColor + '; white-space:pre-wrap">' +
        Html.escapeHtml(view.document).split("\n").join("<br>") + '</div>'
    }
    return Markdown.renderTranscript(view.turns, {
      question: view.questionColor,
      answer: view.answerColor,
      glyph: view.glyphColor,
      error: Color.urgent.toString(),
      link: view.questionColor,  // theme ink, not Qt's link blue
      pending: view.thinking,
      pendingText: view.streamText
    })
  }

  function restream () {
    if (!view.thinking) return
    const at = view.cursor
    view.answer.text = render()
    Qt.callLater(() => {
      findMarks()
      view.placeCursor(view.following ? view.answer.length : Math.min(at, view.answer.length))
    })
  }

  function findMarks () {
    const source = view.plain()
    const bars = []
    const leads = []
    const starts = []
    const questions = []
    const owners = []
    let from = 0
    for (let i = 0; i < view.turns.length; i++) {
      const turn = view.turns[i]
      if (turn.role === "user") {
        const line = view.prompt + String(turn.text)
        const at = source.indexOf(line, from)
        if (at === -1) continue
        const first = view.answer.positionToRectangle(at)
        const last = view.answer.positionToRectangle(Math.max(at, at + line.length - 1))
        bars.push({ y: first.y, height: last.y + last.height - first.y })
        questions.push(at)
        from = at + line.length
      } else if (turn.role === "assistant") {
        const at = source.indexOf("●", from)
        if (at === -1) continue
        starts.push(at)
        owners.push(i)
        leads.push(dotAt(at))
        from = at + 1
      }
    }
    const waiting = view.thinking ? source.indexOf("●", from) : -1
    view.pendingDot = waiting === -1 ? null : dotAt(waiting)
    view.pendingText = waiting === -1 ? null : textAt(waiting + 2)
    view.marks = bars
    view.dots = leads
    view.replyStarts = starts
    view.replyTurns = owners
    view.questionStarts = questions
    view.pendingAt = waiting
    findNumberedLines()
    view.updateSearchMatches()          // the text moved, so the lit matches did too
  }

  // Where a reply's text begins, and its baseline.
  function textAt (pos) {
    const r = view.answer.positionToRectangle(Math.min(view.answer.length, pos))
    return { x: r.x, baseline: r.y + r.height - labelMetrics.descent }
  }

  // A reply's dot: its right edge where the question's > ends, so the gap to
  // the text is the arrow's, and centred on the rendered line, including headings.
  // One rule for finished and waiting replies alike.
  function dotAt (lead) {
    const line = view.answer.positionToRectangle(Math.min(view.answer.length, lead + 2))
    const ink = arrowMetrics.tightBoundingRect
    return {
      x: Math.round(view.answer.positionToRectangle(lead).x + ink.x + ink.width - view.dotDiameter),
      y: Math.round(line.y + (line.height - view.dotDiameter) / 2)
    }
  }

  // Blocks are separated by margins, and positionAt in a margin answers with
  // the nearest line below it — from the first line of a block, one pixel up
  // is the line the cursor is already on. So keep stepping until the layout
  // returns a line that actually lies in the direction of travel.
  function findNumberedLines () {
    const lines = []
    if (view.answer.length > 0) {
      let pos = 0
      while (pos >= 0) {
        const rect = view.answer.positionToRectangle(pos)
        lines.push({ y: rect.y, height: rect.height })
        const next = view.mover.lineFrom(pos, 1, 0)
        if (next <= pos) break
        pos = next
      }
    }
    view.numberedLines = lines
  }
}
