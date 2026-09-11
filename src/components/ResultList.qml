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
  property string pending: ""                  // an unfinished sequence: "g" after g

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

  onActiveFocusChanged: pending = ""

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
    const step = KeysLib.resolve(KeysLib.LIST_KEYS, pending, Chord.of(event))
    pending = step.pending
    run(step.command)
    event.accepted = true
  }

  function run (command) {
    const rowHeight = Math.max(1, contentHeight / Math.max(1, count))
    const pageStep = Math.max(1, Math.floor(height / rowHeight / 2))

    switch (command) {
    case "settings":     settingsRequested(); break
    case "toggleMode":   tabbed(); break
    case "accept":       activated(currentIndex); break
    case "cancel":       escaped(); break
    case "insert":       insertRequested(); break
    case "halfPageDown": moveCursor(pageStep); break
    case "halfPageUp":   moveCursor(-pageStep); break
    case "down":         moveCursor(1); break
    case "up":           moveCursor(-1); break
    case "right":        nextPageRequested(); break
    case "left":         previousPageRequested(); break
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
