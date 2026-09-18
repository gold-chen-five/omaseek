import QtQuick
import qs.Commons
import "../shared/vim/keys.mjs" as KeysLib
import "../shared/vim/find.mjs" as Find
import "../shared/vim/motions.mjs" as Motions
import "../shared/vim/grammar.mjs" as Grammar
import "../shared/vim/keybinds.mjs" as Keybinds
import "../shared/thinking.mjs" as Thinking
import "../shared/urls.mjs" as Urls
import "../shared/vim"
import "answer"

// The transcript, read with vim keys. One read-only rich-text TextEdit holds
// every turn, so the cursor and a selection can cross turns. This file holds
// the reading state and the signals; its parts in answer/ do the work —
// AnswerLayer draws, AnswerRender renders and finds the marks, AnswerMotion
// moves the cursor, AnswerSelection selects and yanks, AnswerActions hands text
// to the panel, AnswerKeys dispatches the keys.
FocusScope {
  id: view

  property var turns: []                       // [{ role: 'user'|'assistant', text }]
  property bool thinking: false
  property string agentName: ""

  property int tick: 0
  property real startedAt: 0

  // The question a reply is on its way for, so its landing can be told apart
  // from another conversation coming on screen.
  property string waitingFor: ""

  onThinkingChanged: {
    if (thinking) {
      startedAt = Date.now()
      tick = 0
    }
    Qt.callLater(renderer.refresh)
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

  // The parts, reached from each other as view.<part>: what the answer draws,
  // how it renders, where keys move the cursor, the selection and yanks, and
  // what it hands to the rest of the panel.
  readonly property Item answer: layerPart.edit
  readonly property Item flick: layerPart
  readonly property var renderer: renderPart
  readonly property var mover: motionPart
  readonly property var selector: selectionPart
  readonly property var actions: actionsPart
  readonly property var keys: keysPart
  readonly property Item finder: finderPart

  Finder {
    id: finderPart

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
  signal agentSwitchRequested()                // shift+tab: the next installed agent answers
  signal translateRequested(string text)       // gt: the selection, or the word under the cursor
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
  onTurnsChanged: Qt.callLater(renderer.refresh)

  onWidthChanged: Qt.callLater(renderer.findMarks)

  // A reply arriving in pieces is not a new answer: the text is replaced, but
  // the cursor stays where the reader put it and settle() is not run, or every
  // repaint would drag them to the newest line.
  onStreamTextChanged: if (thinking) Qt.callLater(renderer.restream)

  // The text as lines. A paragraph ends in U+2029 and a <br> in a question in
  // U+2028, not \n; swapping each for \n — one character for one — keeps every
  // position where it was, lets a question typed on several lines be found
  // again by its text, and gives h, l, f, t and the text objects the line ends
  // they stop at. Without it the whole transcript read as a single line.
  function plain () {
    return answer.getText(0, answer.length).replace(/[\u2028\u2029]/g, "\n")
  }

  // Every motion ends here so the selection follows the cursor as one thing.
  function placeCursor (pos, keepColumn) {
    cursor = Math.max(0, Math.min(answer.length, pos))
    cursorLink = selecting ? Urls.urlFromSelection(selector.selection()) : linkUnder(cursor)
    if (selecting) {
      if (linewise) answer.select(mover.lineStartAt(Math.min(anchor, cursor)), mover.lineEndAt(Math.max(anchor, cursor)))
      else answer.select(anchor, cursor)
    } else {
      answer.cursorPosition = cursor
    }
    if (!keepColumn) preferredX = -1
    mover.ensureVisible()
  }

  // Where the cursor is drawn — for the cursorline and the line numbers.
  // AnswerMotion's ensureVisible sets it as it scrolls the line into view.
  property rect cursorRect: Qt.rect(0, 0, 0, 0)

  // gx: the link under the cursor, whether the agent wrote it as Markdown (a
  // real anchor) or bare in the text.
  function linkUnder (pos) {
    // Read the character's anchor metadata directly: layout hit-testing can
    // resolve a neighboring paragraph after rich-text margins and wrapping.
    const href = Urls.hrefFromHtml(answer.getFormattedText(pos, Math.min(answer.length, pos + 1)))
    const url = href || Urls.urlAt(plain(), pos)
    return Urls.isOpenable(url) ? url : ""
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => keysPart.press(event)

  AnswerLayer {
    id: layerPart
    view: view
    anchors.fill: parent
  }

  AnswerRender { id: renderPart; view: view }
  AnswerMotion { id: motionPart; view: view }
  AnswerSelection { id: selectionPart; view: view }
  AnswerActions { id: actionsPart; view: view }
  AnswerKeys { id: keysPart; view: view }
}
