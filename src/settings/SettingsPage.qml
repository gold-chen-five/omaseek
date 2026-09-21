import QtQuick
import qs.Commons
import "settings.mjs" as SettingsLib
import "../shared/vim/chord.js" as Chord

// One row per setting; the rows come from settings/rows.mjs. A FocusScope because
// a typed row lends the keyboard to a text field and has to take it back.
FocusScope {
  id: page

  property alias incomingRows: rowState.source
  readonly property var rows: rowState.rows
  property int cursor: 0
  property int editingIndex: -1              // which text row is being typed into
  property int dropdownIndex: -1             // which choice row has its list open
  property int refusedIndex: -1              // a key just refused, and why, until the cursor moves
  property string refusal: ""
  property string settingsChord: "C-s"       // the key that opened the page closes it
  property string keysChord: "C-k"           // the key lookup, which opens over the page

  // The widest row of chips on the page, measured as laid out. A dropdown takes
  // this width, so it lines up with the chips under it edge for edge.
  property var chipWidths: ({})
  readonly property real chipColumn: {
    let widest = 0
    for (const key in chipWidths) widest = Math.max(widest, chipWidths[key])
    return widest
  }
  // The widest action button (Update, Test), measured as laid out; every one
  // takes it, so the buttons stack as one column rather than ragged widths.
  property var buttonWidths: ({})
  readonly property real buttonColumn: {
    let widest = 0
    for (const key in buttonWidths) widest = Math.max(widest, buttonWidths[key])
    return widest
  }
  // Where the page is scrolled, and how far it can scroll: read by the tests
  // that cover keeping the position across a rebuild.
  readonly property alias scrollY: scroll.contentY
  readonly property alias scrollHeight: scroll.contentHeight

  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)
  signal activated(string key, string action) // a toggle was flipped or an action pressed
  signal closed()                            // /, esc, or the chord that opened the page
  signal keysRequested()                     // ctrl+k: the key lookup, as from anywhere else
  signal editingFinished()                   // hand the keyboard back to Search.qml

  implicitHeight: layout.implicitHeight

  onCursorChanged: {
    refusedIndex = -1
    keptContentY = -1                        // the reader moved; nothing to put back
    Qt.callLater(ensureCursorVisible)
  }
  // Flipping a switch rewrites the config, which rebuilds every row. The
  // Repeater destroys its delegates first, so the column is briefly empty and
  // the Flickable clamps the scroll to the top — which threw the page back to
  // the first row whenever an engine near the bottom was toggled. Remember
  // where it was and put it back once the rebuilt rows are as tall again.
  property real keptContentY: -1
  onRowsChanged: {
    if (keptContentY < 0) keptContentY = scroll.contentY
    Qt.callLater(restoreScroll)
  }

  function restoreScroll () {
    if (keptContentY < 0 || scroll.contentHeight <= 0) return
    const bottom = Math.max(0, scroll.contentHeight - scroll.height)
    scroll.contentY = Math.max(0, Math.min(keptContentY, bottom))
    if (keptContentY <= bottom) keptContentY = -1   // the page is tall enough again
  }
  SettingsRows {
    id: rowState
    held: page.dropdownIndex !== -1 || page.editingIndex !== -1
  }

  function ensureCursorVisible () {
    // Rebuilt rows sit at y 0 until they are laid out, and scrolling to one
    // then means scrolling to the top. The restore knows where the page was.
    if (keptContentY >= 0) return
    const row = rowRepeater.itemAt(cursor)
    if (!row) return
    const top = row.y
    const bottom = top + row.height
    if (top < scroll.contentY) scroll.contentY = top
    else if (bottom > scroll.contentY + scroll.height) scroll.contentY = bottom - scroll.height
    scroll.contentY = Math.max(0, Math.min(scroll.contentY, Math.max(0, scroll.contentHeight - scroll.height)))
  }

  function open () {
    cursor = firstSetting()
    refusedIndex = -1
    keptContentY = -1
    scroll.contentY = 0
    Qt.callLater(() => page.forceActiveFocus())
  }

  function beginEdit (index) {
    if (rows[index] && rows[index].type === "text") {
      refusedIndex = -1
      editingIndex = index
    }
  }

  function endEdit () {
    if (editingIndex === -1) return          // idempotent: nothing to hand back
    editingIndex = -1
    editingFinished()
  }

  function refuse (index, reason) {
    refusal = reason
    refusedIndex = index
  }

  function noteButton (index, width) {
    if (buttonWidths[index] === width) return
    const next = {}
    for (const key in buttonWidths) next[key] = buttonWidths[key]
    next[index] = width
    buttonWidths = next
  }

  function noteChips (index, width) {
    const next = {}
    for (const key in chipWidths) next[key] = chipWidths[key]
    next[index] = width
    chipWidths = next
  }

  // Section headings and the fixed-key reference are read, not changed.
  function selectable (row) {
    return !!row && row.type !== "section" && row.type !== "info"
  }

  function moveCursor (delta) {
    const step = delta < 0 ? -1 : 1
    let next = cursor
    for (let i = 0; i < rows.length; i++) {
      next += step
      if (next < 0 || next >= rows.length) return
      if (selectable(rows[next])) { cursor = next; return }
    }
  }

  function firstSetting () {
    for (let i = 0; i < rows.length; i++) if (selectable(rows[i])) return i
    return 0
  }

  function lastSetting () {
    for (let i = rows.length - 1; i >= 0; i--) if (selectable(rows[i])) return i
    return 0
  }

  // On a toggle, l is on and h is off; only a flip that changes the state fires.
  function cycle (delta) {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "choice") changed(row.key, SettingsLib.cycle(row, delta))
    else if (row.type === "toggle" && !row.busy && (delta > 0) !== (row.value === true)) activated(row.key, row.action)
  }

  // A choice row has nothing to open: h and l change it.
  function press () {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "text") beginEdit(cursor)
    else if (row.type === "toggle") { if (!row.busy) activated(row.key, row.action) }
    else if (row.type === "action") { if (!row.busy) activated(row.key, row.action) }
    else if (row.control === "dropdown") dropdownIndex = cursor
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    // A row being edited owns the keyboard; its Enter reaches here too and would
    // reopen the editor.
    if (editingIndex !== -1 || dropdownIndex !== -1) return

    const chord = Chord.of(event)
    if (event.key === Qt.Key_Escape || event.text === "/" || (chord !== "" && (chord === page.settingsChord || chord === "C-,"))) {
      closed()
    } else if (chord !== "" && chord === page.keysChord) {
      keysRequested()
    } else if (event.key === Qt.Key_Down || event.text === "j") {
      moveCursor(1)
    } else if (event.key === Qt.Key_Up || event.text === "k") {
      moveCursor(-1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "i") {
      press()
    } else if (event.key === Qt.Key_Right || event.text === "l") {
      cycle(1)
    } else if (event.key === Qt.Key_Left || event.text === "h") {
      cycle(-1)
    } else if (event.text === "g") {
      cursor = firstSetting()
    } else if (event.text === "G") {
      cursor = lastSetting()
    }
    event.accepted = true
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: layout.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    onHeightChanged: Qt.callLater(page.ensureCursorVisible)
    onContentHeightChanged: page.restoreScroll()   // the rebuilt rows have their height back

    Column {
      id: layout

      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.spacing.xs

      Repeater {
        id: rowRepeater
        model: page.rows

        delegate: SettingRow {
          owner: page
          width: layout.width
        }
      }
    }
  }
}
