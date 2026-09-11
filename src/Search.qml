import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "lib/search.mjs" as SearchLib
import "lib/settings.mjs" as SettingsLib
import "lib/keybinds.mjs" as Keybinds
import "lib/states.mjs" as States

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
// machine, field and results, hinged on the field: Enter searches or
// asks and stays put, j or Down steps into what came back, Esc or i steps
// back up.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string view: States.VIEW.SEARCH           // States.VIEW
  property string panelMode: States.PANEL.SEARCH     // States.PANEL — what Enter does with the field
  property string focusArea: States.FOCUS.FIELD      // States.FOCUS — who has the keyboard
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
    view = States.VIEW.SEARCH                  // never reopen into settings or setup
    if (ai.agents === null) ai.probeAgents()   // once: which agents this machine has
    // Normal when there is something below the field to step into — results,
    // or a conversation — so j goes there; insert only when there is nothing
    // to navigate and typing is the only thing left to do.
    focusSearch(!hasBody())
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
    if (panelMode !== States.PANEL.AI) return
    ai.reset()
    input.clear()
    focusSearch(true)
  }

  function toggleMode () {
    panelMode = panelMode === States.PANEL.SEARCH ? States.PANEL.AI : States.PANEL.SEARCH
    view = States.VIEW.SEARCH
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
    view = States.VIEW.SETTINGS
    engine.probe()
    ai.probeAgents()
    settingsPage.open()
  }

  function closeSettings () {
    view = States.VIEW.SEARCH
    focusSearch(false)
  }

  // The instance is down. Rather than leaving an error on screen the panel
  // cannot act on, ask — the answer is always the same one command, and the
  // user should hear what it does before agreeing to it.
  function askToStartEngine (reason) {
    engine.state = "stopped"
    setupReason = reason
    view = States.VIEW.SETUP
    setupPrompt.open()
  }

  function closeSetup () {
    view = States.VIEW.SEARCH
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
    if (panelMode === States.PANEL.AI) {
      ai.ask(query)
      input.clear()                            // the question now lives in the transcript
      focusSearch(false)                       // normal: j steps into the transcript, i asks more
      return
    }
    session.search(query)
    focusSearch(false)                         // normal: j steps into the results
  }

  // Whether there is anything below the field to step into.
  function hasBody () {
    return panelMode === States.PANEL.AI ? ai.history.length > 0 : session.results.count > 0
  }

  function focusResults () {
    focusArea = States.FOCUS.RESULTS
    const target = panelMode === States.PANEL.AI ? answerView : resultsList
    Qt.callLater(() => target.forceActiveFocus())
  }

  // Through setMode, not by assigning `mode`: leaving insert steps the cursor
  // left as vim does and drops any half-typed operator, and doing it by hand
  // here skipped both.
  function focusSearch (insertMode) {
    focusArea = States.FOCUS.FIELD
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

      width: Math.min(Style.space(820), panel.width - Style.gapsOut * 2)
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
            font.pixelSize: Style.font.body    // the same size as the button beside it
            // Ui.TextField sizes itself from the font plus this padding. The
            // kit's default is sized for a dialog form, and the query text is
            // a size smaller than that assumes — this sits one step under it:
            // room around the text without turning the bar into a box.
            verticalPadding: Style.spacing.md
            placeholderText: root.panelMode === States.PANEL.AI ? "Ask " + ai.agentName + "…" : "Search the web…"
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

          // Each half of the panel gets the buttons it has actions for. The
          // block reserves the wider of the two arrangements and keeps it,
          // so the field does not change width when Tab flips the mode —
          // a search bar that resizes under you reads as a different bar.
          Item {
            id: actions

            anchors.right: parent.right
            anchors.top: parent.top                // the field grows down; the buttons stay a line
            height: input.oneLineHeight
            width: Math.max(searchButton.implicitWidth, askActions.implicitWidth)

            Button {
              id: searchButton

              visible: root.panelMode === States.PANEL.SEARCH
              anchors.fill: parent               // the whole reserved block, so
              text: "search"                     // the row has no gap in it
              active: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body

              onClicked: root.runSearch()
            }

            Row {
              id: askActions

              visible: root.panelMode === States.PANEL.AI
              anchors.right: parent.right
              height: parent.height
              spacing: Style.spacing.sm

              Button {
                height: askActions.height
                text: "chat"
                active: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.body

                onClicked: root.runSearch()
              }

              Button {
                height: askActions.height
                text: "new session"
                active: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.body

                onClicked: root.newChat()
              }
            }
          }
        }

        StatusLine {
          id: statusLine

          width: parent.width
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          isError: (root.panelMode === States.PANEL.AI ? ai.status : session.status) === "error"
          mode: SearchLib.modeLabel({
            view: root.view, panelMode: root.panelMode, focusArea: root.focusArea,
            mode: input.mode, selecting: answerView.selecting
          })
          detail: SearchLib.statusText({
            view: root.view,
            panelMode: root.panelMode,
            status: root.panelMode === States.PANEL.AI ? ai.status : session.status,
            count: session.results.count,
            query: session.lastQuery,
            page: session.pageIndex + 1,
            hasNext: session.hasNext,
            loadingPage: session.loadingPage,
            errorMessage: root.panelMode === States.PANEL.AI ? ai.errorMessage : session.errorMessage,
            backend: session.backend,
            agent: ai.agentName,
            selecting: answerView.selecting
          })
        }

        SetupPrompt {
          id: setupPrompt

          visible: root.view === States.VIEW.SETUP
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

          visible: root.view === States.VIEW.SETTINGS
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

          visible: root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.AI
          width: parent.width
          height: parent.height - fieldRow.height - statusLine.height - Style.spacing.md * 2
          turns: ai.history
          thinking: ai.status === "thinking"
          agentName: ai.agentName
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

          visible: root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.SEARCH
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
