import QtQuick
import qs.Commons
import qs.Ui
import "../lib/keys.mjs" as KeysLib
import "chord.js" as Chord

// Result rows and the vim cursor that walks them; anything that changes the view
// is raised as a signal.
ListView {
  id: list

  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily
  property var binds: null               // the settings: where the rebindable commands sit
  readonly property var readerKeys: KeysLib.readerKeys("results", binds)
  property string lineNumbers: "relative"
  property var navigation: ({ pending: "", count: 0 })

  signal handedOff(int index)
  signal pageHandedOff()
  signal activated(int index)
  signal escaped()                       // esc: back to the field, normal mode
  signal insertRequested()               // i or /: back to the field, typing
  signal settingsRequested()
  signal tabbed()                        // the panel switches search <-> ai
  signal nextPageRequested()
  signal previousPageRequested()

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

  onActiveFocusChanged: navigation = { pending: "", count: 0 }
  onModelChanged: navigation = { pending: "", count: 0 }

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
    case "accept":       activated(currentIndex); break
    case "handOff":      if (count > 0) handedOff(currentIndex); break
    case "handOffPage":  if (count > 0) pageHandedOff(); break
    case "cancel":       escaped(); break
    case "insert":       insertRequested(); break
    case "halfPageDown": moveCursor(pageStep * times); break
    case "halfPageUp":   moveCursor(-pageStep * times); break
    case "down":         moveCursor(times); break
    case "up":           moveCursor(-times); break
    case "nextPage":     nextPageRequested(); break
    case "previousPage": previousPageRequested(); break
    case "top":          moveCursorTo(0); break
    case "bottom":       moveCursorTo(count - 1); break
    }
  }

  // `index` and the model roles are required properties on ResultRow itself,
  // so the view fills them in; re-declaring them here would shadow the
  // injection and leave the delegate uninitialized.
  delegate: ResultRow {
    id: rowItem

    width: list.width
    lineNumbers: list.lineNumbers
    cursorIndex: list.currentIndex
    numberDigits: String(Math.max(1, list.count)).length
    hasCursor: rowItem.index === list.currentIndex
    foreground: list.foreground
    accent: list.accent
    selectedBackground: list.selectedBackground
    fontFamily: list.fontFamily

    onHovered: mouse => {
      if (pointerGate.moved(rowItem, mouse)) list.currentIndex = rowItem.index
    }
    onActivated: {
      list.currentIndex = rowItem.index
      list.activated(rowItem.index)
    }
  }
}
