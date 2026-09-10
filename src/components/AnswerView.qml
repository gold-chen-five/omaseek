import QtQuick
import Quickshell
import qs.Commons
import "../lib/keys.mjs" as KeysLib
import "../lib/motions.mjs" as Motions
import "../lib/markdown.mjs" as Markdown
import "chord.js" as Chord

// The conversation with the agent, read with vim keys.
//
// One read-only TextEdit renders the whole transcript, so the cursor and a
// selection can run across turns. It is drawn the way Claude Code draws its
// own: the question bright after a dim ">", on a quiet grey bar; the reply
// in a softer colour after a small dot. Two colours in one TextEdit means
// rich text, so the agent's Markdown goes through lib/markdown.mjs. The
// grey bars are rectangles painted behind the TextEdit at the lines each
// question occupies; the layout is asked where those lines are once it has
// settled.
//
// The cursor is walked the way the search field is: j/k by line, h/l/w/b/e
// within one, 0/$ and gg/G, Ctrl+D/U half a screen. `v` selects by character
// and `V` by line, `y` yanks (and leaves the selection lit for a moment, as
// LazyVim's yank highlight does), `gv` reselects, and Enter hands the
// selection — or the whole transcript, when nothing is selected — to the
// agent in a terminal. Line motions go through the TextEdit's own layout
// (positionAt and positionToRectangle) because wrapped Markdown has no line
// structure of its own to count; word motions reuse lib/motions.mjs on the
// plain text.
FocusScope {
  id: view

  property var turns: []                       // [{ role: 'user'|'assistant', text }]
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  property int cursor: 0                       // the reading position; the TextEdit follows it
  property int anchor: -1                      // visual mode's other end, or -1
  property bool linewise: false                // V rather than v
  property var lastVisual: null                // for gv: { anchor, cursor, linewise }
  property string pending: ""                  // an unfinished sequence: "g" after g
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
  signal escaped()                             // esc: back to the field, normal mode
  signal insertRequested()                     // i or /: back to the field, typing
  signal settingsRequested()
  signal tabbed()
  signal newSessionRequested()                 // ctrl+n, or the button

  onActiveFocusChanged: pending = ""
  onTurnsChanged: {
    anchor = -1
    preferredX = -1
    answer.text = render()
    // The layout settles after the text lands; only then are the line
    // rectangles real. Land on the newest answer, scrolled into view.
    Qt.callLater(() => { placeCursor(answer.length); findMarks() })
  }
  onWidthChanged: Qt.callLater(findMarks)

  function render () {
    return Markdown.renderTranscript(turns, {
      question: questionColor,
      answer: answerColor,
      glyph: glyphColor,
      error: Color.urgent.toString(),
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
    if (selecting) {
      if (linewise) answer.select(lineStartAt(Math.min(anchor, cursor)), lineEndAt(Math.max(anchor, cursor)))
      else answer.select(anchor, cursor)
    } else {
      answer.cursorPosition = cursor
    }
    if (!keepColumn) preferredX = -1
    ensureVisible()
  }

  function moveLine (delta) {
    const rect = answer.positionToRectangle(cursor)
    if (preferredX < 0) preferredX = rect.x
    const y = delta > 0 ? rect.y + rect.height + 1 : rect.y - 1
    if (y < 0 || y > answer.contentHeight) return
    placeCursor(answer.positionAt(preferredX, y), true)
  }

  function halfPage (direction) {
    const rect = answer.positionToRectangle(cursor)
    if (preferredX < 0) preferredX = rect.x
    const y = Math.max(0, Math.min(answer.contentHeight - 1, rect.y + direction * flick.height / 2))
    placeCursor(answer.positionAt(preferredX, y), true)
  }

  function ensureVisible () {
    const rect = answer.positionToRectangle(cursor)
    if (rect.y < flick.contentY) flick.contentY = rect.y
    else if (rect.y + rect.height > flick.contentY + flick.height) flick.contentY = rect.y + rect.height - flick.height
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
  }

  function reselect () {
    if (!lastVisual) return
    anchor = lastVisual.anchor
    linewise = lastVisual.linewise
    placeCursor(lastVisual.cursor, true)
  }

  function yank () {
    const value = selecting ? answer.selectedText : plain()
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
    // The selection stays lit for a beat so the yank is seen to happen.
    if (selecting) yankFlash.restart()
  }

  function handOff () {
    const context = selecting && answer.selectedText ? answer.selectedText : plain()
    if (selecting) stopSelecting()
    handedOff(context)
  }

  // Ends the conversation without leaving the panel. It sits over the
  // transcript rather than in the status strip, because it is only ever
  // wanted when there is a conversation to end — and it names its key, so
  // the shortcut is learnt from using the button.
  Rectangle {
    id: newChatButton

    visible: view.turns.length > 0
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.sm
    z: 2
    width: newChatLabel.implicitWidth + Style.space(20)
    height: newChatLabel.implicitHeight + Style.space(10)
    radius: 0
    color: newChatArea.containsMouse ? Util.alpha(view.foreground, 0.12)
                                     : Util.alpha(view.foreground, 0.05)
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(view.foreground, newChatArea.containsMouse ? 0.38 : 0.18)

    Text {
      id: newChatLabel

      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "new chat  ⌃N"
      color: view.foreground
      opacity: newChatArea.containsMouse ? 0.9 : 0.55
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: newChatArea

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: view.newSessionRequested()
    }
  }

  Timer {
    id: yankFlash

    interval: 250
    onTriggered: view.stopSelecting()
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    const step = KeysLib.resolve(KeysLib.ANSWER_KEYS, pending, Chord.of(event))
    pending = step.pending
    run(step.command)
    event.accepted = true
  }

  // What this pane makes of the shared vocabulary: sideways is a character,
  // the ends are the ends of the transcript, and Enter hands over what is
  // selected. The word motions are the search field's, on the plain text.
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
    case "lineStart":       placeCursor(lineStartAt(cursor)); break
    case "lineEnd":         placeCursor(lineEndAt(cursor)); break

    case "selectChars": if (selecting && !linewise) stopSelecting(); else startSelecting(false); break
    case "selectLines": if (selecting && linewise) stopSelecting(); else startSelecting(true); break
    case "reselect":    reselect(); break
    case "yank":        yank(); break
    case "newSession":  newSessionRequested(); break
    }
  }

  Flickable {
    id: flick

    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: answer.contentHeight + answer.topPadding + answer.bottomPadding
    boundsBehavior: Flickable.StopAtBounds

    // Painted behind the text: one quiet block per question, the grey box
    // Claude Code puts a prompt in. No accent — the reply is the content.
    Repeater {
      model: view.marks

      Rectangle {
        required property var modelData

        x: 0
        y: modelData.y - Style.spacing.xs
        width: flick.width
        height: modelData.height + Style.spacing.xs * 2
        color: Util.alpha(view.foreground, 0.07)     // a flat bar, as Claude Code draws it
      }
    }

    TextEdit {
      id: answer

      width: flick.width
      leftPadding: Style.spacing.md
      // Wide enough on the right for the new-chat button to float over the
      // gutter rather than over the first question.
      rightPadding: newChatButton.visible
        ? newChatButton.width + Style.spacing.md + Style.spacing.sm
        : Style.spacing.md
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

      // A block cursor, as in the field's normal mode: the reading position
      // has to be visible for j/k and v to mean anything.
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
