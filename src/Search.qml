import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "lib/search.mjs" as SearchLib
import "lib/settings.mjs" as SettingsLib

// Web search overlay, through a SearXNG instance the user runs.
//
// The layer-shell recipe and the open/close/dismiss/toggle contract follow the
// first-party overlays (see shell/plugins/emojis/Emojis.qml), so shell IPC
// `toggle jonas.search` behaves like every other Omarchy panel.
//
// This file is the wiring. State lives in three stores — ConfigStore (the
// config file), Engine (the SearXNG instance), SearchSession (the query and
// its pages) — and each view handles its own keys and raises what it wants
// as a signal. What is left here is the part only the panel can decide:
// which view is showing, and which of the search field and the result list
// has the keyboard. That is a two-state machine, "search" and "results",
// with Enter as the hinge: it runs the query and hands focus to the results.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string view: "search"               // search | settings | setup
  property string focusArea: "search"          // search | results
  property string setupReason: ""              // what the backend said when the instance was down

  readonly property var settingsRows: SettingsLib.settingsRows(config.settings, engine.state)

  // Theme tokens: the same [menu] surface the first-party overlays paint with,
  // so a theme switch repaints this panel with no code of our own.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  // ---- shell contract -----------------------------------------------------

  function open (payloadJson) {
    config.reload()
    opened = true
    view = "search"
    focusArea = "search"
    session.reset()
    input.clear()
    input.mode = "insert"
    Qt.callLater(() => input.forceActiveFocus())
  }

  function close () {
    opened = false
    session.cancel()
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

  // ---- views --------------------------------------------------------------

  function openSettings () {
    view = "settings"
    engine.probe()
    settingsPage.open()
  }

  function closeSettings () {
    view = "search"
    focusSearch(false)
  }

  // The instance is down. Rather than leaving an error on screen the panel
  // cannot act on, ask — the answer is always the same one command, and the
  // user should hear what it does before agreeing to it.
  function askToStartEngine (reason) {
    engine.state = "stopped"
    setupReason = reason
    view = "setup"
    setupPrompt.open()
  }

  function closeSetup () {
    view = "search"
    setupReason = ""
    focusSearch(true)                          // back to the query, still typed
  }

  function runSettingAction (key, action) {
    if (key !== "engine") return
    if (action === "stop") engine.stop()
    else engine.start()
  }

  // ---- focus --------------------------------------------------------------

  function runSearch () {
    const query = input.text.trim()
    if (query) session.search(query)
  }

  function focusResults () {
    focusArea = "results"
    Qt.callLater(() => resultsList.forceActiveFocus())
  }

  function focusSearch (insertMode) {
    focusArea = "search"
    input.mode = insertMode ? "insert" : "normal"
    if (!insertMode) input.clampCursor()
    Qt.callLater(() => input.forceActiveFocus())
  }

  function openResult (index) {
    if (index < 0 || index >= session.results.count) return
    const url = session.results.get(index).url
    if (!url) return
    dismiss()
    Quickshell.execDetached(["omarchy-launch-browser", url])
  }

  // ---- stores -------------------------------------------------------------

  ConfigStore { id: config }

  Engine {
    id: engine
    onLaunching: root.dismiss()                // the terminal takes the screen
  }

  SearchSession {
    id: session
    backendPath: engine.backendPath

    onPageShown: resultsList.moveCursorTo(0)
    onLanded: root.focusResults()
    onEngineDown: reason => root.askToStartEngine(reason)
    onEngineUp: engine.state = "running"
  }

  // ---- window -------------------------------------------------------------

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
          escapeSequences: config.keymap.sequences
          escapeTimeout: config.keymap.timeoutMs

          onSubmitted: root.runSearch()
          onCancelled: root.dismiss()
          onSteppedDown: if (session.results.count > 0) root.focusResults()
          onRequestedSettings: root.openSettings()
        }

        StatusLine {
          id: statusLine

          width: parent.width
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          isError: session.status === "error"
          mode: SearchLib.modeLabel({ view: root.view, focusArea: root.focusArea, mode: input.mode })
          detail: SearchLib.statusText({
            view: root.view,
            status: session.status,
            count: session.results.count,
            query: session.lastQuery,
            page: session.pageIndex + 1,
            hasNext: session.hasNext,
            loadingPage: session.loadingPage,
            errorMessage: session.errorMessage,
            backend: session.backend
          })
        }

        SetupPrompt {
          id: setupPrompt

          visible: root.view === "setup"
          width: parent.width
          reason: root.setupReason
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onConfirmed: engine.start()
          onCancelled: root.closeSetup()
        }

        SettingsPage {
          id: settingsPage

          visible: root.view === "settings"
          width: parent.width
          rows: root.settingsRows
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onChanged: (key, value) => config.change(key, value)
          onActivated: (key, action) => root.runSettingAction(key, action)
          onClosed: root.closeSettings()
          onEditingFinished: Qt.callLater(() => settingsPage.forceActiveFocus())
        }

        ResultList {
          id: resultsList

          visible: root.view === "search"
          width: parent.width
          height: parent.height - input.height - statusLine.height - Style.spacing.md * 2
          model: session.results
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onActivated: index => root.openResult(index)
          onEscaped: root.focusSearch(false)
          onInsertRequested: root.focusSearch(true)
          onSettingsRequested: root.openSettings()
          onNextPageRequested: session.nextPage()
          onPreviousPageRequested: session.previousPage()
        }
      }
    }
  }
}
