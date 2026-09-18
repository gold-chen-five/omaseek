import QtQuick
import qs.Commons
import "../../core/thinking.mjs" as Thinking
import "../../vim/measure.js" as Measure
import "../../vim"

// What the answer draws: the transcript's TextEdit, and around it the line
// numbers in their gutter, a bar behind each question, each reply's dot, the
// breathing dot and label of a reply still coming, the cursorline, a yank lit
// for a beat, and the / and f/t matches. Drawn from the view's state (`view`);
// the view reaches the TextEdit as `edit`.
Flickable {
  id: flick

  property var view: null
  readonly property alias edit: answer

  // A character's box, for the match highlights: positionToRectangle gives a
  // caret, and its width is worth deriving once.
  function characterRect (pos) {
    return Measure.characterRect(answer, pos, charMetrics.averageCharacterWidth)
  }

  FontMetrics {
    id: charMetrics
    font.family: flick.view ? flick.view.fontFamily : ""
    font.pixelSize: Style.font.body
  }

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
    // Only until the first words arrive: a streamed reply is written into the
    // very paragraph this label sits on, and drawn over it the two became one
    // unreadable line. The breathing dot stays, and says it is still coming.
    visible: view.thinking && view.pendingText !== null && view.streamText.trim() === ""
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

      head: flick.characterRect(modelData)
      tail: flick.characterRect(
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

      head: flick.characterRect(modelData)
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
    onWidthChanged: Qt.callLater(view.renderer.findMarks)
    onFontChanged: Qt.callLater(view.renderer.findMarks)
    onContentHeightChanged: Qt.callLater(view.renderer.findMarks)
  }
}
