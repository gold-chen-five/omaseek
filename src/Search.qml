import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "settings/settings.mjs" as SettingsLib
import "shared/vim/keybinds.mjs" as Keybinds
import "shared/states.mjs" as States
import "ask"
import "engine"
import "panel"
import "search"
import "settings"
import "translate"

// Web search and AI overlay. The layer-shell setup and the open/close/dismiss/
// toggle contract mirror shell/plugins/emojis/Emojis.qml, so shell IPC works
// the same. State lives in the stores and what the keys do in the command
// objects; this file decides which view shows and whether the field or the view
// below it has the keyboard, and lays the window out.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string view: States.VIEW.SEARCH
  property string panelMode: States.PANEL.SEARCH  // what Enter does with the field
  property string focusArea: States.FOCUS.FIELD  // who has the keyboard
  property string setupReason: ""              // what the backend said when the instance was down
  property string notice: ""                   // what a key just did, on the status line for a beat

  readonly property Item input: card.field
  readonly property var settingsRows: SettingsLib.settingsRows(config.settings, engine.state, ai.agents, ai.models,
    engine.test, engine.version, engine.speed, translator.models)
  // Every panel key, parsed, by action id; and the keys the field reads in
  // normal mode beyond vim's (L, H, U, gt, gT). Each falls back to its default.
  readonly property var chords: Keybinds.panelChords(config.settings)
  readonly property var normalChords: Keybinds.normalChords(config.settings)
  // `/` in the pane being read, while it is still being typed.
  readonly property string findPrompt: focusArea === States.FOCUS.TRANSLATION ? card.translationReader.findPrompt
    : panelMode === States.PANEL.AI ? card.answerView.findPrompt : card.resultsList.findPrompt

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
    commands.resetHistoryWalk()
    focusSearch(fieldMode)                     // first launch inherits the field's insert default
  }

  function close () {
    opened = false
    session.cancel()
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

  // ---- views and focus ----------------------------------------------------

  function toggleMode () {
    const fieldMode = input.mode
    commands.resetHistoryWalk()
    panelMode = panelMode === States.PANEL.SEARCH ? States.PANEL.AI : States.PANEL.SEARCH
    view = States.VIEW.SEARCH
    focusSearch(fieldMode)
  }

  function openSettings () {
    view = States.VIEW.SETTINGS
    engine.probe()
    ai.probeAgents()
    card.settingsPage.open()
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
    card.setupPrompt.open()
  }

  function closeSetup () {
    view = States.VIEW.SEARCH
    setupReason = ""
    focusSearch("insert")
  }

  function hasBody () {
    return panelMode === States.PANEL.AI ? ai.history.length > 0 : session.results.count > 0
  }

  function focusResults () {
    // A reading pane is normal mode. Converting here gives a later i/a the
    // same character-under-cursor starting point as Vim.
    input.setMode("normal")
    focusArea = States.FOCUS.RESULTS
    const target = panelMode === States.PANEL.AI ? card.answerView : card.resultsList
    Qt.callLater(() => target.forceActiveFocus())
  }

  // ctrl+l from a reading pane: the translation beside it takes the keyboard,
  // and ctrl+x there closes it rather than the conversation. A finished one is
  // read with vim keys; before that the panel holds the keys itself.
  function focusTranslation () {
    if (!translator.open) return
    input.setMode("normal")
    focusArea = States.FOCUS.TRANSLATION
    const target = translator.status === "done" ? card.translationReader : card.translationPanel
    Qt.callLater(() => target.forceActiveFocus())
  }

  // Back from the translation, or after it closed under the keyboard: the pane
  // beside it when it has something to read, else the field.
  function focusReading () {
    if (hasBody()) focusResults()
    else focusSearch("normal")
  }

  // Through setMode, so leaving insert steps the cursor left and clears any
  // half-typed operator.
  function focusSearch (mode) {
    focusArea = States.FOCUS.FIELD
    if (mode === "i" || mode === "a") input.enterInsert(mode)
    else input.setMode(mode)
    Qt.callLater(() => input.forceActiveFocus())
  }

  // Every yank in the panel lands on the system clipboard, so one taken here
  // puts in the field with p.
  function copyText (value) {
    if (value) Quickshell.execDetached(["wl-copy", "--", value])
  }

  // Nothing moves on screen when a yank works, so the status line says so for a
  // beat — the line the armed clear already borrows.
  function say (message) {
    notice = message
    noticeWindow.restart()
  }

  Timer {
    id: noticeWindow
    interval: 1200
    onTriggered: root.notice = ""
  }

  // ---- stores and commands ------------------------------------------------

  ConfigStore { id: config }

  HistoryStore { id: queries }

  Translator {
    id: translator

    // Closed by ctrl+x, ×, or anything else while it had the keyboard.
    onOpenChanged: if (!open && root.focusArea === States.FOCUS.TRANSLATION) root.focusReading()
    // The reader appears when a translation lands and goes when another starts;
    // the keyboard follows whichever of it and the panel is showing.
    onStatusChanged: if (open && root.focusArea === States.FOCUS.TRANSLATION) root.focusTranslation()

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
      card.resultsList.moveCursorTo(0)
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
    chatModel: SettingsLib.selectedModel(config.settings, ai.agents, ai.models)
    launcher: config.settings.launcher
    streaming: config.settings.stream

    onLaunching: root.dismiss()                // the terminal takes the screen
  }

  Commands {
    id: commands
    host: root
    session: session
    queries: queries
    ai: ai
    translator: translator
    config: config
  }

  ChatCommands {
    id: chat
    host: root
    ai: ai
    config: config
    translator: translator
  }

  SettingsActions {
    id: settingsActions
    config: config
    engine: engine
  }

  // The field's signals: what Enter, the arrows and the panel keys ask for.
  Connections {
    target: root.input

    function onSubmitted () { commands.runSearch() }
    function onCancelled () { root.dismiss() }
    // With nothing below to read, j reaches a translation of the bar (gT).
    function onSteppedDown () { if (root.hasBody()) root.focusResults(); else root.focusTranslation() }
    function onHistoryPrevRequested () { commands.walkHistory(1) }
    // Past the draft there is no query left, so Down means the results.
    function onHistoryNextRequested () { if (!commands.walkHistory(-1) && root.hasBody()) root.focusResults() }
    // Typing leaves the walk: the field is the reader's again. A walk writing
    // the field is not typing, hence the flag.
    function onTextChanged () { if (!commands.applyingHistory) commands.historyIndex = -1 }
    function onRequestedSettings () { root.openSettings() }
    function onTabbed () { root.toggleMode() }
    function onAgentSwitchRequested () { chat.switchAgent() }
    function onTranslateRequested (text) { commands.translateText(text) }
    function onHandedOff (text, everything) { commands.handOffBar(text, everything) }
    function onAskNowRequested (text, whole) { commands.askFromBar(text, whole) }
    function onAskAboutRequested (text) { commands.askAboutText(text) }
    function onSearchRequested (text) { commands.searchFor(String(text).split(root.input.lineBreak).join(" ")) }
    function onNewSessionRequested () { chat.newChat() }
    function onNextSessionRequested () { chat.nextChat() }
    function onSessionWalked (delta) { chat.walkChats(delta) }
    function onCloseSessionRequested () { chat.closeChat() }
    function onClearSessionsRequested () { chat.clearChats() }
    function onStopRequested () { chat.stopAnswer() }
    function onRetryRequested () { chat.retryAnswer() }
    function onLinkOpened (url) { commands.openUrl(url) }
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

    PanelCard {
      id: card

      // Wider while a translation is split off, so the pane beside it keeps its width.
      width: Math.min(Style.space(translator.open ? 1200 : 820), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      host: root
      config: config
      ai: ai
      session: session
      engine: engine
      translator: translator
      commands: commands
      chat: chat
      settingsActions: settingsActions
    }
  }
}
