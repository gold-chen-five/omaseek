import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// DuckDuckGo search overlay.
//
// Layer-shell recipe and the open/close/dismiss/toggle contract follow the
// first-party overlays (see shell/plugins/emojis/Emojis.qml) so shell IPC
// `toggle jonas.search` behaves like every other Omarchy panel.
//
// Focus is a two-state machine: "search" (the vim text field has focus) and
// "results" (j/k moves the cursor). Enter is the hinge — it runs the query and
// hands focus to the results.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string focusArea: "search"        // search | results
  property string status: "idle"             // idle | loading | ok | empty | error
  property string errorMessage: ""
  property string lastQuery: ""
  property bool pendingG: false              // first half of a gg
  property var nextPage: null                // DDG's forward nav form, verbatim
  property bool appending: false             // current fetch appends rather than replaces
  property bool loadingMore: false
  property int pagesLoaded: 0

  // Resolve our own directory so the backend is found through the dev symlink.
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  // Theme tokens: same [menu] surface the first-party overlays paint with, so
  // a theme switch repaints this panel with no code of our own.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  function open(payloadJson) {
    root.opened = true
    root.focusArea = "search"
    root.status = "idle"
    root.errorMessage = ""
    root.pendingG = false
    root.nextPage = null
    root.appending = false
    root.loadingMore = false
    root.pagesLoaded = 0
    resultsModel.clear()
    input.clear()
    input.mode = "insert"
    Qt.callLater(function () { input.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    searchProcess.running = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jonas.search")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function runSearch() {
    var query = input.text.trim()
    if (!query) return
    root.lastQuery = query
    root.status = "loading"
    root.errorMessage = ""
    root.nextPage = null
    root.appending = false
    root.loadingMore = false
    root.pagesLoaded = 0
    resultsModel.clear()
    searchProcess.running = false
    searchProcess.command = [root.pluginDir + "/bin/ddg-search", query]
    searchProcess.running = true
  }

  // Fetches the next page and appends. DuckDuckGo only serves it when the
  // whole nav form is echoed back, so `nextPage` is passed through verbatim.
  function loadMore() {
    if (!root.nextPage || root.loadingMore || root.status === "loading") return
    root.loadingMore = true
    root.appending = true
    searchProcess.running = false
    searchProcess.command = [root.pluginDir + "/bin/ddg-search", "--next", JSON.stringify(root.nextPage)]
    searchProcess.running = true
  }

  function applyResults(payload) {
    var append = root.appending
    root.appending = false
    root.loadingMore = false

    if (!payload.ok) {
      var message = payload.error === "network" ? "No network connection"
        : payload.error === "blocked" ? "DuckDuckGo declined the request — try again shortly"
        : (payload.message || "Search failed")
      if (append) {
        // Keep the results already on screen; just stop offering more.
        root.nextPage = null
        root.errorMessage = message
        return
      }
      resultsModel.clear()
      root.status = "error"
      root.errorMessage = message
      return
    }

    if (!append) resultsModel.clear()

    // DuckDuckGo repeats a few hits across page boundaries.
    var seen = ({})
    for (var s = 0; s < resultsModel.count; s++) seen[resultsModel.get(s).url] = true

    var rows = payload.results || []
    var added = 0
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].url || seen[rows[i].url]) continue
      seen[rows[i].url] = true
      added++
      resultsModel.append({
        title: rows[i].title || "",
        url: rows[i].url || "",
        snippet: rows[i].snippet || "",
        display_url: rows[i].display_url || "",
        icon: rows[i].icon || ""
      })
    }

    root.nextPage = payload.next || null
    if (added > 0) root.pagesLoaded++

    if (resultsModel.count === 0) {
      root.status = "empty"
      return
    }
    root.status = "ok"
    if (!append) {
      resultsList.moveCursorTo(0)
      focusResults()
    } else if (added === 0 && root.nextPage) {
      // A page of pure duplicates: skip ahead rather than appearing stuck.
      root.loadMore()
    }
  }

  // Pull the next page in before the cursor actually lands on the last row,
  // so paging down stays continuous instead of stalling at the boundary.
  function prefetchIfNearEnd() {
    if (resultsList.currentIndex >= resultsModel.count - 3) root.loadMore()
  }

  function focusResults() {
    root.focusArea = "results"
    root.pendingG = false
    Qt.callLater(function () { resultsList.forceActiveFocus() })
  }

  function focusSearch(insertMode) {
    root.focusArea = "search"
    input.mode = insertMode ? "insert" : "normal"
    if (!insertMode) input.clampCursor()
    Qt.callLater(function () { input.forceActiveFocus() })
  }

  function openResult(index) {
    if (index < 0 || index >= resultsModel.count) return
    var url = resultsModel.get(index).url
    if (!url) return
    root.dismiss()
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  ListModel { id: resultsModel }

  Process {
    id: searchProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.status = "error"
          root.errorMessage = "Search returned nothing"
          return
        }
        try {
          root.applyResults(JSON.parse(raw))
        } catch (e) {
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

        // Status strip: mode on the left, what the search is doing on the right.
        Item {
          width: parent.width
          height: modeLabel.implicitHeight

          Text {
            id: modeLabel
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: root.focusArea === "results" ? "RESULTS" : input.mode.toUpperCase()
            color: root.accent
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            color: root.status === "error" ? Color.menu.text : root.foreground
            opacity: root.status === "error" ? 0.95 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width - modeLabel.implicitWidth - Style.spacing.lg)
            text: {
              if (root.status === "loading") return "Searching…"
              if (root.status === "error") return root.errorMessage
              if (root.status === "empty") return "No results for “" + root.lastQuery + "”"
              if (root.status === "ok") {
                if (root.loadingMore) return resultsModel.count + " results · loading more…"
                if (root.errorMessage) return root.errorMessage
                return resultsModel.count + " results" + (root.nextPage ? "" : " · end")
                  + " · j/k move · enter opens"
              }
              return "enter searches · esc for normal mode"
            }
          }
        }

        ResultList {
          id: resultsList

          width: parent.width
          height: parent.height - input.height - modeLabel.height - Style.spacing.md * 2
          model: resultsModel
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onActivated: function (index) { root.openResult(index) }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function (event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            var pageStep = Math.max(1, Math.floor(resultsList.height / Math.max(1, resultsList.contentHeight / Math.max(1, resultsList.count)) / 2))

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
              if (root.pendingG) { resultsList.moveCursorTo(0); root.pendingG = false }
              else root.pendingG = true
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
