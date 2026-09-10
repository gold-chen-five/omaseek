import QtQuick
import qs.Commons
import qs.Ui

// Result rows plus the vim cursor that walks them.
//
// The list owns the keys that move its own cursor; anything that changes what
// is on screen — a page turn, going back to the field, the settings page — is
// raised as a signal, so the focus machine stays in Search.qml.
ListView {
  id: list

  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily
  property bool pendingG: false          // first half of a gg

  signal activated(int index)
  signal escaped()                       // esc: back to the field, normal mode
  signal insertRequested()               // i or /: back to the field, typing
  signal settingsRequested()
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

  onActiveFocusChanged: pendingG = false

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
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    const rowHeight = Math.max(1, contentHeight / Math.max(1, count))
    const pageStep = Math.max(1, Math.floor(height / rowHeight / 2))

    if (ctrl && (event.key === Qt.Key_S || event.key === Qt.Key_Comma)) {
      settingsRequested()
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activated(currentIndex)
    } else if (event.key === Qt.Key_Escape) {
      escaped()
    } else if (ctrl && event.key === Qt.Key_D) {
      moveCursor(pageStep)
    } else if (ctrl && event.key === Qt.Key_U) {
      moveCursor(-pageStep)
    } else if (event.key === Qt.Key_Down || event.text === "j") {
      moveCursor(1)
    } else if (event.key === Qt.Key_Up || event.text === "k") {
      moveCursor(-1)
    } else if (event.key === Qt.Key_Right || event.text === "l") {
      nextPageRequested()
    } else if (event.key === Qt.Key_Left || event.text === "h") {
      previousPageRequested()
    } else if (event.text === "G") {
      moveCursorTo(count - 1)
    } else if (event.text === "g") {
      if (pendingG) moveCursorTo(0)
      pendingG = !pendingG
      event.accepted = true
      return
    } else if (event.text === "i" || event.text === "/") {
      insertRequested()
    }
    pendingG = false
    event.accepted = true
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
