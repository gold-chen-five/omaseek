import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "lib/search.mjs" as SearchLib

// DuckDuckGo search overlay.
//
// The layer-shell recipe and the open/close/dismiss/toggle contract follow the
// first-party overlays (see shell/plugins/emojis/Emojis.qml), so shell IPC
// `toggle jonas.search` behaves like every other Omarchy panel.
//
// Focus is a two-state machine: "search" (the vim field has focus) and
// "results" (j/k walks the list). Enter is the hinge — it runs the query and
// hands focus to the results.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string focusArea: "search"       // search | results
  property string status: "idle"            // idle | loading | ok | empty | error
  property string errorMessage: ""
  property string lastQuery: ""
  property bool pendingG: false             // first half of a gg

  // Paging. `nextPage` is DuckDuckGo's forward nav form, kept verbatim because
  // it only serves the next page when the whole form is echoed back.
  property var nextPage: null
  property bool appending: false
  property bool loadingMore: false

  readonly property bool hasMore: nextPage !== null

  // Resolved so the backend is found through the dev symlink.
  readonly property string backend: Qt.resolvedUrl("../bin/ddg-search").toString().replace(/^file:\/\//, "")

  // Theme tokens: the same [menu] surface the first-party overlays paint with,
  // so a theme switch repaints this panel with no code of our own.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  function open (payloadJson) {
    opened = true
    focusArea = "search"
    status = "idle"
    errorMessage = ""
    lastQuery = ""
    resetPaging()
    resultsModel.clear()
    input.clear()
    input.mode = "insert"
    Qt.callLater(() => input.forceActiveFocus())
  }

  function close () {
    opened = false
    searchProcess.running = false
  }

  function dismiss () {
    close()
    if (shell && typeof shell.hide === "function") {
      shell.hide(manifest?.id ?? "jonas.search")
    }
  }

  function toggle () {
    if (opened) dismiss()
    else open("{}")
  }

  function resetPaging () {
    nextPage = null
    appending = false
    loadingMore = false
    pendingG = false
  }

  function runSearch () {
    const query = input.text.trim()
    if (!query) return

    lastQuery = query
    status = "loading"
    errorMessage = ""
    resetPaging()
    resultsModel.clear()
    fetch([backend, query])
  }

  function loadMore () {
    if (!hasMore || loadingMore || status === "loading") return
    loadingMore = true
    appending = true
    fetch([backend, "--next", JSON.stringify(nextPage)])
  }

  function fetch (command) {
    searchProcess.running = false
    searchProcess.command = command
    searchProcess.running = true
  }

  // Pull the next page in before the cursor actually lands on the last row, so
  // paging down stays continuous instead of stalling at the boundary.
  function prefetchIfNearEnd () {
    if (resultsList.currentIndex >= resultsModel.count - 3) loadMore()
  }

  function currentUrls () {
    const urls = []
    for (let i = 0; i < resultsModel.count; i++) urls.push(resultsModel.get(i).url)
    return urls
  }

  function applyResults (payload) {
    const append = appending
    appending = false
    loadingMore = false

    if (!payload.ok) {
      const message = SearchLib.describeError(payload)
      if (append) {
        nextPage = null                     // keep what is on screen, stop offering more
        errorMessage = message
        return
      }
      resultsModel.clear()
      status = "error"
      errorMessage = message
      return
    }

    if (!append) resultsModel.clear()

    const added = SearchLib.mergeResults(currentUrls(), payload.results)
    for (const row of added) resultsModel.append(row)
    nextPage = payload.next ?? null

    if (resultsModel.count === 0) {
      status = "empty"
      return
    }

    status = "ok"
    if (!append) {
      resultsList.moveCursorTo(0)
      focusResults()
    } else if (added.length === 0 && hasMore) {
      loadMore()                            // a page of pure duplicates: skip ahead
    }
  }

  function focusResults () {
    focusArea = "results"
    pendingG = false
    Qt.callLater(() => resultsList.forceActiveFocus())
  }

  function focusSearch (insertMode) {
    focusArea = "search"
    input.mode = insertMode ? "insert" : "normal"
    if (!insertMode) input.clampCursor()
    Qt.callLater(() => input.forceActiveFocus())
  }

  function openResult (index) {
    if (index < 0 || index >= resultsModel.count) return
    const url = resultsModel.get(index).url
    if (!url) return
    dismiss()
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  ListModel { id: resultsModel }

  Process {
    id: searchProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const raw = String(text ?? "").trim()
        if (!raw) {
          root.status = "error"
          root.errorMessage = "Search returned nothing"
          return
        }
        try {
          root.applyResults(JSON.parse(raw))
        } catch (error) {
          root.status = "error"
          root.errorMessage = "Could not read search output"
        }
      }
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jonas-search"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card

      width: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        VimTextField {
          id: input

          width: parent.width
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          placeholderText: "Search the web…"

          onSubmitted: root.runSearch()
          onCancelled: root.dismiss()
        }

        StatusLine {
          id: statusLine

          width: parent.width
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          isError: root.status === "error"
          mode: SearchLib.modeLabel({ focusArea: root.focusArea, mode: input.mode })
          detail: SearchLib.statusText({
            status: root.status,
            count: resultsModel.count,
            query: root.lastQuery,
            hasMore: root.hasMore,
            loadingMore: root.loadingMore,
            errorMessage: root.errorMessage
          })
        }

        ResultList {
          id: resultsList

          width: parent.width
          height: parent.height - input.height - statusLine.height - Style.spacing.md * 2
          model: resultsModel
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onActivated: index => root.openResult(index)

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            const rowHeight = Math.max(1, resultsList.contentHeight / Math.max(1, resultsList.count))
            const pageStep = Math.max(1, Math.floor(resultsList.height / rowHeight / 2))

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.openResult(resultsList.currentIndex)
            } else if (event.key === Qt.Key_Escape) {
              root.focusSearch(false)
            } else if (ctrl && event.key === Qt.Key_D) {
              resultsList.moveCursor(pageStep)
              root.prefetchIfNearEnd()
            } else if (ctrl && event.key === Qt.Key_U) {
              resultsList.moveCursor(-pageStep)
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              resultsList.moveCursor(1)
              root.prefetchIfNearEnd()
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              resultsList.moveCursor(-1)
            } else if (event.text === "G") {
              resultsList.moveCursorTo(resultsList.count - 1)
              root.prefetchIfNearEnd()
            } else if (event.text === "L") {
              root.loadMore()
            } else if (event.text === "g") {
              if (root.pendingG) resultsList.moveCursorTo(0)
              root.pendingG = !root.pendingG
              event.accepted = true
              return
            } else if (event.text === "i" || event.text === "/") {
              root.focusSearch(true)
            }
            root.pendingG = false
            event.accepted = true
          }
        }
      }
    }
  }
}
