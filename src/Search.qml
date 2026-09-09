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

  // Results are paged, not scrolled. `pages` caches every page fetched for this
  // query as { rows, next }, where `next` is DuckDuckGo's forward nav form kept
  // verbatim — it only serves the next page when the whole form is echoed back.
  // Caching means h walks back without refetching.
  property var pages: []
  property int pageIndex: 0
  property bool loadingPage: false
  property string backend: ""               // which engine answered: duckduckgo | exa

  readonly property var currentPage: pages.length > 0 ? pages[pageIndex] : null
  readonly property bool hasNext: currentPage ? (pageIndex + 1 < pages.length || currentPage.next !== null) : false
  readonly property bool hasPrevious: pageIndex > 0

  // Resolved so the backend is found through the dev symlink.
  readonly property string backendPath: Qt.resolvedUrl("../bin/search").toString().replace(/^file:\/\//, "")

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
    pages = []
    pageIndex = 0
    loadingPage = false
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
    fetch([backendPath, query])
  }

  // `l` — forward a page, from cache when we have already been there.
  function nextPageView () {
    if (loadingPage || status === "loading") return
    if (pageIndex + 1 < pages.length) {
      showPage(pageIndex + 1)
      return
    }
    if (!currentPage || !currentPage.next) return
    loadingPage = true
    fetch([backendPath, "--next", JSON.stringify(currentPage.next)])
  }

  // `h` — back a page. Always cached, so this never hits the network.
  function previousPageView () {
    if (hasPrevious) showPage(pageIndex - 1)
  }

  function showPage (index) {
    if (index < 0 || index >= pages.length) return
    pageIndex = index
    resultsModel.clear()
    for (const row of pages[index].rows) resultsModel.append(row)
    resultsList.moveCursorTo(0)
  }

  function fetch (command) {
    searchProcess.running = false
    searchProcess.command = command
    searchProcess.running = true
  }

  function applyResults (payload) {
    const wasPaging = loadingPage
    loadingPage = false

    if (!payload.ok) {
      const message = SearchLib.describeError(payload)
      if (wasPaging) {
        // Keep the page on screen and stop offering a next one.
        pages = pages.map((page, i) => i === pageIndex ? { rows: page.rows, next: null } : page)
        errorMessage = message
        return
      }
      resultsModel.clear()
      status = "error"
      errorMessage = message
      return
    }

    const rows = SearchLib.mergeResults([], payload.results)
    const page = { rows: rows, next: payload.next ?? null }

    if (rows.length === 0) {
      if (wasPaging) {
        // An empty page past the end: stay put and stop offering more.
        pages = pages.map((existing, i) => i === pageIndex ? { rows: existing.rows, next: null } : existing)
        return
      }
      resultsModel.clear()
      status = "empty"
      return
    }

    status = "ok"
    errorMessage = ""
    backend = payload.backend ?? ""
    pages = wasPaging ? [...pages, page] : [page]
    showPage(pages.length - 1)
    if (!wasPaging) focusResults()
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
          onSteppedDown: if (resultsModel.count > 0) root.focusResults()
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
            page: root.pageIndex + 1,
            hasNext: root.hasNext,
            loadingPage: root.loadingPage,
            errorMessage: root.errorMessage,
            backend: root.backend
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
            } else if (ctrl && event.key === Qt.Key_U) {
              resultsList.moveCursor(-pageStep)
            } else if (event.key === Qt.Key_Down || event.text === "j") {
              resultsList.moveCursor(1)
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              resultsList.moveCursor(-1)
            } else if (event.key === Qt.Key_Right || event.text === "l") {
              root.nextPageView()
            } else if (event.key === Qt.Key_Left || event.text === "h") {
              root.previousPageView()
            } else if (event.text === "G") {
              resultsList.moveCursorTo(resultsList.count - 1)
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
