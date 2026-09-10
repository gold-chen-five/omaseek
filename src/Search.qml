import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "lib/search.mjs" as SearchLib
import "lib/settings.mjs" as SettingsLib
import "lib/keybinds.mjs" as Keybinds

// Web search overlay, through a SearXNG instance the user runs.
//
// The layer-shell recipe and the open/close/dismiss/toggle contract follow the
// first-party overlays (see shell/plugins/emojis/Emojis.qml), so shell IPC
// `toggle omaseek` behaves like every other Omarchy panel.
//
// This file is the wiring. State lives in four stores — ConfigStore (the
// config file), Engine (the SearXNG instance), SearchSession (the query and
// its pages), AiSession (the conversation with an agent) — and each view
// handles its own keys and raises what it wants as a signal. What is left
// here is the part only the panel can decide: which view is showing, whether
// the field searches or asks (`panelMode`, Tab flips it), and which of the
// field and the thing below it has the keyboard. That is a two-state
// machine, "search" and "results", hinged on the field: Enter searches or
// asks and stays put, j or Down steps into what came back, Esc or i steps
// back up.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string view: "search"               // search | settings | setup
  property string panelMode: "search"          // search | ai — what Enter does with the field
  property string focusArea: "search"          // search | results
  property string setupReason: ""              // what the backend said when the instance was down

  readonly property var settingsRows: SettingsLib.settingsRows(config.settings, engine.state, ai.agents)

  // The two rebindable keys, parsed once into the spelling the views match on.
  readonly property string searchChord: Keybinds.parseChord(config.settings.searchKey) || "Return"
  readonly property string newSessionChord: Keybinds.parseChord(config.settings.newSessionKey) || "C-c"

  // Theme tokens: the same [menu] surface the first-party overlays paint with,
  // so a theme switch repaints this panel with no code of our own.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  // ---- shell contract -----------------------------------------------------

  // The panel is keepLoaded, so the last search is still here when it is
  // summoned again — and it comes back rather than being thrown away.
  // Reopening is usually to try the next result, not to start over: the
  // browser took the screen and the panel with it. It reopens where it left
  // off, in normal mode, so j is already the way back into the results.
  // A new search is `cc` — vim's clear-the-line — or i to edit this one.
  function open (payloadJson) {
    config.reload()
    opened = true
    view = "search"                            // never reopen into settings or setup
    if (ai.agents === null) ai.probeAgents()   // once: which agents this machine has
    // Normal when there is still a query in the field to act on, insert when
    // there is nothing to type over — which is the state AI mode leaves the
    // field in, since asking moves the question into the transcript.
    focusSearch(input.text.length === 0)
  }

  function close () {
    opened = false
    session.cancel()
  }

  // Tab: the same field, the other job. The text stays — a query that found
  // nothing is often the question worth asking.
  // Ctrl+N, or the button in the transcript: forget the conversation and
  // start one. Only AI mode has a session to end — a search is replaced by
  // the next search, not started over.
  function newChat () {
    if (panelMode !== "ai") return
    ai.reset()
    input.clear()
    focusSearch(true)
  }

  function toggleMode () {
    panelMode = panelMode === "search" ? "ai" : "search"
    view = "search"
    focusSearch(true)
  }

  function dismiss () {
    close()
    if (shell && typeof shell.hide === "function") {
      shell.hide(manifest?.id ?? "omaseek")
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
    ai.probeAgents()
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
    if (!query) return
    if (panelMode === "ai") {
      ai.ask(query)
      input.clear()                            // the question now lives in the transcript
      return
    }
    session.search(query)
    focusSearch(false)                         // normal: j steps into the results
  }

  // Whether there is anything below the field to step into.
  function hasBody () {
    return panelMode === "ai" ? ai.history.length > 0 : session.results.count > 0
  }

  function focusResults () {
    focusArea = "results"
    const target = panelMode === "ai" ? answerView : resultsList
    Qt.callLater(() => target.forceActiveFocus())
  }

  // Through setMode, not by assigning `mode`: leaving insert steps the cursor
  // left as vim does and drops any half-typed operator, and doing it by hand
  // here skipped both.
  function focusSearch (insertMode) {
    focusArea = "search"
    input.setMode(insertMode ? "insert" : "normal")
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
    onEngineDown: reason => root.askToStartEngine(reason)
    onEngineUp: engine.state = "running"
  }

  AiSession {
    id: ai
    askPath: Qt.resolvedUrl("../bin/ask").toString().replace(/^file:\/\//, "")
    chatAgent: config.settings.chatAgent
    launcher: config.settings.launcher

    onLaunching: root.dismiss()                // the terminal takes the screen
  }

  // ---- window -------------------------------------------------------------

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omaseek"
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

        // The field and the button that runs it. A button because Enter is
        // not discoverable, and because the panel is summoned with a mouse
        // as often as it is typed at.
        Item {
          id: fieldRow

          width: parent.width
          height: input.height

          VimTextField {
            id: input

            width: parent.width - actions.width - Style.spacing.sm
            foreground: root.foreground
            accent: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            placeholderText: root.panelMode === "ai" ? "Ask " + ai.agentName + "…" : "Search the web…"
            escapeSequences: config.keymap.sequences
            escapeTimeout: config.keymap.timeoutMs
            searchChord: root.searchChord
            newSessionChord: root.newSessionChord

            onSubmitted: root.runSearch()
            onCancelled: root.dismiss()
            onSteppedDown: if (root.hasBody()) root.focusResults()
            onRequestedSettings: root.openSettings()
            onTabbed: root.toggleMode()
            onNewSessionRequested: root.newChat()
          }

          // Each half of the panel gets the buttons it has actions for. They
          // match the field's height so the row reads as one control, and
          // they name their key, so the shortcut is learnt from the button.
          Row {
            id: actions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Button {
              visible: root.panelMode === "search"
              height: input.height
              text: "search  " + Keybinds.chordText(root.searchChord)
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall

              onClicked: root.runSearch()
            }

            Button {
              visible: root.panelMode === "ai"
              height: input.height
              text: "chat  " + Keybinds.chordText(root.searchChord)
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall

              onClicked: root.runSearch()
            }

            Button {
              visible: root.panelMode === "ai"
              height: input.height
              text: "new session  " + Keybinds.chordText(root.newSessionChord)
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall

              onClicked: root.newChat()
            }
          }
        }

        StatusLine {
          id: statusLine

          width: parent.width
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          isError: (root.panelMode === "ai" ? ai.status : session.status) === "error"
          mode: SearchLib.modeLabel({
            view: root.view, panelMode: root.panelMode, focusArea: root.focusArea,
            mode: input.mode, selecting: answerView.selecting
          })
          detail: SearchLib.statusText({
            view: root.view,
            panelMode: root.panelMode,
            status: root.panelMode === "ai" ? ai.status : session.status,
            count: session.results.count,
            query: session.lastQuery,
            page: session.pageIndex + 1,
            hasNext: session.hasNext,
            loadingPage: session.loadingPage,
            errorMessage: root.panelMode === "ai" ? ai.errorMessage : session.errorMessage,
            backend: session.backend,
            agent: ai.agentName,
            selecting: answerView.selecting
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

        AnswerView {
          id: answerView

          visible: root.view === "search" && root.panelMode === "ai"
          width: parent.width
          height: parent.height - fieldRow.height - statusLine.height - Style.spacing.md * 2
          turns: ai.history
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onHandedOff: context => ai.launch(context)
          onEscaped: root.focusSearch(false)
          onInsertRequested: root.focusSearch(true)
          onSettingsRequested: root.openSettings()
          onTabbed: root.toggleMode()
          onNewSessionRequested: root.newChat()
          newSessionChord: root.newSessionChord
        }

        ResultList {
          id: resultsList

          visible: root.view === "search" && root.panelMode === "search"
          width: parent.width
          height: parent.height - fieldRow.height - statusLine.height - Style.spacing.md * 2
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
          onTabbed: root.toggleMode()
        }
      }
    }
  }
}
