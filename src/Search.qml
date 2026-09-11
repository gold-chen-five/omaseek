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

// Web search and AI overlay. The layer-shell setup and the open/close/dismiss/
// toggle contract mirror shell/plugins/emojis/Emojis.qml, so shell IPC works
// the same. State lives in the stores; this file decides which view shows and
// whether the field or the view below it has the keyboard.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string view: States.VIEW.SEARCH
  property string panelMode: States.PANEL.SEARCH  // what Enter does with the field
  property string focusArea: States.FOCUS.FIELD  // who has the keyboard
  property string setupReason: ""              // what the backend said when the instance was down

  readonly property var settingsRows: SettingsLib.settingsRows(config.settings, engine.state, ai.agents)

  readonly property string searchChord: Keybinds.parseChord(config.settings.searchKey) || "Return"
  readonly property string newSessionChord: Keybinds.parseChord(config.settings.newSessionKey) || "C-c"

  // [menu] tokens, as the first-party overlays use: a theme switch repaints this.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.menu.selectedText
  readonly property color scrim: Color.menu.scrim
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  // ---- shell contract -----------------------------------------------------

  // keepLoaded keeps the search and the conversation; reopen where they were.
  function open (payloadJson) {
    config.reload()
    opened = true
    view = States.VIEW.SEARCH                  // never reopen into settings or setup
    if (ai.agents === null) ai.probeAgents()   // once: which agents this machine has
    // Normal when there is something below to step into, insert otherwise.
    focusSearch(!hasBody())
  }

  function close () {
    opened = false
    session.cancel()
  }

  // Only AI mode has a session to end; a search is simply replaced.
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

  // The instance is down: ask to start it rather than show an error.
  function askToStartEngine (reason) {
    engine.state = "stopped"
    setupReason = reason
    view = States.VIEW.SETUP
    setupPrompt.open()
  }

  function closeSetup () {
    view = States.VIEW.SEARCH
    setupReason = ""
    focusSearch(true)
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
      focusSearch(false)
      return
    }
    session.search(query)
    focusSearch(false)                         // normal: j steps into the results
  }

  function hasBody () {
    return panelMode === States.PANEL.AI ? ai.history.length > 0 : session.results.count > 0
  }

  function focusResults () {
    focusArea = States.FOCUS.RESULTS
    const target = panelMode === States.PANEL.AI ? answerView : resultsList
    Qt.callLater(() => target.forceActiveFocus())
  }

  // Through setMode, so leaving insert steps the cursor left and clears any
  // half-typed operator.
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
            font.pixelSize: Style.font.body
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

          // Reserves the wider arrangement, so the field keeps its width across modes.
          Item {
            id: actions

            anchors.right: parent.right
            anchors.top: parent.top                // the field grows down; the buttons stay a line
            height: input.oneLineHeight
            width: Math.max(searchButton.implicitWidth, askActions.implicitWidth)

            Button {
              id: searchButton

              visible: root.panelMode === States.PANEL.SEARCH
              anchors.fill: parent
              text: "search"
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
