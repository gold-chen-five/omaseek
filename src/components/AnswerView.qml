import QtQuick
import Quickshell
import qs.Commons
import "../lib/motions.mjs" as Motions

// The agent's answer, read with vim keys.
//
// A read-only TextEdit rendering Markdown, walked by a cursor the way the
// search field is: j/k by line, h/l/w/b/e within one, 0/$ and gg/G, Ctrl+D/U
// half a screen. `v` starts a selection, `y` yanks it, and Enter hands it —
// or the whole answer, when nothing is selected — to the agent in a terminal.
// Line motions go through the TextEdit's own layout (positionAt and
// positionToRectangle) because wrapped Markdown has no line structure of its
// own to count; word motions reuse lib/motions.mjs on the plain text.
FocusScope {
  id: view

  property string text: ""
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  property int anchor: -1                      // visual mode's other end, or -1
  property bool pendingG: false
  property real preferredX: -1                 // the column j/k try to keep

  readonly property bool selecting: anchor !== -1

  signal handedOff(string context)             // Enter: give this to the agent
  signal escaped()                             // esc: back to the field, normal mode
  signal insertRequested()                     // i or /: back to the field, typing
  signal settingsRequested()
  signal tabbed()

  onActiveFocusChanged: pendingG = false
  onTextChanged: {
    anchor = -1
    preferredX = -1
    Qt.callLater(() => { answer.cursorPosition = answer.length; flick.contentY = Math.max(0, flick.contentHeight - flick.height) })
  }

  function plain () { return answer.getText(0, answer.length) }

  // Every motion ends here so the selection follows the cursor as one thing.
  function moveTo (pos, keepColumn) {
    const clamped = Math.max(0, Math.min(answer.length, pos))
    if (selecting) answer.select(anchor, clamped)
    else answer.cursorPosition = clamped
    if (!keepColumn) preferredX = -1
    ensureVisible()
  }

  function moveLine (delta) {
    const rect = answer.positionToRectangle(answer.cursorPosition)
    if (preferredX < 0) preferredX = rect.x
    const y = delta > 0 ? rect.y + rect.height + 1 : rect.y - 1
    if (y < 0 || y > answer.contentHeight) return
    moveTo(answer.positionAt(preferredX, y), true)
  }

  function lineStart () {
    const rect = answer.positionToRectangle(answer.cursorPosition)
    return answer.positionAt(0, rect.y + rect.height / 2)
  }

  function lineEnd () {
    const rect = answer.positionToRectangle(answer.cursorPosition)
    return answer.positionAt(answer.width, rect.y + rect.height / 2)
  }

  function halfPage (direction) {
    const rect = answer.positionToRectangle(answer.cursorPosition)
    if (preferredX < 0) preferredX = rect.x
    const y = Math.max(0, Math.min(answer.contentHeight - 1, rect.y + direction * flick.height / 2))
    moveTo(answer.positionAt(preferredX, y), true)
  }

  function ensureVisible () {
    const rect = answer.positionToRectangle(answer.cursorPosition)
    if (rect.y < flick.contentY) flick.contentY = rect.y
    else if (rect.y + rect.height > flick.contentY + flick.height) flick.contentY = rect.y + rect.height - flick.height
  }

  function startSelecting () {
    anchor = answer.cursorPosition
    answer.select(anchor, anchor)
  }

  function stopSelecting () {
    const pos = answer.cursorPosition
    anchor = -1
    answer.deselect()
    answer.cursorPosition = pos
  }

  function yank () {
    const value = selecting ? answer.selectedText : plain()
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
    if (selecting) stopSelecting()
  }

  function handOff () {
    const context = selecting && answer.selectedText ? answer.selectedText : plain()
    if (selecting) stopSelecting()
    handedOff(context)
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    const key = event.text
    const source = plain()
    const pos = answer.cursorPosition
    let g = false

    if (ctrl && (event.key === Qt.Key_S || event.key === Qt.Key_Comma)) {
      settingsRequested()
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      tabbed()
    } else if (event.key === Qt.Key_Escape) {
      if (selecting) stopSelecting()
      else escaped()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      handOff()
    } else if (ctrl && event.key === Qt.Key_D) {
      halfPage(1)
    } else if (ctrl && event.key === Qt.Key_U) {
      halfPage(-1)
    } else if (event.key === Qt.Key_Down || key === "j") {
      moveLine(1)
    } else if (event.key === Qt.Key_Up || key === "k") {
      moveLine(-1)
    } else if (event.key === Qt.Key_Right || key === "l") {
      moveTo(pos + 1)
    } else if (event.key === Qt.Key_Left || key === "h") {
      moveTo(pos - 1)
    } else if (key === "w") {
      moveTo(Motions.wordForward(source, pos))
    } else if (key === "W") {
      moveTo(Motions.wordForward(source, pos, true))
    } else if (key === "b") {
      moveTo(Motions.wordBackward(source, pos))
    } else if (key === "B") {
      moveTo(Motions.wordBackward(source, pos, true))
    } else if (key === "e") {
      moveTo(Motions.wordEnd(source, pos))
    } else if (key === "0" || key === "^" || event.key === Qt.Key_Home) {
      moveTo(lineStart())
    } else if (key === "$" || event.key === Qt.Key_End) {
      moveTo(lineEnd())
    } else if (key === "G") {
      moveTo(answer.length)
    } else if (key === "g") {
      if (pendingG) moveTo(0)
      g = !pendingG
    } else if (key === "v") {
      if (selecting) stopSelecting()
      else startSelecting()
    } else if (key === "y") {
      yank()
    } else if (key === "i" || key === "/") {
      insertRequested()
    }
    pendingG = g
    event.accepted = true
  }

  Flickable {
    id: flick

    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: answer.contentHeight
    boundsBehavior: Flickable.StopAtBounds

    TextEdit {
      id: answer

      width: flick.width
      readOnly: true
      selectByMouse: true
      persistentSelection: true
      textFormat: TextEdit.MarkdownText
      wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
      text: view.text
      color: view.foreground
      selectionColor: view.selectedBackground
      selectedTextColor: view.accent
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
      onSelectedTextChanged: if (selectedText !== "" && !view.selecting) view.anchor = selectionStart
    }
  }
}
