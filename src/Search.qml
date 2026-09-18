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
import "lib/history.mjs" as History
import "lib/sessions.mjs" as Sessions
import "lib/translate.mjs" as TranslateLib
import "lib/urls.mjs" as Urls

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

  readonly property var settingsRows: SettingsLib.settingsRows(config.settings, engine.state, ai.agents, ai.models, engine.test, engine.version, engine.speed, translator.models)
  readonly property string chatModel: SettingsLib.selectedModel(config.settings, ai.agents, ai.models)

  // Every panel key, parsed, by action id; each falls back to its default.
  readonly property var chords: Keybinds.panelChords(config.settings)
  // The keys the field reads in normal mode beyond vim's: L, H and U.
  readonly property var normalChords: Keybinds.normalChords(config.settings)
  readonly property string clearSessionsKeyText: config.settings.clearSessionsKey || "ctrl+shift+x"
  property bool clearArmed: false              // the first press; the second forgets them
  property int historyIndex: -1                // where the query walk sits; -1 is what was typed
  property string historyDraft: ""             // what was typed, kept while the walk is away from it
  property bool applyingHistory: false         // a walk writing the field, not the reader typing
  property string notice: ""                   // what a key just did, on the status line for a beat
  // `/` in the pane being read, while it is still being typed.
  readonly property string findPrompt: panelMode === States.PANEL.AI
    ? answerView.findPrompt : resultsList.findPrompt

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
    const fieldMode = input.mode
    config.reload()
    opened = true
    view = States.VIEW.SEARCH                  // never reopen into settings or setup
    if (ai.agents === null) ai.probeAgents()   // once: which agents this machine has
    resetHistoryWalk()
    focusSearch(fieldMode)                     // first launch inherits the field's insert default
  }

  function close () {
    opened = false
    session.cancel()
  }

  // Only AI mode has a session to end; a search is simply replaced. The one
  // left behind stays in the ring, a Ctrl+N away.
  function newChat () {
    if (panelMode !== States.PANEL.AI) return
    disarmClear()
    ai.reset()
    input.clear()
    focusSearch("insert")
  }

  // The saved conversations: Ctrl+N walks them, Ctrl+X forgets one. Both leave
  // a half-typed question alone, and land in the transcript when there is one.
  function nextChat () {
    walkChats(1)
  }

  // gt, gT and the translate button: the text into the language set under
  // Translate, in the panel split off to the right. A new one replaces what
  // is there; the keyboard stays where it was.
  function translateText (value) {
    const target = TranslateLib.effectiveTarget(config.settings)
    if (translator.translate(value, target)) say("translating into " + TranslateLib.targetLabel(target) + "…")
  }

  function translateBar () {
    translateText(input.text.split(input.lineBreak).join("\n"))
  }

  function closeTranslation () {
    translator.close()
  }

  // Shift+tab: the next installed agent answers from now on. The conversation
  // does not change hands — every question already carries the turns before it
  // in its prompt, whoever wrote them — so the new agent picks it up as it is.
  function switchAgent () {
    const next = SettingsLib.nextAgent(ai.agents, config.settings.chatAgent)
    if (!next) {
      say(ai.agents && ai.agents.agents && ai.agents.agents.length ? "no other agent installed" : "no agent installed")
      return
    }
    config.change("chatAgent", next)
    say("now asking " + next + (ai.history.length > 0 ? " — it sees the conversation so far" : ""))
  }

  // L / H in the answer, and ctrl+n from either half: a step through the ring.
  function walkChats (delta) {
    if (panelMode !== States.PANEL.AI) return
    disarmClear()
    if (ai.walkSessions(delta)) showChat()
  }

  function closeChat () {
    // ctrl+x closes an open translation first, and does nothing else.
    if (translator.open) {
      closeTranslation()
      return
    }
    if (panelMode !== States.PANEL.AI) return
    disarmClear()
    if (ai.closeSession()) showChat()
  }

  // A square on the session strip, clicked.
  function pickChat (index) {
    disarmClear()
    if (ai.openSession(index)) showChat()
  }

  // Forgetting every conversation cannot be undone and there is no dialog in
  // this panel, so the key asks once: the status line says what the second
  // press will do, and anything else called off.
  function clearChats () {
    if (panelMode !== States.PANEL.AI || ai.sessionCount === 0) return
    if (!clearArmed) {
      clearArmed = true
      clearWindow.restart()
      return
    }
    disarmClear()
    ai.clearSessions()
    input.clear()
    focusSearch("insert")
  }

  // Stop the reply being written, keeping the conversation; retry the last
  // question once it failed, was stopped, or was lost to a restart.
  function stopAnswer () {
    if (panelMode !== States.PANEL.AI) return
    disarmClear()
    ai.stop()
  }

  function retryAnswer () {
    if (panelMode !== States.PANEL.AI) return
    disarmClear()
    if (ai.retry()) focusSearch("insert")      // as asking does
  }

  function disarmClear () {
    clearArmed = false
    clearWindow.stop()
  }

  Timer {
    id: clearWindow
    interval: 4000
    onTriggered: root.clearArmed = false
  }

  Timer {
    id: noticeWindow
    interval: 1200
    onTriggered: root.notice = ""
  }

  function showChat () {
    if (ai.history.length === 0) focusSearch("insert")
    else focusResults()
  }

  function toggleMode () {
    const fieldMode = input.mode
    resetHistoryWalk()
    panelMode = panelMode === States.PANEL.SEARCH ? States.PANEL.AI : States.PANEL.SEARCH
    view = States.VIEW.SEARCH
    focusSearch(fieldMode)
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
    if (key === "stream") {
      config.change("stream", action === "on")
      return
    }
    if (key === "engineUpdate" && action === "update") {
      engine.updateImage()
      return
    }
    if (key === "engineTest" && action === "test") {
      engine.runTest()
      return
    }
    if (key === "engineSpeed" && action === "time") {
      engine.timeSearch()
      return
    }
    if (key.indexOf("searxngEngine:") === 0) {
      const name = key.slice("searxngEngine:".length)
      config.change("searxngEngines", SettingsLib.toggleEngine(config.settings, name, action === "on"))
      engine.test = null                       // both described the engines as they were
      engine.speed = null
      return
    }
    if (key !== "engine") return
    if (action === "stop") engine.stop()
    else engine.start()
  }

  // ---- focus --------------------------------------------------------------

  // `searching` forces a search: gs on a title that happens to look like a
  // domain means "find this", not "go there".
  function runSearch (searching) {
    const query = input.text.trim()
    if (!query) return
    if (panelMode === States.PANEL.AI) {
      ai.ask(query.split(input.lineBreak).join("\n"))
      resetHistoryWalk()                       // ↑ starts again from the question just asked
      input.clear()                            // the question now lives in the transcript
      // Straight into the answer, as Enter in search goes to the results: the
      // reply is what is read next, and q there stops it. i, a or gi go back to
      // the field for the next question.
      focusResults()
      return
    }
    const flat = SearchLib.cleanQuery(query.split(input.lineBreak).join(" "))
    // The field shows what is searched: stray spaces at either end, or a run of
    // them inside, are gone once Enter has read it.
    if (input.text !== flat) input.setQuery(flat)
    queries.remember(flat)                     // the arrows walk back to it next time
    resetHistoryWalk()
    // A pasted address is opened, as a browser's address bar would; anything
    // that is not unmistakably one (vue.js, README.md) is still searched.
    const address = searching === true ? "" : Urls.queryUrl(flat)
    if (address) {
      openUrl(address)
      return
    }
    session.search(flat)
    focusSearch("normal")                      // keep the query readable while results load
  }

  // ---- the queries searched before ----------------------------------------

  // Up and Down in the one-line search field. The draft is what the reader had
  // typed: it is kept aside on the first step away and put back on the last step
  // home. An unchanged index means the walk had nowhere to go, which is how Down
  // at the draft still steps into the results.
  function walkHistory (delta) {
    // Search walks the queries it searched; ask, the questions in its saved
    // conversations — the same walk over a different list.
    const past = panelMode === States.PANEL.AI ? Sessions.pastQuestions(ai.sessions) : queries.queries
    if (historyIndex === -1) historyDraft = input.text
    const step = History.stepQuery(past, historyIndex, delta, historyDraft)
    if (step.index === historyIndex) return false
    historyIndex = step.index
    applyingHistory = true
    input.setQuery(step.text)
    applyingHistory = false
    return true
  }

  function resetHistoryWalk () {
    historyIndex = -1
    historyDraft = ""
  }

  // ---- the two halves, from each other ------------------------------------

  // Every yank in the panel lands on the system clipboard, so one taken here
  // puts in the field with p.
  function copyText (value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  // Nothing moves on screen when a yank works, so the status line says so for a
  // beat — the line clearArmed already borrows.
  function say (message) {
    notice = message
    noticeWindow.restart()
  }

  function yankResult (index, withTitle) {
    const text = session.yankText(index, withTitle)
    if (!text) return
    copyText(text)
    say(SearchLib.yankNotice(withTitle))
  }

  // gc: the result over in the ask bar. Deliberately unsent — a question still
  // has to be typed around the URL.
  function askAboutResult (index) {
    const url = session.yankText(index, false)
    if (!url) return
    if (panelMode !== States.PANEL.AI) toggleMode()
    input.setQuery(url + " ")
    focusSearch("insert")
  }

  // gc in the answer: the passage in the ask bar, the cursor under it.
  // Unsent, as with a result: the question is the reader's to write.
  function askAboutText (text) {
    const passage = SearchLib.passageForQuestion(text)
    if (!passage) return
    input.setQuery(passage)
    focusSearch("insert")
  }

  // gs: the other way. A selection is already a whole query, so this one runs.
  function searchFor (text) {
    if (!text) return
    if (panelMode !== States.PANEL.SEARCH) toggleMode()
    input.setQuery(text)
    runSearch(true)
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

  HistoryStore { id: queries }

  Translator {
    id: translator

    askPath: Qt.resolvedUrl("../bin/ask").toString().replace(/^file:\/\//, "")
    modelAgent: SettingsLib.translateAgentOf(config.settings, ai.agents)
  }

  Engine {
    id: engine
    onLaunching: root.dismiss()                // the terminal takes the screen
  }

  SearchSession {
    id: session
    backendPath: engine.backendPath

    onPageShown: {
      resultsList.moveCursorTo(0)
      if (root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.SEARCH)
        root.focusResults()
    }
    onEngineDown: reason => root.askToStartEngine(reason)
    onEngineUp: engine.state = "running"
  }

  AiSession {
    id: ai
    askPath: Qt.resolvedUrl("../bin/ask").toString().replace(/^file:\/\//, "")
    chatAgent: config.settings.chatAgent
    chatModel: root.chatModel
    launcher: config.settings.launcher
    streaming: config.settings.stream

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

      width: Math.min(Style.space(translator.open ? 1200 : 820), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: content

        // The view below fills what the field, the strip and the status line
        // leave; a strip is there in one mode or the other — pages in search,
        // conversations in AI — and takes a gap with it.
        readonly property real viewHeight: Math.max(0, height - fieldRow.height - statusLine.height
          - Style.spacing.md * 2
          - (sessionTabs.visible ? sessionTabs.height + Style.spacing.md : 0)
          - (pageTabs.visible ? pageTabs.height + Style.spacing.md : 0))

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
          // for each line added with Ctrl+J or o/O, up to six.
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
                stoppable: root.panelMode === States.PANEL.AI && ai.status === "thinking"
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                verticalPadding: Style.spacing.md
                placeholderText: root.panelMode === States.PANEL.AI ? "Ask " + ai.agentName + "…" : "Search the web…"
                escapeSequences: config.keymap.sequences
                escapeTimeout: config.keymap.timeoutMs
                chords: root.chords
                normalChords: root.normalChords

                onSubmitted: root.runSearch()
                onCancelled: root.dismiss()
                onSteppedDown: if (root.hasBody()) root.focusResults()
                onHistoryPrevRequested: root.walkHistory(1)
                // Past the draft there is no query left, so Down means the results.
                onHistoryNextRequested: if (!root.walkHistory(-1) && root.hasBody()) root.focusResults()
                // Typing leaves the walk: the field is the reader's again. A walk
                // writing the field is not typing, hence the flag.
                onTextChanged: if (!root.applyingHistory) root.historyIndex = -1
                onRequestedSettings: root.openSettings()
                onTabbed: root.toggleMode()
                onAgentSwitchRequested: root.switchAgent()
                onTranslateRequested: text => root.translateText(text)
                onNewSessionRequested: root.newChat()
                onNextSessionRequested: root.nextChat()
                onSessionWalked: delta => root.walkChats(delta)
                onCloseSessionRequested: root.closeChat()
                onClearSessionsRequested: root.clearChats()
                onStopRequested: root.stopAnswer()
                onRetryRequested: root.retryAnswer()
                onLinkOpened: url => root.openUrl(url)

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
          Row {
            id: actions

            anchors.right: parent.right
            anchors.top: parent.top                // the field grows down; the buttons stay a line
            height: fieldFrame.oneLineHeight
            spacing: Style.spacing.sm

            // gT with a mouse: whatever is in the bar, into the panel beside
            // the results or the answer.
            Button {
              height: actions.height
              text: "translate"
              tooltipText: "translate the bar (gT)"
              active: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.body

              onClicked: root.translateBar()
            }

            Item {
              height: actions.height
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

                // While a reply is being written the button stops it, and after a
                // failure or a stop it asks again — the keys, with a mouse.
                Button {
                  height: askActions.height
                  text: ai.status === "thinking" ? "stop" : ai.canRetry && input.text.trim() === "" ? "retry" : "chat"
                  active: true
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.body

                  onClicked: {
                    if (ai.status === "thinking") root.stopAnswer()
                    else if (ai.canRetry && input.text.trim() === "") root.retryAnswer()
                    else root.runSearch()
                  }
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
        }

        StatusLine {
          id: statusLine

          width: parent.width
          isError: (root.panelMode === States.PANEL.AI ? ai.status : session.status) === "error"
          mode: SearchLib.modeLabel({
            view: root.view, panelMode: root.panelMode, focusArea: root.focusArea,
            mode: input.mode, selecting: answerView.selecting
          })
          // The destructive key takes the line over while it waits to be sure.
          detail: root.findPrompt ? root.findPrompt
            : root.clearArmed
            ? SearchLib.confirmClearText(root.clearSessionsKeyText, ai.sessionCount)
            : root.notice ? root.notice
            : SearchLib.statusText({
              view: root.view,
              panelMode: root.panelMode,
              status: root.panelMode === States.PANEL.AI ? ai.status : session.status,
              count: session.results.count,
              query: session.lastQuery,
              page: session.pageIndex + 1,
              hasNext: session.hasNext,
              loadingPage: session.loadingPage,
              pageTarget: session.pageTarget,
              pageError: session.pageError,
              nextPageKey: config.settings.nextPageKey,
              errorMessage: root.panelMode === States.PANEL.AI ? ai.errorMessage : session.errorMessage,
              backend: session.backend,
              agent: ai.agentName,
              selecting: answerView.selecting,
              link: answerView.cursorLink,
              session: ai.sessionLabel,
              // Which key stops depends on where the keyboard is: the answer's q,
              // the field's esc — twice from insert, the first leaving it.
              stopKey: root.focusArea === States.FOCUS.RESULTS ? "q"
                : input.mode === "insert" ? "esc esc" : "esc",
              retryKey: config.settings.retryAnswerKey,
              canRetry: ai.canRetry,
              address: root.panelMode === States.PANEL.SEARCH && root.focusArea === States.FOCUS.FIELD
                ? Urls.queryUrl(input.text.split(input.lineBreak).join(" ")) : ""
            })
        }

        // The mouse's h, l and 5gp: one square a page, and a › for the page
        // not fetched yet. Search's answer to the AI strip below.
        PageTabs {
          id: pageTabs

          visible: root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.SEARCH
            && session.status === "ok" && (session.pageCount > 1 || session.hasNext)
          width: parent.width
          pageCount: session.pageCount
          current: session.pageIndex
          hasNext: session.hasNext
          loading: session.loadingPage
          numbering: config.settings.pageNumbers

          onPicked: page => session.goToPage(page)
          onNextRequested: session.nextPage()
        }

        SessionTabs {
          id: sessionTabs

          visible: root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.AI
            && ai.sessionCount > 0
          width: parent.width
          sessions: ai.sessions
          pending: ai.pendingIds
          current: ai.sessionIndex

          onPicked: index => root.pickChat(index)
          onStarted: root.newChat()
        }

        SetupPrompt {
          id: setupPrompt

          visible: root.view === States.VIEW.SETUP
          width: parent.width
          reason: root.setupReason

          onConfirmed: engine.start()
          onCancelled: root.closeSetup()
        }

        SettingsPage {
          id: settingsPage

          visible: root.view === States.VIEW.SETTINGS
          width: parent.width
          height: content.viewHeight
          incomingRows: root.settingsRows
          settingsChord: root.chords.settings

          onChanged: (key, value) => {
            config.change(key, value)
            if (key === "searxngLanguage") { engine.test = null; engine.speed = null }
          }
          onActivated: (key, action) => root.runSettingAction(key, action)
          onClosed: root.closeSettings()
          onEditingFinished: Qt.callLater(() => settingsPage.forceActiveFocus())
        }

        // The reading half: the answer or the results, and — while a
        // translation is open — the panel split off to their right.
        Item {
          id: reading

          visible: root.view === States.VIEW.SEARCH
          width: parent.width
          height: content.viewHeight

          Item {
            id: readingPane

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: translator.open ? Math.round(parent.width * 0.58) : parent.width

            AnswerView {
              id: answerView

              binds: config.settings
              chords: root.chords
              lineNumbers: config.settings.lineNumbers

              visible: root.panelMode === States.PANEL.AI
              anchors.fill: parent
              turns: ai.history
              streamText: ai.liveStreamText
              thinking: ai.status === "thinking"
              agentName: ai.agentName

              onHandedOff: context => ai.launch(context)
              onLinkOpened: url => root.openUrl(url)
              onSearchRequested: text => root.searchFor(text)
              onEscaped: root.focusSearch("normal")
              onNormalRequested: root.focusSearch("normal")
              onInsertRequested: root.focusSearch("i")
              onAppendRequested: root.focusSearch("a")
              onSettingsRequested: root.openSettings()
              onTabbed: root.toggleMode()
              onAgentSwitchRequested: root.switchAgent()
              onTranslateRequested: text => root.translateText(text)
              onNewSessionRequested: root.newChat()
              onSessionWalked: delta => root.walkChats(delta)
              onCloseSessionRequested: root.closeChat()
              onClearSessionsRequested: root.clearChats()
              onStopRequested: root.stopAnswer()
              onRetryRequested: root.retryAnswer()
              onPutRequested: (text, after) => {
                root.focusSearch("normal")
                input.put(after, text)
              }
              onAskRequested: text => root.askAboutText(text)
            }

            ResultList {
              id: resultsList

              binds: config.settings
              lineNumbers: config.settings.lineNumbers

              visible: root.panelMode === States.PANEL.SEARCH
              anchors.fill: parent
              model: session.results

              onHandedOff: index => ai.launch(session.handoffText(index))
              onPageHandedOff: ai.launch(session.handoffText(-1))
              onYanked: (index, withTitle) => root.yankResult(index, withTitle)
              onAskRequested: index => root.askAboutResult(index)
              onSearchRequested: index => {
                const row = session.rowAt(index)
                if (row && row.title) root.searchFor(row.title)
              }
              onActivated: index => root.openResult(index)
              onEscaped: root.focusSearch("normal")
              onNormalRequested: root.focusSearch("normal")
              onInsertRequested: root.focusSearch("i")
              onAppendRequested: root.focusSearch("a")
              onSettingsRequested: root.openSettings()
              onNextPageRequested: pages => session.nextPage(pages)
              onPreviousPageRequested: pages => session.previousPage(pages)
              onPageJumpRequested: page => session.goToPage(page)
              onTabbed: root.toggleMode()
              onAgentSwitchRequested: root.switchAgent()
              onCloseSessionRequested: root.closeChat()
            }
          }

          TranslatePanel {
            id: translatePanel

            visible: translator.open
            anchors.left: readingPane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: Style.spacing.md
            source: translator.source
            text: translator.text
            status: translator.status
            errorMessage: translator.errorMessage
            targetLabel: translator.targetLabel
            startedAt: translator.startedAt
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily

            onClosed: root.closeTranslation()
            onCopied: text => {
              root.copyText(text)
              root.say("translation copied")
            }
          }
        }
      }
    }
  }
}
