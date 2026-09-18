import QtQuick
import Quickshell
import qs.Commons
import "../lib/keys.mjs" as KeysLib
import "../lib/find.mjs" as Find
import "../lib/motions.mjs" as Motions
import "../lib/markdown.mjs" as Markdown
import "../lib/thinking.mjs" as Thinking
import "../lib/urls.mjs" as Urls
import "../lib/transcript.mjs" as Transcript
import "../lib/textobjects.mjs" as TextObjects
import "../lib/grammar.mjs" as Grammar
import "../lib/keybinds.mjs" as Keybinds
import "chord.js" as Chord
import "measure.js" as Measure

// The transcript, read with vim keys. One read-only rich-text TextEdit holds
// every turn, so the cursor and a selection can cross turns. Line motions use
// its layout (positionAt/positionToRectangle): wrapped Markdown has no lines of
// its own to count.
FocusScope {
  id: view

  property var turns: []                       // [{ role: 'user'|'assistant', text }]
  property bool thinking: false
  property string agentName: ""

  property int tick: 0
  property real startedAt: 0

  onThinkingChanged: {
    if (thinking) {
      startedAt = Date.now()
      tick = 0
    }
    Qt.callLater(refresh)
  }

  // The question's arrow, measured, so a reply's dot can end where it does.
  TextMetrics {
    id: arrowMetrics
    font: answer.font
    text: ">"
  }

  FontMetrics {
    id: labelMetrics
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }

  Timer {
    interval: Thinking.CLOCK_MS
    running: view.thinking && view.visible
    repeat: true
    onTriggered: view.tick = view.tick + 1
  }
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  property int cursor: 0
  property int anchor: -1                      // visual mode's other end, or -1
  property bool linewise: false                // V rather than v
  property var lastVisual: null                // for gv: { anchor, cursor, linewise }
  property var grammar: Grammar.IDLE           // a half-typed sequence: 3, y, yi, f, g
  property var lastFind: null                  // { command, char }, for ; and ,
  property bool repeatFindReady: false         // clever-f: fa, then f/F walk the same target
  property int currentFindHit: -1              // actual match; t/T leave the cursor beside it
  readonly property var findMatches: repeatFindReady && lastFind
    ? Motions.matchingCharsInLine(plain(), currentFindHit, lastFind.char) : []
  property string streamText: ""                // the reply being written, so far
  property bool following: true                // stay at the bottom until the reader moves
  property bool flashing: false                // a yanked range is lit, not selected
  // The panel keys, already parsed, by action id. Only the new-session one is
  // read here: the rest are commands in the pane's keymap.
  property var chords: Keybinds.panelChords(null)
  property string cursorLink: ""               // the openable link under the cursor, or ""
  property real preferredX: -1                 // the column j/k try to keep
  property var binds: null                     // the settings: where the rebindable commands sit
  readonly property var readerKeys: KeysLib.readerKeys("answer", binds)

  // `/` through the transcript. The pattern stays lit after the prompt closes,
  // as vim's hlsearch does; leaving the pane forgets it.
  readonly property string findPrompt: finder.prompt
  readonly property string findPattern: finder.active ? finder.find.pattern : finder.lastPattern
  // A pattern still being typed matches inside a word; one `*` started does not.
  readonly property bool findWholeWord: finder.active ? false : finder.lastWholeWord
  property var searchMatches: []

  Finder {
    id: finder

    matchesFor: (pattern, wholeWord) => Find.matchPositions(view.plain(), pattern, wholeWord)

    onMoved: target => view.placeCursor(target)
    onDropped: target => view.placeCursor(target)
  }

  onFindPatternChanged: updateSearchMatches()
  onFindWholeWordChanged: updateSearchMatches()

  function updateSearchMatches () {
    searchMatches = findPattern === "" ? [] : Find.matchPositions(plain(), findPattern, findWholeWord)
  }

  // `*` and `#`: the word under the cursor becomes the search, with no prompt to
  // type into. It leaves the state an accepted prompt would, so the matches stay
  // lit and n and N carry on from there.
  function searchWordUnderCursor (backward) {
    finder.searchWord(Find.wordAt(plain(), cursor), cursor, backward)
  }
  property string lineNumbers: "relative"
  readonly property int cursorLine: {
    let nearest = 0
    for (let i = 0; i < numberedLines.length; i++) {
      if (numberedLines[i].y <= cursorRect.y + 1) nearest = i
      else break
    }
    return nearest
  }
  property var numberedLines: []               // rendered lines, matching j/k
  property var marks: []                       // [{ y, height }] — where the questions are
  property var dots: []                        // [{ x, y }] — where each reply's dot goes
  property var replyStarts: []                 // plain-text index of each reply's ●
  property var replyTurns: []                  // and which turn each one is
  property var questionStarts: []              // plain-text index of each question's >
  property int pendingAt: -1                   // the waiting placeholder's ●, or -1
  property var yankBand: null                  // { y, height } of a reply just yanked, while lit
  property var pendingDot: null                // while thinking: the placeholder reply's dot
  property var pendingText: null               // and where its text would begin
  readonly property int dotDiameter: Math.round(Style.font.body * 0.55)

  readonly property bool selecting: anchor !== -1
  readonly property string prompt: "> "        // Claude Code's prompt glyph; the plain text starts with it

  // The reply sits a step back from the question, the glyphs two steps.
  readonly property string questionColor: view.foreground.toString()
  readonly property string answerColor: blend(view.foreground, Color.menu.background, 0.78)
  readonly property string glyphColor: blend(view.foreground, Color.menu.background, 0.5)

  function blend (a, b, t) {
    return Qt.rgba(a.r * t + b.r * (1 - t), a.g * t + b.g * (1 - t), a.b * t + b.b * (1 - t), 1).toString()
  }

  signal handedOff(string context)             // Enter: give this to the agent
  signal linkOpened(string url)                // gx on a link
  signal searchRequested(string text)          // gs: search the web for this
  signal escaped()                             // esc: back to the field, normal mode
  signal normalRequested()                     // /: back to the field, normal mode
  signal insertRequested()                     // i: back to the field, insert before the cursor
  signal appendRequested()                     // a: back to the field, insert after the cursor
  signal settingsRequested()
  signal tabbed()
  signal newSessionRequested()                 // the new-session chord, or the button
  signal sessionWalked(int delta)              // L / H and ctrl+n: how far through the ring
  signal closeSessionRequested()               // forget this conversation
  signal clearSessionsRequested()              // forget all of them
  signal stopRequested()                       // stop the reply being written
  signal retryRequested()                      // ask the last question again
  signal putRequested(string text, bool after) // p and P: the selection, or "" for the clipboard
  signal askRequested(string text)             // gc: this text, into the ask bar

  onActiveFocusChanged: {
    grammar = Grammar.IDLE
    repeatFindReady = false
    currentFindHit = -1
    // Leaving the pane drops the search as well as the prompt, so a highlight
    // never outlives the reading that wanted it.
    if (!activeFocus) finder.forget()
    if (activeFocus) cursorLink = linkUnder(cursor)   // the layout may not have existed when the answer landed
  }
  onTurnsChanged: Qt.callLater(refresh)

  // An answer lands as two changes in one handler — the history, then the
  // status — and callLater folds them into one render.
  function refresh () {
    anchor = -1
    preferredX = -1
    following = true
    repeatFindReady = false
    currentFindHit = -1
    answer.text = render()
    Qt.callLater(settle)                       // the layout settles after the text lands
  }

  // Find the bars and dots, then land at the start of the newest reply so j
  // reads down through it (or at the end, under the question, while waiting).
  function settle () {
    findMarks()
    placeCursor(startOfNewest())
  }

  function startOfNewest () {
    const last = turns.length > 0 ? turns[turns.length - 1] : null
    if (!last || last.role !== "assistant" || replyStarts.length === 0) return answer.length
    return Math.min(answer.length, replyStarts[replyStarts.length - 1] + 2)
  }
  onWidthChanged: Qt.callLater(findMarks)

  function render () {
    return Markdown.renderTranscript(turns, {
      question: questionColor,
      answer: answerColor,
      glyph: glyphColor,
      error: Color.urgent.toString(),
      link: questionColor,  // theme ink, not Qt's link blue
      pending: thinking,
      pendingText: streamText
    })
  }

  // A reply arriving in pieces is not a new answer: the text is replaced, but
  // the cursor stays where the reader put it and settle() is not run, or every
  // repaint would drag them to the newest line.
  onStreamTextChanged: if (thinking) Qt.callLater(restream)

  function restream () {
    if (!thinking) return
    const at = cursor
    answer.text = render()
    Qt.callLater(() => {
      findMarks()
      placeCursor(following ? answer.length : Math.min(at, answer.length))
    })
  }

  // A <br> in a question comes back as U+2028, not \n. Swapping one for the
  // other keeps every position where it was, and lets a question typed on
  // several lines be found again by its text.
  function plain () {
    return answer.getText(0, answer.length).split(String.fromCharCode(0x2028)).join("\n")
  }

  function findMarks () {
    const source = plain()
    const bars = []
    const leads = []
    const starts = []
    const questions = []
    const owners = []
    let from = 0
    for (let i = 0; i < turns.length; i++) {
      const turn = turns[i]
      if (turn.role === "user") {
        const line = prompt + String(turn.text)
        const at = source.indexOf(line, from)
        if (at === -1) continue
        const first = answer.positionToRectangle(at)
        const last = answer.positionToRectangle(Math.max(at, at + line.length - 1))
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
    const waiting = thinking ? source.indexOf("●", from) : -1
    pendingDot = waiting === -1 ? null : dotAt(waiting)
    pendingText = waiting === -1 ? null : textAt(waiting + 2)
    marks = bars
    dots = leads
    replyStarts = starts
    replyTurns = owners
    questionStarts = questions
    pendingAt = waiting
    findNumberedLines()
    updateSearchMatches()          // the text moved, so the lit matches did too
  }

  // Where a reply's text begins, and its baseline.
  function textAt (pos) {
    const r = answer.positionToRectangle(Math.min(answer.length, pos))
    return { x: r.x, baseline: r.y + r.height - labelMetrics.descent }
  }

  // A reply's dot: its right edge where the question's > ends, so the gap to
  // the text is the arrow's, and centred on the rendered line, including headings.
  // One rule for finished and waiting replies alike.
  function dotAt (lead) {
    const line = answer.positionToRectangle(Math.min(answer.length, lead + 2))
    const ink = arrowMetrics.tightBoundingRect
    return {
      x: Math.round(answer.positionToRectangle(lead).x + ink.x + ink.width - dotDiameter),
      y: Math.round(line.y + (line.height - dotDiameter) / 2)
    }
  }

  function lineStartAt (pos) {
    const rect = answer.positionToRectangle(pos)
    return answer.positionAt(0, rect.y + rect.height / 2)
  }

  function lineEndAt (pos) {
    const rect = answer.positionToRectangle(pos)
    return answer.positionAt(answer.width, rect.y + rect.height / 2)
  }

  // Every motion ends here so the selection follows the cursor as one thing.
  function placeCursor (pos, keepColumn) {
    cursor = Math.max(0, Math.min(answer.length, pos))
    cursorLink = selecting ? Urls.urlFromSelection(selection()) : linkUnder(cursor)
    if (selecting) {
      if (linewise) answer.select(lineStartAt(Math.min(anchor, cursor)), lineEndAt(Math.max(anchor, cursor)))
      else answer.select(anchor, cursor)
    } else {
      answer.cursorPosition = cursor
    }
    if (!keepColumn) preferredX = -1
    ensureVisible()
  }

  // Blocks are separated by margins, and positionAt in a margin answers with
  // the nearest line below it — from the first line of a block, one pixel up
  // is the line the cursor is already on. So keep stepping until the layout
  // returns a line that actually lies in the direction of travel.
  function findNumberedLines () {
    const lines = []
    if (answer.length > 0) {
      let pos = 0
      while (pos >= 0) {
        const rect = answer.positionToRectangle(pos)
        lines.push({ y: rect.y, height: rect.height })
        const next = lineFrom(pos, 1, 0)
        if (next <= pos) break
        pos = next
      }
    }
    numberedLines = lines
  }

  function lineFrom (pos, delta, column) {
    const rect = answer.positionToRectangle(pos)
    const step = Math.max(2, Math.round(rect.height / 4))
    let y = delta > 0 ? rect.y + rect.height + 1 : rect.y - 1
    while (y >= 0 && y <= answer.contentHeight) {
      const next = answer.positionAt(column === undefined ? preferredX : column, y)
      const landed = answer.positionToRectangle(next)
      if (delta > 0 ? landed.y > rect.y : landed.y < rect.y) return next
      y += delta > 0 ? step : -step
    }
    return -1
  }

  // count lines down, or up when negative, aiming for the column j and k keep.
  function lineTarget (count) {
    if (preferredX < 0) preferredX = answer.positionToRectangle(cursor).x
    let pos = cursor
    for (let i = 0; i < Math.abs(count); i++) {
      const next = lineFrom(pos, count)
      if (next === -1) break
      pos = next
    }
    return pos
  }

  function halfPageTarget (direction) {
    const rect = answer.positionToRectangle(cursor)
    if (preferredX < 0) preferredX = rect.x
    const y = Math.max(0, Math.min(answer.contentHeight - 1, rect.y + direction * flick.height / 2))
    return answer.positionAt(preferredX, y)
  }

  // Where a motion lands, without going there: { pos, inclusive, linewise,
  // column }, or null for a command that is not a motion. The one answer moves
  // the cursor, stretches a selection, or bounds a yank.
  function motionTarget (command, count) {
    const text = plain()
    const times = motion => Motions.repeat(motion, count, cursor)
    switch (command) {
    case "down":            return { pos: lineTarget(count), linewise: true, column: true }
    case "up":              return { pos: lineTarget(-count), linewise: true, column: true }
    case "halfPageDown":    return { pos: halfPageTarget(1), linewise: true, column: true }
    case "halfPageUp":      return { pos: halfPageTarget(-1), linewise: true, column: true }
    case "right":           return { pos: Math.min(answer.length, cursor + count) }
    case "left":            return { pos: Math.max(0, cursor - count) }
    case "top":             return { pos: 0, linewise: true }
    case "bottom":          return { pos: answer.length, linewise: true }
    case "wordForward":     return { pos: times(at => Motions.wordForward(text, at)) }
    case "wordForwardBig":  return { pos: times(at => Motions.wordForward(text, at, true)) }
    case "wordBackward":    return { pos: times(at => Motions.wordBackward(text, at)) }
    case "wordBackwardBig": return { pos: times(at => Motions.wordBackward(text, at, true)) }
    case "wordEnd":         return { pos: times(at => Motions.wordEnd(text, at)), inclusive: true }
    case "wordEndBig":      return { pos: times(at => Motions.wordEnd(text, at, true)), inclusive: true }
    case "lineStart":       return { pos: lineStartAt(cursor) }
    case "lineEnd":         return { pos: Math.max(lineStartAt(cursor), lineEndAt(cursor) - 1), inclusive: true }  // on the last character, as vim puts it
    // A motion, so a count repeats it (3n) and an operator can take it (y2n).
    case "findNext":        return { pos: finder.target(false, cursor, count) }
    case "findPrevious":    return { pos: finder.target(true, cursor, count) }
    }
    return null
  }

  // f F t T look along the line under the cursor only, as vim's do.
  function findTarget (command, char, count, again) {
    return {
      pos: Motions.findInLine(plain(), cursor, command, char, count, again),
      inclusive: command === "f" || command === "t"
    }
  }

  function characterRect (pos) {
    return Measure.characterRect(answer, pos, labelMetrics.averageCharacterWidth)
  }

  function go (target, operator) {
    if (!target || target.pos < 0) return
    if (operator === "y") yankMotion(target)
    else placeCursor(target.pos, target.column === true)
  }

  // Once the transcript overflows, hold the cursor line centred so every j or k
  // scrolls.
  property rect cursorRect: Qt.rect(0, 0, 0, 0)

  function ensureVisible () {
    const rect = answer.positionToRectangle(cursor)
    cursorRect = rect
    const overflow = flick.contentHeight - flick.height
    if (overflow <= 0) { flick.contentY = 0; return }
    const centred = rect.y + rect.height / 2 - flick.height / 2
    flick.contentY = Math.max(0, Math.min(overflow, centred))
  }

  function startSelecting (byLine) {
    yankFlash.stop()
    endFlash()
    anchor = cursor
    linewise = byLine
    placeCursor(cursor, true)
  }

  function stopSelecting () {
    yankFlash.stop()
    if (selecting) lastVisual = { anchor: anchor, cursor: cursor, linewise: linewise }
    anchor = -1
    linewise = false
    answer.deselect()
    answer.cursorPosition = cursor
    cursorLink = linkUnder(cursor)
  }

  function reselect () {
    if (!lastVisual) return
    anchor = lastVisual.anchor
    linewise = lastVisual.linewise
    placeCursor(lastVisual.cursor, true)
  }

  // Charwise visual includes the character under the cursor, as vim's does;
  // TextEdit.select(a, b) stops before b, so the text is read directly.
  function selection () {
    if (!selecting) return ""
    const from = linewise ? lineStartAt(Math.min(anchor, cursor)) : Math.min(anchor, cursor)
    const to = linewise ? lineEndAt(Math.max(anchor, cursor)) : Math.min(answer.length, Math.max(anchor, cursor) + 1)
    return Transcript.cut(plain().substring(from, to), from, leadRanges())
  }

  // The ● before each reply, and the waiting placeholder: present in the text
  // only to hold a drawn dot's place, so copied text leaves them out.
  function leadRanges () {
    const ranges = []
    for (let i = 0; i < replyStarts.length; i++) ranges.push([replyStarts[i], replyStarts[i] + 2])
    if (pendingAt !== -1) ranges.push([pendingAt, pendingAt + 3])
    return ranges
  }

  function copy (value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  function yank () {
    if (!selecting) return yankReply()
    copy(selection())
    yankFlash.restart()                        // lit for a beat, as LazyVim does
  }

  // yy follows the displayed lines used by j/k and the number gutter.
  function yankLines (count) {
    const from = lineStartAt(cursor)
    let last = cursor
    for (let i = 1; i < count; i++) {
      const next = lineFrom(last, 1, 0)
      if (next < 0) break
      last = next
    }
    const next = lineFrom(last, 1, 0)
    const to = next < 0 ? answer.length : lineStartAt(next)
    yankRange(from, to)
  }

  // The reply under the cursor, as the agent wrote it — Markdown, so a
  // link or a code block survives the paste. On a question, the reply that
  // answers it.
  function yankReply () {
    let r = Transcript.replyIndexAt(cursor, questionStarts, replyStarts)
    if (r === -1) r = replyStarts.length - 1
    if (r === -1) return
    copy(String(turns[replyTurns[r]].text))
    // Lit by a band behind its lines, not by selecting it: a selection
    // appearing on the text is taken for a mouse drag and starts visual mode.
    const from = replyStarts[r] + 2
    const to = Transcript.replyEnd(r, questionStarts, replyStarts, pendingAt, answer.length)
    const top = answer.positionToRectangle(from)
    const bottom = answer.positionToRectangle(Math.max(from, to - 1))
    yankBand = { y: top.y, height: bottom.y + bottom.height - top.y }
    replyFlash.restart()
  }

  // y with a motion. Linewise motions take whole lines, as V does; an
  // exclusive one stops short of the character it lands on.
  function yankMotion (target) {
    const low = Math.min(cursor, target.pos)
    const high = Math.max(cursor, target.pos)
    if (target.linewise) yankRange(lineStartAt(low), lineEndAt(high))
    else if (target.inclusive) yankRange(low, Math.min(answer.length, high + 1))
    else yankRange(low, Grammar.trimExclusive(plain(), low, high))
  }

  // [from, to) to the clipboard, lit for a beat; the cursor goes to its start,
  // as vim's does.
  function yankRange (from, to) {
    if (to <= from) return
    copy(Transcript.cut(plain().substring(from, to), from, leadRanges()))
    placeCursor(from)
    flash(from, to)
  }

  // Lit by selecting it, flagged: a selection appearing on the text is
  // otherwise taken for a mouse drag and starts visual mode.
  function flash (from, to) {
    flashing = true
    answer.select(from, to)
    rangeFlash.restart()
  }

  function endFlash () {
    rangeFlash.stop()
    if (!flashing) return
    flashing = false
    if (!selecting) {
      answer.deselect()
      answer.cursorPosition = cursor
    }
  }

  // iw, a", i( … on the line under the cursor: yanked after y, selected in
  // visual mode.
  function takeObject (scope, object, operator) {
    const range = TextObjects.isTextObject(object) ? TextObjects.resolveInLine(plain(), cursor, scope, object) : null
    if (!range) return
    if (operator === "y") {
      yankRange(range.start, range.end)
      return
    }
    if (!selecting) return
    linewise = false
    anchor = range.start
    placeCursor(Math.max(range.start, range.end - 1), true)
  }

  // p and P hand text to the ask bar, where it can be edited: the selection
  // in visual mode, else "" and the field reads the clipboard, where every
  // yank here lands.
  function put (after) {
    const value = selection()
    if (selecting) stopSelecting()
    putRequested(value, after)
  }

  // gc: the selection, else the displayed line under the cursor — the same unit
  // yy takes — over in the ask bar to ask a question about.
  function askAbout () {
    let text = ""
    if (selecting) {
      text = selection()
      stopSelecting()
    } else {
      const from = lineStartAt(cursor)
      const next = lineFrom(cursor, 1, 0)
      const to = next < 0 ? answer.length : lineStartAt(next)
      text = Transcript.cut(plain().substring(from, to), from, leadRanges())
    }
    if (text.trim()) askRequested(text)
  }

  // gs: the selection, else the word under the cursor, the way vim's * takes one.
  // A selection is already a whole query, so Search.qml runs it rather than
  // leaving it in the field.
  function searchFor () {
    const text = (selecting ? selection() : wordUnderCursor()).trim()
    if (selecting) stopSelecting()
    if (text) searchRequested(text)
  }

  function wordUnderCursor () {
    const source = plain()
    const range = TextObjects.resolveInLine(source, cursor, "i", "w")
    return range ? source.substring(range.start, range.end) : ""
  }

  // gx: the link under the cursor, whether the agent wrote it as Markdown (a
  // real anchor) or bare in the text.
  function linkUnder (pos) {
    // Read the character's anchor metadata directly: layout hit-testing can
    // resolve a neighboring paragraph after rich-text margins and wrapping.
    const href = Urls.hrefFromHtml(answer.getFormattedText(pos, Math.min(answer.length, pos + 1)))
    const url = href || Urls.urlAt(plain(), pos)
    return Urls.isOpenable(url) ? url : ""
  }

  function openLink () {
    const url = selecting ? Urls.urlFromSelection(selection()) : linkUnder(cursor)
    if (!url) return
    if (selecting) stopSelecting()
    linkOpened(url)
  }

  // The selection; else the reply under the cursor and the question it
  // answers, as the agent wrote it, so its Markdown links survive the draft.
  function handOff () {
    if (selecting) {
      const context = selection()
      stopSelecting()
      handedOff(context)
      return
    }
    const r = Transcript.replyIndexAt(cursor, questionStarts, replyStarts)
    handedOff(r === -1 ? Transcript.conversationText(turns) : Transcript.exchangeText(turns, replyTurns[r]))
  }

  function handOffAll () {
    if (selecting) stopSelecting()
    handedOff(Transcript.conversationText(turns))
  }

  // A reply yanked whole is lit for a beat.
  Timer {
    id: replyFlash

    interval: 250
    onTriggered: view.yankBand = null
  }

  Timer {
    id: rangeFlash

    interval: 250
    onTriggered: view.endFlash()
  }

  Timer {
    id: yankFlash

    interval: 250
    onTriggered: view.stopSelecting()
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    following = false        // the reader is reading; stop dragging them to the newest line
    // An open prompt takes every key into the pattern before the grammar sees one.
    if (finder.feed(event)) {
      event.accepted = true
      return
    }
    const chord = Chord.of(event)
    if (chord !== "" && chord === view.chords.newSession) {
      grammar = Grammar.IDLE
      newSessionRequested()
      event.accepted = true
      return
    }
    const step = Grammar.feed(grammar, chord, readerKeys, selecting, repeatFindReady ? lastFind : null)
    grammar = step.state
    if (!step.action && chord !== "") {
      const onlyCount = grammar.count > 0 && grammar.keys === "" && grammar.before === 0 &&
        grammar.operator === "" && grammar.find === "" && grammar.scope === ""
      if (!onlyCount) repeatFindReady = false
    }
    perform(step.action)
    event.accepted = true
  }

  function perform (action) {
    if (!action) return
    if (action.type !== "find" && action.type !== "repeatFind") repeatFindReady = false
    switch (action.type) {
    case "command": {
      const target = motionTarget(action.command, action.count)
      if (target) go(target, action.operator)
      else if (!action.operator) run(action.command, action.count)   // y then a non-motion: dropped, as vim does
      break
    }
    case "find":
      {
        const target = findTarget(action.command, action.char, action.count, false)
        if (target.pos >= 0) {
          lastFind = { command: action.command, char: action.char }
          repeatFindReady = true
          currentFindHit = Motions.findMatchPosition(target.pos, action.command)
        }
        go(target, action.operator)
      }
      break
    case "repeatFind":
      if (!lastFind) break
      {
        const command = action.command || (action.reverse ? Motions.flipFind(lastFind.command) : lastFind.command)
        const target = findTarget(command, lastFind.char, action.count, true)
        if (target.pos >= 0) {
          if (action.command) lastFind = { command: command, char: lastFind.char }
          repeatFindReady = true
          currentFindHit = Motions.findMatchPosition(target.pos, command)
        }
        go(target, action.operator)
      }
      break
    case "object": takeObject(action.scope, action.object, action.operator); break
    case "line":   yankLines(action.count); break
    }
  }

  function run (command, count) {
    const times = count === undefined ? 1 : Math.max(1, count)
    switch (command) {
    case "settings":     settingsRequested(); break
    case "toggleMode":   tabbed(); break
    // L / H walk the ring, as h and l page the results; ctrl+n lands here too.
    case "nextSession":  sessionWalked(times); break
    case "previousSession": sessionWalked(-times); break
    case "closeSession": closeSessionRequested(); break
    case "clearSessions": clearSessionsRequested(); break
    case "stopAnswer":   stopRequested(); break
    case "retryAnswer":  retryRequested(); break
    case "handOff":      handOff(); break
    case "handOffPage":  handOffAll(); break
    case "accept":       openLink(); break
    // Esc leaves one step at a time, and a search is one of them: drop the
    // selection, then the search and its highlight, and only then the pane.
    case "cancel":
      if (selecting) stopSelecting()
      else if (finder.lastPattern) finder.forget()
      else escaped()
      break
    case "fieldNormal":  if (selecting) stopSelecting(); normalRequested(); break
    case "insert":       insertRequested(); break
    case "append":       appendRequested(); break
    case "selectChars": if (selecting && !linewise) stopSelecting(); else startSelecting(false); break
    case "selectLines": if (selecting && linewise) stopSelecting(); else startSelecting(true); break
    case "reselect":    reselect(); break
    case "yank":        yank(); break
    case "openLink":    openLink(); break
    case "searchFor":   searchFor(); break
    case "askAbout":    askAbout(); break
    case "put":         put(true); break
    case "putBefore":   put(false); break
    case "findForward":  finder.open(false, cursor); break
    case "findBackward": finder.open(true, cursor); break
    case "searchWord":     searchWordUnderCursor(false); break
    case "searchWordBack": searchWordUnderCursor(true); break
    }
  }

  Flickable {
    id: flick

    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: answer.contentHeight + answer.topPadding + answer.bottomPadding
    boundsBehavior: Flickable.StopAtBounds

    // The gutter is outside the TextEdit text, so yanks never include numbers.
    Repeater {
      model: view.lineNumbers === "hide" ? [] : view.numberedLines

      Text {
        required property int index
        required property var modelData
        z: 2
        x: Style.spacing.xs
        y: modelData.y
        width: gutterMetrics.advanceWidth
        height: modelData.height
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        text: view.lineNumbers === "relative" ? Math.abs(index - view.cursorLine) : index + 1
        color: view.activeFocus && Math.abs(view.cursorRect.y - modelData.y) < 1
          ? view.accent : Util.alpha(view.foreground, 0.45)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    TextMetrics {
      id: gutterMetrics
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
      // Character count bounds line count without a width/line-count feedback loop.
      text: "8".repeat(Math.max(2, String(answer.length).length))
    }

    // A quiet bar behind each question, as Claude Code draws a prompt.
    Repeater {
      model: view.marks

      Rectangle {
        required property var modelData

        x: 0
        y: modelData.y - Style.spacing.xs
        width: flick.width
        height: modelData.height + Style.spacing.xs * 2
        color: Util.alpha(view.foreground, 0.07)
        radius: Style.cornerRadius
      }
    }

    // Cursorline: the caret alone is easy to lose in a long answer.
    Rectangle {
      visible: view.activeFocus && !view.selecting
      x: 0
      y: view.cursorRect.y - Style.spacing.xxs
      width: flick.width
      height: view.cursorRect.height + Style.spacing.xxs * 2
      color: Util.alpha(view.foreground, 0.06)
    }

    // Every reply's dot, drawn over the transparent ● that holds its place in
    // the text, so it matches the breathing one below in size, colour and
    // position.
    Repeater {
      model: view.dots

      Rectangle {
        required property var modelData

        z: 1
        x: modelData.x
        y: modelData.y
        width: view.dotDiameter
        height: width
        radius: width / 2
        color: view.answerColor
      }
    }

    // The reply being waited for. Its placeholder paragraph is laid out like any
    // reply, so this dot and the label sit exactly where the answer will land.
    Rectangle {
      z: 1
      visible: view.thinking && view.pendingDot !== null
      x: view.pendingDot ? view.pendingDot.x : 0
      y: view.pendingDot ? view.pendingDot.y : 0
      width: view.dotDiameter
      height: width
      radius: width / 2
      color: view.answerColor

      SequentialAnimation on opacity {
        running: view.thinking && view.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.2; duration: Thinking.PULSE_MS / 2; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Thinking.PULSE_MS / 2; easing.type: Easing.InOutSine }
      }
    }

    Text {
      id: waitLabel

      z: 1
      visible: view.thinking && view.pendingText !== null
      x: view.pendingText ? view.pendingText.x : 0
      y: view.pendingText ? Math.round(view.pendingText.baseline - baselineOffset) : 0
      textFormat: Text.PlainText
      // tick is read so the clock re-evaluates every frame.
      text: view.tick >= 0 ? Thinking.thinkingLabel(view.agentName, Date.now() - view.startedAt) : ""
      color: view.answerColor
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    Rectangle {
      visible: view.yankBand !== null
      x: 0
      y: view.yankBand ? view.yankBand.y - Style.spacing.xs : 0
      width: flick.width
      height: view.yankBand ? view.yankBand.height + Style.spacing.xs * 2 : 0
      color: Util.alpha(view.accent, 0.3)
      radius: Style.cornerRadius
    }

    // `/` matches, in the same language as the f/t ones above: the one the
    // cursor is on is accented, the rest are quiet.
    Repeater {
      model: view.searchMatches

      MatchHighlight {
        required property int modelData

        head: view.characterRect(modelData)
        tail: view.characterRect(
          Math.max(modelData, Math.min(answer.length, modelData + view.findPattern.length) - 1))
        current: modelData === view.cursor
        foreground: view.foreground
        accent: view.accent
      }
    }

    Repeater {
      model: view.findMatches

      MatchHighlight {
        required property int modelData

        head: view.characterRect(modelData)
        current: modelData === view.currentFindHit
        foreground: view.foreground
        accent: view.accent
      }
    }

    TextEdit {
      id: answer

      width: flick.width
      leftPadding: view.lineNumbers === "hide" ? Style.spacing.md
        : gutterMetrics.advanceWidth + Style.spacing.xs + Style.spacing.md
      rightPadding: Style.spacing.md
      topPadding: Style.spacing.xs
      bottomPadding: Style.spacing.xs
      readOnly: true
      selectByMouse: true
      persistentSelection: true
      textFormat: TextEdit.RichText
      wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
      color: view.foreground
      selectionColor: view.accent
      selectedTextColor: Color.menu.background
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
      cursorVisible: view.activeFocus

      cursorDelegate: Rectangle {
        width: Math.max(2, metrics.averageCharacterWidth)
        color: view.accent
        opacity: view.activeFocus ? 0.55 : 0
        radius: 1

        FontMetrics { id: metrics; font: answer.font }
      }

      // The mouse selects too; a drag becomes the same selection v makes.
      onSelectedTextChanged: if (selectedText !== "" && !view.selecting && !view.flashing) {
        view.anchor = selectionStart
        view.cursor = selectionEnd
      }
      onWidthChanged: Qt.callLater(view.findMarks)
      onFontChanged: Qt.callLater(view.findMarks)
      onContentHeightChanged: Qt.callLater(view.findMarks)
    }
  }
}
