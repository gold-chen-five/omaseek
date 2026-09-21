import QtQuick
import qs.Commons
import qs.Ui
import "keylist.mjs" as KeyList
import "../shared/vim/keys.mjs" as KeysLib
import "../shared/vim/chord.js" as Chord
import "../field"

// ctrl+k: every key in the panel, to look one up without leaving for Settings.
// The page is the search page in miniature — the same field over a list read
// with the same keys — so nothing has to be learned to use it:
//
//   · the filter is a VimTextField like the bar's, with every vim key in it
//   · Enter, j or Down step into the list, as they step into the results
//   · the list runs the reading keys (j k, gg G, ctrl+d ctrl+u, counts), and
//     gn, gi, i, a, / and esc go back to the filter, as they go back to the bar
//   · a panel key means here what it means anywhere: it closes the lookup and
//     acts, which is what these signals are for
//
// The rows are the Settings → Keys rows — what it does, the key beside it, the
// hint under it — and the fixed keys close the page as they close that one.
// The entries are keylist.mjs's.
FocusScope {
  id: lookup

  property var settings: null
  property var keymap: ({ sequences: [], timeoutMs: 0 })
  property var chords: ({})
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var entries: KeyList.filterEntries(KeyList.keyEntries(settings), filter.text)
  readonly property var readerKeys: KeysLib.readerKeys("results", settings)
  // Numbered as the results are, so a count (5j) can be read off the rows.
  readonly property string lineNumbers: settings && settings.lineNumbers ? settings.lineNumbers : "relative"
  property var navigation: ({ pending: "", count: 0 })

  signal closed()
  signal settingsRequested()
  signal tabbed()
  signal agentSwitchRequested()
  signal newSessionRequested()
  signal nextSessionRequested()
  signal closeSessionRequested()
  signal clearSessionsRequested()
  signal retryRequested()

  // Opened afresh each time: the last search is not what the next one is after.
  function open () {
    filter.text = ""
    list.currentIndex = 0
    list.positionViewAtBeginning()
    focusFilter("i")
  }

  function focusFilter (mode) {
    if (mode === "i" || mode === "a") filter.enterInsert(mode)
    else filter.setMode(mode)
    filter.forceActiveFocus()
  }

  // Nothing to read means nothing to step into, as an empty result list does.
  function focusList () {
    if (list.count === 0) return
    navigation = { pending: "", count: 0 }
    list.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: Color.menu.background
  }

  // The card under it would take clicks otherwise.
  MouseArea { anchors.fill: parent; onClicked: lookup.focusFilter(filter.mode) }

  Text {
    id: title

    anchors.left: parent.left
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: "KEYS · type to filter · esc closes"
    color: lookup.foreground
    opacity: 0.5
    font.family: lookup.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  // The field's frame, drawn as the bar draws its own: the field scrolls inside
  // it, so a frame the field drew would scroll with it.
  BorderSurface {
    id: filterFrame

    readonly property real insetTop: Border.top(filter.borderSpec) + filter.verticalPadding
    readonly property real insetBottom: Border.bottom(filter.borderSpec) + filter.verticalPadding

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: title.bottom
    anchors.topMargin: Style.spacing.sm
    height: Math.round(filter.lineHeight + insetTop + insetBottom)
    radius: Style.cornerRadius
    color: Style.controlFill(filter.activeFocus, filter.hovered, lookup.foreground, lookup.accent)
    borderSpec: filter.borderSpec

    Flickable {
      id: filterScroll

      anchors.fill: parent
      anchors.leftMargin: Border.left(filter.borderSpec) + filter.horizontalPadding
      anchors.rightMargin: Border.right(filter.borderSpec) + filter.horizontalPadding
      anchors.topMargin: filterFrame.insetTop
      anchors.bottomMargin: filterFrame.insetBottom
      clip: true
      interactive: false
      contentWidth: filter.width
      contentHeight: filter.height

      VimTextField {
        id: filter

        width: Math.max(filterScroll.width, implicitWidth)
        height: Math.max(filterScroll.height, implicitHeight)
        focus: true
        placeholderText: "translate, ctrl+x, undo, gd …"
        foreground: lookup.foreground
        accent: lookup.accent
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.body
        verticalPadding: Style.spacing.md
        escapeSequences: lookup.keymap.sequences
        escapeTimeout: lookup.keymap.timeoutMs
        // The panel's keys are the field's here too, so each one closes the
        // lookup and does what it does anywhere else.
        chords: lookup.chords

        onSubmitted: lookup.focusList()          // Enter: into the list, as it goes to the results
        onSteppedDown: lookup.focusList()
        onHistoryNextRequested: lookup.focusList()   // Down; there is no history to walk here
        onCancelled: lookup.closed()             // esc from normal mode
        onKeysRequested: lookup.closed()
        onRequestedSettings: lookup.settingsRequested()
        onTabbed: lookup.tabbed()
        onAgentSwitchRequested: lookup.agentSwitchRequested()
        onNewSessionRequested: lookup.newSessionRequested()
        onNextSessionRequested: lookup.nextSessionRequested()
        onCloseSessionRequested: lookup.closeSessionRequested()
        onClearSessionsRequested: lookup.clearSessionsRequested()
        onRetryRequested: lookup.retryRequested()

        onCursorRectangleChanged: {
          const r = cursorRectangle
          if (r.x < filterScroll.contentX) filterScroll.contentX = r.x
          else if (r.x + r.width > filterScroll.contentX + filterScroll.width) filterScroll.contentX = r.x + r.width - filterScroll.width
        }
      }
    }
  }

  ListView {
    id: list

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filterFrame.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.spacing.md
    clip: true
    keyNavigationEnabled: false                // the table below drives j/k and the arrows
    boundsBehavior: Flickable.StopAtBounds
    model: lookup.entries
    currentIndex: 0

    function moveCursor (delta) { moveCursorTo(currentIndex + delta) }

    function moveCursorTo (index) {
      if (count === 0) return
      currentIndex = Math.max(0, Math.min(count - 1, index))
      positionViewAtIndex(currentIndex, ListView.Contain)
    }

    onModelChanged: currentIndex = 0

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
      const step = KeysLib.resolveCounted(lookup.readerKeys, lookup.navigation, Chord.of(event))
      lookup.navigation = step.state
      run(step.command, step.count)
      event.accepted = true
    }

    // The reading keys, as the results read them; the commands this page has
    // nothing to do (a page, a yank, a hand-off) simply do nothing.
    function run (command, times) {
      const rowHeight = Math.max(1, contentHeight / Math.max(1, count))
      const pageStep = Math.max(1, Math.floor(height / rowHeight / 2))

      switch (command) {
      case "down":         moveCursor(times); break
      case "up":           moveCursor(-times); break
      case "halfPageDown": moveCursor(pageStep * times); break
      case "halfPageUp":   moveCursor(-pageStep * times); break
      case "top":          moveCursorTo(0); break
      case "bottom":       moveCursorTo(count - 1); break
      // Back to the filter, the five ways the panes go back to the field —
      // and `/`, which here is that same filter rather than a second search.
      case "cancel":
      case "fieldNormal":  lookup.focusFilter("normal"); break
      case "insert":
      case "findForward":
      case "findBackward": lookup.focusFilter("i"); break
      case "append":       lookup.focusFilter("a"); break
      case "keysHelp":     lookup.closed(); break
      case "settings":     lookup.settingsRequested(); break
      case "toggleMode":   lookup.tabbed(); break
      case "switchAgent":  lookup.agentSwitchRequested(); break
      case "newSession":   lookup.newSessionRequested(); break
      case "nextSession":  lookup.nextSessionRequested(); break
      case "closeSession": lookup.closeSessionRequested(); break
      case "clearSessions": lookup.clearSessionsRequested(); break
      case "retryAnswer":  lookup.retryRequested(); break
      }
    }

    // The section heading and its rule, as the settings page draws a section.
    section.property: "group"
    section.delegate: Item {
      required property string section

      width: ListView.view.width
      height: heading.implicitHeight + Style.spacing.lg + Style.spacing.xs

      // No rule above the first group, as the page draws none above its first
      // section.
      Rectangle {
        visible: lookup.entries.length > 0 && lookup.entries[0].group !== parent.section
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.md
        height: Math.max(1, Style.normalBorderWidth)
        color: Util.alpha(lookup.foreground, 0.18)
      }

      Text {
        id: heading

        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: parent.section.toUpperCase()
        color: lookup.foreground
        opacity: 0.5
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }
    }

    delegate: Rectangle {
      id: row

      required property var modelData
      required property int index
      // A group of vim's own keys: no binding to show, and read as the page
      // reads its fixed rows.
      readonly property bool fixed: modelData.fixed === true
      // Lit only while the list has the keyboard, so typing in the filter does
      // not look like it would act on a row.
      readonly property bool hasCursor: index === list.currentIndex && list.activeFocus

      width: ListView.view.width
      height: labels.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: hasCursor ? Color.menu.selectedBackground : "transparent"

      // The results' number column: relative to the cursor, absolute, or hidden.
      Text {
        id: rowNumber

        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.top: labels.top
        visible: lookup.lineNumbers !== "hide"
        width: visible ? numberMetrics.advanceWidth : 0
        text: lookup.lineNumbers === "relative" ? Math.abs(row.index - list.currentIndex) : row.index + 1
        horizontalAlignment: Text.AlignRight
        color: row.hasCursor ? lookup.accent : Util.alpha(lookup.foreground, 0.45)
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.caption
      }

      TextMetrics {
        id: numberMetrics
        font: rowNumber.font
        text: "8".repeat(String(Math.max(1, list.count)).length)
      }

      Column {
        id: labels

        anchors.left: rowNumber.right
        anchors.right: keyText.left
        anchors.leftMargin: rowNumber.visible ? Style.spacing.md : 0
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.modelData.label
          color: lookup.foreground
          opacity: row.fixed ? 0.8 : 1
          font.family: lookup.fontFamily
          font.pixelSize: row.fixed ? Style.font.body : Style.font.subtitle
          elide: Text.ElideRight
        }

        // Wrapped, never elided: a hint cut short hides exactly what it is
        // there to say — and a fixed row is all hint.
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: row.modelData.hint || ""
          color: lookup.foreground
          opacity: 0.55
          font.family: lookup.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Text {
        id: keyText

        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: row.fixed ? 0 : Math.round(list.width * 0.2)
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.modelData.keys
        color: row.hasCursor ? lookup.accent : lookup.foreground
        font.family: lookup.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          list.currentIndex = row.index
          lookup.focusList()
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: list.count === 0
      textFormat: Text.PlainText
      text: "no key matches “" + filter.text + "”"
      color: lookup.foreground
      opacity: 0.5
      font.family: lookup.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
