import QtQuick
import Quickshell
import qs.Commons
import "../lib/keys.mjs" as KeysLib
import "../lib/motions.mjs" as Motions
import "../lib/markdown.mjs" as Markdown
import "../lib/thinking.mjs" as Thinking
import "../lib/urls.mjs" as Urls
import "chord.js" as Chord

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
  property string pending: ""                  // an unfinished sequence: "g" after g
  property string newSessionChord: "C-c"          // from settings, already parsed
  property string cursorLink: ""               // the openable link under the cursor, or ""
  property real preferredX: -1                 // the column j/k try to keep
  property var marks: []                       // [{ y, height }] — where the questions are
  property var dots: []                        // [{ x, y }] — where each reply's dot goes
  property var replyStarts: []                 // plain-text index of each reply's ●
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
  signal escaped()                             // esc: back to the field, normal mode
  signal insertRequested()                     // i or /: back to the field, typing
  signal settingsRequested()
  signal tabbed()
  signal newSessionRequested()                 // the new-session chord, or the button

  onActiveFocusChanged: {
    pending = ""
    if (activeFocus) cursorLink = linkUnder(cursor)   // the layout may not have existed when the answer landed
  }
  onTurnsChanged: Qt.callLater(refresh)

  // An answer lands as two changes in one handler — the history, then the
  // status — and callLater folds them into one render.
  function refresh () {
    anchor = -1
    preferredX = -1
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
      pending: thinking
    })
  }

  function plain () { return answer.getText(0, answer.length) }

  function findMarks () {
    const source = plain()
    const bars = []
    const leads = []
    const starts = []
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
        from = at + line.length
      } else if (turn.role === "assistant") {
        const at = source.indexOf("●", from)
        if (at === -1) continue
        starts.push(at)
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
  }

  // Where a reply's text begins, and its baseline.
  function textAt (pos) {
    const r = answer.positionToRectangle(Math.min(answer.length, pos))
    return { x: r.x, baseline: r.y + r.height - labelMetrics.descent }
  }

  // A reply's dot: its right edge where the question's > ends, so the gap to
  // the text is the arrow's, and centred on the x-height of the text it leads.
  // One rule for finished and waiting replies alike.
  function dotAt (lead) {
    const text = textAt(lead + 2)
    const ink = arrowMetrics.tightBoundingRect
    return {
      x: Math.round(answer.positionToRectangle(lead).x + ink.x + ink.width - dotDiameter),
      y: Math.round(text.baseline - labelMetrics.xHeight / 2 - dotDiameter / 2)
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
  function moveLine (delta) {
    const rect = answer.positionToRectangle(cursor)
    if (preferredX < 0) preferredX = rect.x
    const step = Math.max(2, Math.round(rect.height / 4))
    let y = delta > 0 ? rect.y + rect.height + 1 : rect.y - 1
    while (y >= 0 && y <= answer.contentHeight) {
      const pos = answer.positionAt(preferredX, y)
      const landed = answer.positionToRectangle(pos)
      if (delta > 0 ? landed.y > rect.y : landed.y < rect.y) {
        placeCursor(pos, true)
        return
      }
      y += delta > 0 ? step : -step
    }
  }

  function halfPage (direction) {
    const rect = answer.positionToRectangle(cursor)
    if (preferredX < 0) preferredX = rect.x
    const y = Math.max(0, Math.min(answer.contentHeight - 1, rect.y + direction * flick.height / 2))
    placeCursor(answer.positionAt(preferredX, y), true)
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
    if (linewise) return answer.selectedText
    const from = Math.min(anchor, cursor)
    const to = Math.min(answer.length, Math.max(anchor, cursor) + 1)
    return answer.getText(from, to)
  }

  function yank () {
    const value = selecting ? selection() : plain()
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
    // The selection stays lit for a beat so the yank is seen to happen.
    if (selecting) yankFlash.restart()
  }

  // gx: the link under the cursor, whether the agent wrote it as Markdown (a
  // real anchor) or bare in the text.
  function linkUnder (pos) {
    const here = answer.positionToRectangle(pos)
    const next = answer.positionToRectangle(Math.min(answer.length, pos + 1))
    const x = next.y === here.y && next.x > here.x ? (here.x + next.x) / 2 : here.x + 1
    const y = here.y + here.height / 2
    // linkAt wants content coordinates, inside the padding, unlike the
    // rectangles positionToRectangle returns.
    const href = answer.linkAt(x - answer.leftPadding, y - answer.topPadding)
    const url = href || Urls.urlAt(plain(), pos)
    return Urls.isOpenable(url) ? url : ""
  }

  function openLink () {
    const url = selecting ? Urls.urlFromSelection(selection()) : linkUnder(cursor)
    if (!url) return
    if (selecting) stopSelecting()
    linkOpened(url)
  }

  function handOff () {
    const context = selection() || plain()
    if (selecting) stopSelecting()
    handedOff(context)
  }

  Timer {
    id: yankFlash

    interval: 250
    onTriggered: view.stopSelecting()
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    const chord = Chord.of(event)
    if (chord !== "" && chord === view.newSessionChord) {
      pending = ""
      newSessionRequested()
      event.accepted = true
      return
    }
    const step = KeysLib.resolve(KeysLib.ANSWER_KEYS, pending, chord)
    pending = step.pending
    run(step.command)
    event.accepted = true
  }

  function run (command) {
    switch (command) {
    case "settings":     settingsRequested(); break
    case "toggleMode":   tabbed(); break
    case "accept":       handOff(); break
    case "cancel":       if (selecting) stopSelecting(); else escaped(); break
    case "insert":       insertRequested(); break
    case "halfPageDown": halfPage(1); break
    case "halfPageUp":   halfPage(-1); break
    case "down":         moveLine(1); break
    case "up":           moveLine(-1); break
    case "right":        placeCursor(cursor + 1); break
    case "left":         placeCursor(cursor - 1); break
    case "top":          placeCursor(0); break
    case "bottom":       placeCursor(answer.length); break

    case "wordForward":     placeCursor(Motions.wordForward(plain(), cursor)); break
    case "wordForwardBig":  placeCursor(Motions.wordForward(plain(), cursor, true)); break
    case "wordBackward":    placeCursor(Motions.wordBackward(plain(), cursor)); break
    case "wordBackwardBig": placeCursor(Motions.wordBackward(plain(), cursor, true)); break
    case "wordEnd":         placeCursor(Motions.wordEnd(plain(), cursor)); break
    case "wordEndBig":      placeCursor(Motions.wordEnd(plain(), cursor, true)); break
    case "lineStart":       placeCursor(lineStartAt(cursor)); break
    case "lineEnd":         placeCursor(Math.max(lineStartAt(cursor), lineEndAt(cursor) - 1)); break  // on the last character, as vim puts it

    case "selectChars": if (selecting && !linewise) stopSelecting(); else startSelecting(false); break
    case "selectLines": if (selecting && linewise) stopSelecting(); else startSelecting(true); break
    case "reselect":    reselect(); break
    case "yank":        yank(); break
    case "openLink":    openLink(); break
    }
  }

  Flickable {
    id: flick

    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: answer.contentHeight + answer.topPadding + answer.bottomPadding
    boundsBehavior: Flickable.StopAtBounds

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

    TextEdit {
      id: answer

      width: flick.width
      leftPadding: Style.spacing.md
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
      onSelectedTextChanged: if (selectedText !== "" && !view.selecting) {
        view.anchor = selectionStart
        view.cursor = selectionEnd
      }
      onContentHeightChanged: Qt.callLater(view.findMarks)
    }
  }
}
