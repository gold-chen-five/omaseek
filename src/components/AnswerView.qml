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
      Qt.callLater(() => { flick.contentY = Math.max(0, flick.contentHeight - flick.height) })
    }
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
  onTurnsChanged: {
    anchor = -1
    preferredX = -1
    answer.text = render()
    // Once the layout settles, land at the start of the newest reply so j reads
    // down through it.
    Qt.callLater(() => { placeCursor(startOfNewest()); findMarks() })
  }

  function startOfNewest () {
    const last = turns.length > 0 ? turns[turns.length - 1] : null
    if (!last || last.role !== "assistant") return answer.length
    const source = plain()
    const at = source.lastIndexOf("●")
    return at === -1 ? answer.length : Math.min(answer.length, at + 2)
  }
  onWidthChanged: Qt.callLater(findMarks)

  function render () {
    return Markdown.renderTranscript(turns, {
      question: questionColor,
      answer: answerColor,
      glyph: glyphColor,
      error: Color.urgent.toString(),
      link: questionColor,  // theme ink, not Qt's link blue
      dotSize: Math.round(Style.font.body * 0.6)
    })
  }

  function plain () { return answer.getText(0, answer.length) }

  function findMarks () {
    const source = plain()
    const found = []
    let from = 0
    for (let i = 0; i < turns.length; i++) {
      if (turns[i].role !== "user") continue
      const line = prompt + String(turns[i].text)
      const at = source.indexOf(line, from)
      if (at === -1) continue
      const first = answer.positionToRectangle(at)
      const last = answer.positionToRectangle(Math.max(at, at + line.length - 1))
      found.push({ y: first.y, height: last.y + last.height - first.y })
      from = at + line.length
    }
    marks = found
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
                   + (spinner.visible ? spinner.height + Style.spacing.xs : 0)
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

    // Where the reply's dot will be, so the answer replaces it in place.
    Row {
      id: spinner

      visible: view.thinking
      x: answer.leftPadding
      y: answer.contentHeight + answer.topPadding + answer.bottomPadding
      spacing: Style.spacing.xs

      // One dot, breathing slowly, in the colour of the text beside it. Drawn
      // rather than typed: a small glyph sits on its own baseline, low against
      // the label, so this is centred on the label's x-height instead.
      Rectangle {
        width: Math.round(Style.font.body * 0.55)
        height: width
        radius: width / 2
        color: view.answerColor
        y: Math.round(waitLabel.y + waitLabel.baselineOffset - labelMetrics.xHeight / 2 - height / 2)

        SequentialAnimation on opacity {
          running: view.thinking && view.visible
          loops: Animation.Infinite
          NumberAnimation { to: 0.2; duration: Thinking.PULSE_MS / 2; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: Thinking.PULSE_MS / 2; easing.type: Easing.InOutSine }
        }
      }
      Text {
        id: waitLabel

        textFormat: Text.PlainText
        // tick is read so the clock re-evaluates every frame.
        text: view.tick >= 0 ? Thinking.thinkingLabel(view.agentName, Date.now() - view.startedAt) : ""
        color: view.answerColor
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
      }
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
