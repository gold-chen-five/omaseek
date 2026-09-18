import QtQuick
import qs.Commons
import qs.Ui
import "../shared/vim/keys.mjs" as KeysLib
import "../shared/vim/find.mjs" as Find
import "../shared/vim/chord.js" as Chord
import "../shared/vim"

// Result rows and the vim cursor that walks them; anything that changes the view
// is raised as a signal.
ListView {
  id: list

  property var binds: null               // the settings: where the rebindable commands sit
  readonly property var readerKeys: KeysLib.readerKeys("results", binds)
  property string lineNumbers: "relative"
  property var navigation: ({ pending: "", count: 0 })

  signal handedOff(int index)
  signal pageHandedOff()
  signal yanked(int index, bool withTitle)   // y / Y: the URL, or the title above it
  signal askRequested(int index)             // gc: this result, over in the ask bar
  signal searchRequested(int index)          // gs: search for this result's title
  signal activated(int index)
  signal escaped()                       // esc: back to the field, normal mode
  signal normalRequested()               // /: back to the field, normal mode
  signal insertRequested()               // i: back to the field, insert before the cursor
  signal appendRequested()               // a: back to the field, insert after the cursor
  signal settingsRequested()
  signal tabbed()                        // the panel switches search <-> ai
  signal agentSwitchRequested()          // shift+tab: the next installed agent answers
  signal closeSessionRequested()         // ctrl+x: close the translation beside the list
  signal paneRightRequested()            // ctrl+l: into the translation beside it
  signal nextPageRequested(int pages)    // 5l: five pages on
  signal previousPageRequested(int pages)
  signal pageJumpRequested(int page)     // 5gp: page five, fetching its way there

  readonly property string findPrompt: finder.prompt
  // What the rows mark. It outlives the prompt, as the answer's highlight does.
  readonly property string findPattern: finder.active ? finder.find.pattern : finder.lastPattern

  // What `/` matches here: a row, on anything the row shows.
  Finder {
    id: finder

    matchesFor: (pattern, wholeWord) => Find.matchingRows(list.visibleRows(), pattern)

    onMoved: target => list.moveCursorTo(target)
    onDropped: target => list.moveCursorTo(target)
  }

  // The page on screen as plain rows, for the search to read.
  function visibleRows () {
    const rows = []
    for (let i = 0; i < count; i++) {
      const row = model.get(i)
      rows.push({ title: row.title, snippet: row.snippet, display_url: row.display_url, url: row.url })
    }
    return rows
  }

  clip: true
  keyNavigationEnabled: false            // the handler below drives j/k and the arrows
  boundsBehavior: Flickable.StopAtBounds
  currentIndex: 0
  spacing: Style.spacing.xxs
  highlightMoveDuration: 0
  cacheBuffer: 400                       // keep favicons alive just off-screen

  // Rows sliding under a stationary pointer would otherwise fire hover events
  // and yank the cursor away from wherever the keyboard put it.
  PointerMoveGate {
    id: pointerGate
    referenceItem: list
  }

  onActiveFocusChanged: { navigation = { pending: "", count: 0 }; finder.forget() }
  onModelChanged: { navigation = { pending: "", count: 0 }; finder.close() }

  function moveCursor (delta) {
    moveCursorTo(currentIndex + delta)
  }

  function moveCursorTo (index) {
    if (count === 0) return
    pointerGate.reset()
    currentIndex = Math.max(0, Math.min(count - 1, index))
    positionViewAtIndex(currentIndex, ListView.Contain)
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    // An open prompt takes every key into the pattern before the table sees one.
    if (finder.feed(event)) {
      event.accepted = true
      return
    }
    const step = KeysLib.resolveCounted(readerKeys, navigation, Chord.of(event))
    navigation = step.state
    run(step.command, step.count)
    event.accepted = true
  }

  function run (command, times) {
    const rowHeight = Math.max(1, contentHeight / Math.max(1, count))
    const pageStep = Math.max(1, Math.floor(height / rowHeight / 2))

    switch (command) {
    case "settings":     settingsRequested(); break
    case "toggleMode":   tabbed(); break
    case "switchAgent":  agentSwitchRequested(); break
    // ctrl+x: the translation panel, when it is open — the list has no
    // conversation of its own to forget.
    case "closeSession": closeSessionRequested(); break
    case "paneRight":    paneRightRequested(); break
    case "accept":       activated(currentIndex); break
    case "handOff":      if (count > 0) handedOff(currentIndex); break
    case "handOffPage":  if (count > 0) pageHandedOff(); break
    case "yankUrl":      if (count > 0) yanked(currentIndex, false); break
    case "yankCitation": if (count > 0) yanked(currentIndex, true); break
    case "askAbout":     if (count > 0) askRequested(currentIndex); break
    case "searchFor":    if (count > 0) searchRequested(currentIndex); break
    // As in the answer: the search goes before the pane does.
    case "cancel":       if (finder.lastPattern) finder.forget(); else escaped(); break
    case "fieldNormal":  normalRequested(); break
    case "insert":       insertRequested(); break
    case "append":       appendRequested(); break
    case "halfPageDown": moveCursor(pageStep * times); break
    case "halfPageUp":   moveCursor(-pageStep * times); break
    case "down":         moveCursor(times); break
    case "up":           moveCursor(-times); break
    case "nextPage":     nextPageRequested(times); break
    case "goToPage":     pageJumpRequested(times); break
    case "previousPage": previousPageRequested(times); break
    case "top":          moveCursorTo(0); break
    case "bottom":       moveCursorTo(count - 1); break
    case "findForward":  finder.open(false, currentIndex); break
    case "findBackward": finder.open(true, currentIndex); break
    case "findNext":     finder.step(false, currentIndex, times); break
    case "findPrevious": finder.step(true, currentIndex, times); break
    }
  }

  // `index` and the model roles are required properties on ResultRow itself,
  // so the view fills them in; re-declaring them here would shadow the
  // injection and leave the delegate uninitialized.
  delegate: ResultRow {
    id: rowItem

    width: list.width
    lineNumbers: list.lineNumbers
    highlight: list.findPattern
    cursorIndex: list.currentIndex
    numberDigits: String(Math.max(1, list.count)).length
    hasCursor: rowItem.index === list.currentIndex

    onHovered: mouse => {
      if (pointerGate.moved(rowItem, mouse)) list.currentIndex = rowItem.index
    }
    onActivated: {
      list.currentIndex = rowItem.index
      list.activated(rowItem.index)
    }
  }
}
