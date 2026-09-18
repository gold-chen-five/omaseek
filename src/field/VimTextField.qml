import QtQuick
import QtQuick.Controls
import qs.Commons
import "../vim/motions.mjs" as Motions
import "../vim/keybinds.mjs" as Keybinds
import "../vim/chord.js" as Chord
import "../vim/measure.js" as Measure
import "../vim"

// The search field with a vim editing model. This file holds the mode machine's
// state and routes each key: the panel's keys first (FieldPanelKeys), then
// insert mode (FieldInsert) or normal and visual (FieldNormal, with the key a
// command waits for in FieldPending); what the keys do to the text is
// FieldEdits. Cursor arithmetic lives in vim/motions.mjs, under test.
//
// A TextArea, not a TextField: a question can hold line breaks, which a
// TextInput strips. It never wraps — a long line scrolls sideways inside the
// frame Search.qml draws around it, as the single-line field did — so only a
// Ctrl+J and o/O add rows. The frame is the container's because the field scrolls.
TextArea {
  id: field

  property color foreground: Color.foreground
  property color accent: Color.accent
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property bool multiline: false            // AI mode: line-opening keys work
  property bool stoppable: false            // a reply is being written: q and esc stop it
  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), foreground, accent)
  readonly property real lineHeight: contentHeight / Math.max(1, lineCount)

  padding: 0
  background: null
  wrapMode: TextEdit.NoWrap
  selectByMouse: true
  color: foreground
  selectionColor: Style.selectionFillFor(foreground, accent)
  selectedTextColor: foreground
  placeholderTextColor: Qt.darker(foreground, 1.6)

  property string mode: "insert"            // insert | normal | visual
  property string register: ""              // vim's unnamed register

  // Pending state for multi-key sequences: 2dw, d3w, f{char}, r{char}, ...
  property int operatorCount: 1
  property string pendingOperator: ""
  property string pendingFind: ""           // f/F/t/T awaiting its target
  property int pendingReplace: 0            // r awaiting its character; value is the count
  property string pendingTextObject: ""     // i/a awaiting its object, as in diw
  property int pendingCount: 0
  property bool pendingG: false             // g awaiting its second key: gx
  property string lastFindCommand: ""       // for ; and ,
  property string lastFindChar: ""
  property bool repeatFindReady: false       // clever-f: fa, then f/F walk the same target
  property int currentFindHit: -1            // actual match; t/T leave the cursor beside it
  readonly property var findMatches: repeatFindReady
    ? Motions.matchingCharsInLine(text, currentFindHit, lastFindChar) : []
  property bool visualLinewise: false
  property int visualCursor: 0
  property int visualAnchor: -1

  // Insert-mode escape sequence (vim's `inoremap jk <Esc>`); empty turns it off.
  property var escapeSequences: []
  property int escapeTimeout: 200
  readonly property string lineBreak: "\n"      // what line-opening commands insert
  property string escapePending: ""          // sequence keys typed so far

  // The panel keys, already parsed, by action id. Checked before mode dispatch
  // so rebinding search moves it off Enter, and so a session key works from
  // insert mode without typing anything.
  property var chords: Keybinds.panelChords(null)

  signal submitted()
  signal cancelled()                        // Esc from normal mode
  signal steppedDown()                      // j / Down: the results are the "line" below
  signal historyPrevRequested()             // Up in the one-line search field: an older query
  signal historyNextRequested()             // Down there: back toward what was being typed
  signal requestedSettings()                // Ctrl+S (or Ctrl+,) in any mode
  signal tabbed()                           // Tab in any mode: the panel switches search <-> ai
  signal agentSwitchRequested()             // shift+tab: the next installed agent answers
  signal translateRequested(string text)    // gt on a selection, gT or ctrl+t on the whole bar
  signal newSessionRequested()              // the new-session chord: start over
  signal nextSessionRequested()             // the next saved conversation
  signal sessionWalked(int delta)           // L / H in normal mode: through the ring

  // The keys normal mode reads beyond vim's own, by action id: the answer's L and
  // H, and U for what was searched or asked before.
  property var normalChords: ({})
  signal closeSessionRequested()            // forget this conversation
  signal clearSessionsRequested()           // forget all of them
  signal linkOpened(string url)             // gx: the URL under the cursor, or selected
  signal stopRequested()                    // stop the reply being written
  signal retryRequested()                   // ask the last question again

  readonly property bool normalish: mode !== "insert"

  function setMode (next) {
    if (next === "normal" && mode === "insert") {
      cursorPosition = Motions.insertExit(text, cursorPosition)
    }
    if (next !== "visual") {
      if (mode === "visual" && visualLinewise) cursorPosition = visualCursor
      visualLinewise = false
      visualAnchor = -1
      deselect()
    }
    mode = next
    clearPending()
    if (next === "normal") clampCursor()
  }

  // Enter from a reading pane exactly as the matching normal-mode command
  // would: i inserts at the cursor, while a advances one character first.
  function enterInsert (motion) {
    clearPending()
    normalKeys.handleNormalKey(motion === "a" ? "a" : "i")
  }

  function clearPending () {
    pendingOperator = ""
    operatorCount = 1
    pendingFind = ""
    pendingReplace = 0
    pendingTextObject = ""
    pendingCount = 0
    pendingG = false
    repeatFindReady = false
    currentFindHit = -1
  }

  function takeCount (fallback) {
    const count = pendingCount > 0 ? pendingCount : fallback
    pendingCount = 0
    return count
  }

  // The panel replaces what was typed while walking the query history. Set
  // through here so the cursor lands at the end, as it does in a shell.
  function setQuery (value) {
    text = value
    cursorPosition = length
    clampCursor()
  }

  function clampCursor () {
    if (mode === "insert") return
    cursorPosition = Motions.clampToLine(text, cursorPosition)
  }

  function characterRect (pos) {
    return Measure.characterRect(field, pos, metrics.averageCharacterWidth)
  }

  onModeChanged: {
    if (mode !== "visual") deselect()
    insertKeys.clearEscapePending()                      // a half-typed sequence dies with the mode
  }

  FontMetrics { id: metrics; font: field.font }

  Repeater {
    model: field.findMatches

    MatchHighlight {
      required property int modelData

      head: field.characterRect(modelData)
      current: modelData === field.currentFindHit
      foreground: field.foreground
      accent: field.accent
    }
  }

  cursorDelegate: Rectangle {
    width: field.normalish ? Math.max(2, metrics.averageCharacterWidth) : Math.max(1, Style.space(1))
    color: field.normalish ? Color.menu.selectedText : field.foreground
    opacity: field.normalish ? 0.55 : 1.0
    radius: 1

  }

  // p and P from the answer arrive here: what to put, and on which side.
  function put (after, value) {
    edits.put(after, value)
  }

  FieldPanelKeys { id: panelKeysPart; field: field }
  FieldInsert { id: insertPart; field: field }
  FieldNormal { id: normalPart; field: field }
  FieldPending { id: pendingPart; field: field }
  FieldEdits { id: editsPart; field: field }

  // The parts, reached from each other as field.<part>.
  readonly property var panelKeys: panelKeysPart
  readonly property var insertKeys: insertPart
  readonly property var normalKeys: normalPart
  readonly property var pending: pendingPart
  readonly property var edits: editsPart

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    // The panel's own keys, in every mode, before the field types anything.
    const command = panelKeys.panelCommand(Chord.of(event))
    if (command !== "") {
      panelKeys.raisePanel(command)
      event.accepted = true
      return
    }
    if (mode === "insert") insertKeys.handleInsertKey(event)
    else normalKeys.press(event)
  }
}
