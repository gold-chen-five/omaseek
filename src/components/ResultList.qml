import QtQuick
import qs.Commons
import qs.Ui

// Result rows plus the vim cursor that walks them. Key handling stays in
// Search.qml so the panel owns the whole focus state machine.
ListView {
  id: list

  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal activated(int index)

  clip: true
  keyNavigationEnabled: false            // Search.qml drives j/k and the arrows
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

  function moveCursor (delta) {
    moveCursorTo(currentIndex + delta)
  }

  function moveCursorTo (index) {
    if (count === 0) return
    pointerGate.reset()
    currentIndex = Math.max(0, Math.min(count - 1, index))
    positionViewAtIndex(currentIndex, ListView.Contain)
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
