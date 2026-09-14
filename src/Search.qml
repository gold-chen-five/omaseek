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
  readonly property string settingsChord: Keybinds.parseChord(config.settings.settingsKey) || "C-s"
  readonly property string switchChord: Keybinds.parseChord(config.settings.switchModeKey) || "Tab"

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
    focusSearch(hasBody() ? "normal" : "insert")
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
    focusSearch("insert")
  }

  function toggleMode () {
    panelMode = panelMode === States.PANEL.SEARCH ? States.PANEL.AI : States.PANEL.SEARCH
    view = States.VIEW.SEARCH
    focusSearch("insert")
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
    focusSearch("normal")
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
    focusSearch("insert")
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
      ai.ask(query.split(input.lineBreak).join("\n"))
      input.clear()                            // the question now lives in the transcript
      focusSearch("normal")
      return
    }
    session.search(query.split(input.lineBreak).join(" "))
    focusSearch("normal")                      // normal: j steps into the results
  }

  function hasBody () {
    return panelMode === States.PANEL.AI ? ai.history.length > 0 : session.results.count > 0
  }

  function focusResults () {
    // A reading pane is normal mode. Converting here gives a later i/a the
    // same character-under-cursor starting point as Vim.
    input.setMode("normal")
    focusArea = States.FOCUS.RESULTS
    const target = panelMode === States.PANEL.AI ? answerView : resultsList
    Qt.callLater(() => target.forceActiveFocus())
  }

  // Through setMode, so leaving insert steps the cursor left and clears any
  // half-typed operator.
  function focusSearch (mode) {
    focusArea = States.FOCUS.FIELD
    if (mode === "i" || mode === "a") input.enterInsert(mode)
    else input.setMode(mode)
    Qt.callLater(() => input.forceActiveFocus())
  }

  function openResult (index) {
    if (index < 0 || index >= session.results.count) return
    openUrl(session.results.get(index).url)
  }

  // The browser takes the screen, so the panel steps aside.
  function openUrl (url) {
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
          height: fieldFrame.height

          // The field's frame, drawn here rather than by the field: the field
          // scrolls inside it, and a frame it drew itself would scroll too. One
          // line tall at rest — the single-line field's height — and a row taller
          // for each Ctrl+J, up to six.
          BorderSurface {
            id: fieldFrame

            readonly property real insetTop: Border.top(input.borderSpec) + input.verticalPadding
            readonly property real insetBottom: Border.bottom(input.borderSpec) + input.verticalPadding
            readonly property real oneLineHeight: Math.round(input.lineHeight + insetTop + insetBottom)

            width: parent.width - actions.width - Style.spacing.sm
            height: Math.round(Math.min(input.lineCount, 6) * input.lineHeight + insetTop + insetBottom)
            radius: Style.cornerRadius
            color: Style.controlFill(input.activeFocus, input.hovered, root.foreground, root.accent)
            borderSpec: input.borderSpec

            Flickable {
              id: fieldScroll

              anchors.fill: parent
              anchors.leftMargin: Border.left(input.borderSpec) + input.horizontalPadding
              anchors.rightMargin: Border.right(input.borderSpec) + input.horizontalPadding
              anchors.topMargin: fieldFrame.insetTop
              anchors.bottomMargin: fieldFrame.insetBottom
              clip: true
              interactive: false               // it follows the cursor; nothing drags it
              contentWidth: input.width
              contentHeight: input.height

              VimTextField {
                id: input

                width: Math.max(fieldScroll.width, implicitWidth)
                height: Math.max(fieldScroll.height, implicitHeight)
                multiline: root.panelMode === States.PANEL.AI
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
                settingsChord: root.settingsChord
                switchChord: root.switchChord

                onSubmitted: root.runSearch()
                onCancelled: root.dismiss()
                onSteppedDown: if (root.hasBody()) root.focusResults()
                onRequestedSettings: root.openSettings()
                onTabbed: root.toggleMode()
                onNewSessionRequested: root.newChat()

                // The frame scrolls to keep the cursor in view as it passes an edge.
                onCursorRectangleChanged: {
                  const r = cursorRectangle
                  if (r.x < fieldScroll.contentX) fieldScroll.contentX = r.x
                  else if (r.x + r.width > fieldScroll.contentX + fieldScroll.width) fieldScroll.contentX = r.x + r.width - fieldScroll.width
                  if (r.y < fieldScroll.contentY) fieldScroll.contentY = r.y
                  else if (r.y + r.height > fieldScroll.contentY + fieldScroll.height) fieldScroll.contentY = r.y + r.height - fieldScroll.height
                }
              }
            }
          }

          // Reserves the wider arrangement, so the field keeps its width across modes.
          Item {
            id: actions

            anchors.right: parent.right
            anchors.top: parent.top                // the field grows down; the buttons stay a line
            height: fieldFrame.oneLineHeight
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
            selecting: answerView.selecting,
            link: answerView.cursorLink
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
          height: Math.max(0, parent.height - fieldRow.height - statusLine.height - Style.spacing.md * 2)
          rows: root.settingsRows
          settingsChord: root.settingsChord
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
          binds: config.settings
          lineNumbers: config.settings.lineNumbers

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
          onLinkOpened: url => root.openUrl(url)
          onEscaped: root.focusSearch("normal")
          onNormalRequested: root.focusSearch("normal")
          onInsertRequested: root.focusSearch("i")
          onAppendRequested: root.focusSearch("a")
          onSettingsRequested: root.openSettings()
          onTabbed: root.toggleMode()
          onNewSessionRequested: root.newChat()
          onPutRequested: (text, after) => {
            root.focusSearch("normal")
            input.put(after, text)
          }
          newSessionChord: root.newSessionChord
        }

        ResultList {
          id: resultsList
          binds: config.settings
          lineNumbers: config.settings.lineNumbers

          visible: root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.SEARCH
          width: parent.width
          height: parent.height - fieldRow.height - statusLine.height - Style.spacing.md * 2
          model: session.results
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily

          onHandedOff: index => ai.launch(session.handoffText(index))
          onPageHandedOff: ai.launch(session.handoffText(-1))
          onActivated: index => root.openResult(index)
          onEscaped: root.focusSearch("normal")
          onNormalRequested: root.focusSearch("normal")
          onInsertRequested: root.focusSearch("i")
          onAppendRequested: root.focusSearch("a")
          onSettingsRequested: root.openSettings()
          onNextPageRequested: session.nextPage()
          onPreviousPageRequested: session.previousPage()
          onTabbed: root.toggleMode()
        }
      }
    }
  }
}
