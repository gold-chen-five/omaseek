import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "settings/settings.mjs" as SettingsLib
import "shared/vim/keybinds.mjs" as Keybinds
import "shared/states.mjs" as States
import "shared/pixels.mjs" as Pixels
import "shared/terminal.mjs" as Terminal
import "panel/layout.mjs" as Layout
import "ask"
import "engine"
import "panel"
import "search"
import "settings"
import "shared"
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
  property bool keysOpen: false                // the ctrl+k lookup is over the card
  property string keysReturnTo: ""             // the focusArea it was opened from
  property bool introPending: false            // the welcome page is not finished: opening shows it
  readonly property var shortcutStatus: shortcut.status   // for the welcome page's SUPER + D step

  readonly property Item input: card.field
  readonly property var settingsRows: SettingsLib.settingsRows(config.settings, engine.state, ai.agents, ai.models,
    engine.test, engine.version, engine.speed, translator.models, shortcut.status)
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
  // The monitor's own scale (1.25), which Qt does not report: it draws at a
  // whole 2x and Hyprland scales that down. The bars size their frames to
  // whole monitor pixels with it (pixels.mjs).
  readonly property real outputScale: {
    const monitor = Hyprland.monitorFor(panel.screen)
    return monitor && monitor.scale > 0 ? monitor.scale : 1
  }

  // ---- shell contract -----------------------------------------------------

  // keepLoaded keeps the search and the conversation; reopen where they were.
  function open (payloadJson) {
    const fieldMode = input.mode
    config.reload()
    suggestions.clear()                        // they show again on the next thing typed
    opened = true
    if (ai.agents === null) ai.probeAgents()   // once: which agents this machine has
    commands.resetHistoryWalk()
    // Until the welcome page is finished, it is what opens — with each step
    // checked again, since a terminal it opened may have just done one.
    if (introPending) {
      view = States.VIEW.WELCOME
      engine.probe()
      shortcut.probe()
      card.welcomePage.open()
      return
    }
    view = States.VIEW.SEARCH                  // never reopen into settings or setup
    focusSearch(fieldMode)                     // first launch inherits the field's insert default
  }

  function close () {
    opened = false
    keysOpen = false
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
    suggestions.clear()
    panelMode = panelMode === States.PANEL.SEARCH ? States.PANEL.AI : States.PANEL.SEARCH
    view = States.VIEW.SEARCH
    focusSearch(fieldMode)
  }

  function openSettings () {
    view = States.VIEW.SETTINGS
    engine.probe()
    shortcut.probe()
    ai.probeAgents()
    card.settingsFilter.clear()
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

  // ctrl+k: the key lookup takes the keyboard, and closing it gives the
  // keyboard back where it was — the field in the mode it was in, or the pane.
  function openKeys () {
    if (keysOpen) {
      closeKeys()
      return
    }
    keysReturnTo = focusArea
    keysOpen = true
    Qt.callLater(() => card.keysLookup.open())
  }

  function closeKeys () {
    keysOpen = false
    // Opened over settings: closing it leaves settings too, back to the search
    // or ask page underneath, as esc there would.
    if (view === States.VIEW.SETTINGS) closeSettings()
    else if (keysReturnTo === States.FOCUS.TRANSLATION && translator.open) focusTranslation()
    else if (keysReturnTo === States.FOCUS.RESULTS && hasBody()) focusResults()
    else focusSearch(input.mode)
  }

  // ctrl+c in search: the results and the bar cleared, and the bar ready to
  // type — what a new session is in the other half.
  function clearSearch () {
    suggestions.clear()
    session.reset()
    commands.resetHistoryWalk()
    input.clear()
    focusSearch("insert")
  }

  // Through setMode, so leaving insert steps the cursor left and clears any
  // half-typed operator.
  function focusSearch (mode) {
    focusArea = States.FOCUS.FIELD
    if (mode === "i" || mode === "a") input.enterInsert(mode)
    else input.setMode(mode)
    Qt.callLater(() => input.forceActiveFocus())
  }

  // ctrl+v from the results or an answer: the clipboard into the bar, still
  // typing — where the cursor was, or after the block cursor as `a` would.
  function pasteIntoField () {
    focusSearch(input.mode === "insert" ? "insert" : "a")
    input.pasteClipboard()
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

  // The first time omaseek is loaded it opens itself, on the welcome page: a
  // fresh install has no SearXNG and no SUPER + D, and an icon that appeared
  // somewhere on the bar is easy to miss. The file remembers that it did, and
  // whether the page was finished — until it is, opening shows it again.
  JsonFile {
    id: firstRun

    name: "omaseek/first-run.json"
    onLoaded: text => {
      if (text.trim() === "") {
        welcomeDelay.start()
        return
      }
      try {
        root.introPending = JSON.parse(text).done === false
      } catch (error) {
        root.introPending = false              // unreadable: not worth a page nobody asked for
      }
    }
  }

  // After the load that raised this has finished, so the shell has handed over
  // `shell` and can summon the panel the way the bar icon does.
  Timer {
    id: welcomeDelay
    interval: 500
    onTriggered: root.welcome()
  }

  function welcome () {
    firstRun.write(JSON.stringify({ version: 1, welcomed: Date.now(), done: false }) + "\n")
    introPending = true
    placeBarIcon()
    const id = manifest?.id ?? "omaseek"
    const summoned = shell && typeof shell.summon === "function" && shell.summon(id, "{}")
    if (!summoned) open("{}")
  }

  // Start searching, or esc, on the welcome page: it is not shown again.
  function finishIntro () {
    introPending = false
    firstRun.write(JSON.stringify({ version: 1, done: true }) + "\n")
    view = States.VIEW.SEARCH
    focusSearch("insert")
  }

  // Omarchy puts a new bar widget after the weather in the centre; the icon
  // goes to the centre's left end instead, where it reads as the start of the
  // bar's middle. Once, on the first run, and only when it is still in the
  // centre — an installer asked for left or right, and that answer stands.
  function placeBarIcon () {
    const id = manifest?.id ?? "omaseek"
    Quickshell.execDetached(["bash", "-c",
      'f="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"; '
      + 'jq -e --arg id "$1" \'(.bar.layout.center // []) | map(.id) | index($id)\' "$f" >/dev/null 2>&1 '
      + '&& omarchy-shell shell moveBarWidget "$1" \'{"section":"center","index":0}\' >/dev/null 2>&1',
      "place-icon", id])
  }

  // The welcome page's steps: each terminal ends by bringing the panel back to
  // the page, since whoever pressed them may not know another way in yet.
  readonly property string comeBackCommand: Terminal.summonCommand(manifest?.id ?? "omaseek")
  function setUpEngine () { engine.start(comeBackCommand) }
  function addShortcut () { shortcut.add(comeBackCommand) }

  // The dropdown under the search bar, while a search is being typed there.
  Suggestions {
    id: suggestions

    backendPath: engine.backendPath
    enabled: config.settings.searchSuggestions !== "off"
    past: queries.queries
    active: root.opened && root.view === States.VIEW.SEARCH && root.panelMode === States.PANEL.SEARCH
      && root.focusArea === States.FOCUS.FIELD && !root.keysOpen
      && root.input.mode === "insert" && root.input.activeFocus
  }

  Binding { target: root.input; property: "completing"; value: suggestions.showing }

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

  Shortcut {
    id: shortcut
    onLaunching: root.dismiss()
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
    chatEffort: SettingsLib.selectedEffort(config.settings, ai.agents)
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
    suggestions: suggestions
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
    shortcut: shortcut
  }

  // The field's signals: what Enter, the arrows and the panel keys ask for.
  Connections {
    target: root.input

    function onSubmitted () { commands.runSearch() }
    function onCancelled () { root.dismiss() }
    // With nothing below to read, j reaches a translation of the bar (gT).
    function onSteppedDown () { if (root.hasBody()) root.focusResults(); else root.focusTranslation() }
    function onHistoryPrevRequested () { commands.walkHistory(1) }
    function onCompletionStepped (delta) { commands.stepSuggestion(delta) }
    // Past the draft there is no query left, so Down means the results.
    function onHistoryNextRequested () { if (!commands.walkHistory(-1) && root.hasBody()) root.focusResults() }
    // Typing leaves the walk: the field is the reader's again. A walk writing
    // the field is not typing, hence the flag. Only what is typed into a search
    // asks for suggestions: a question, or the bar rewritten by a walk or the
    // list, never leaves for SearXNG's autocompleter.
    function onTextChanged () {
      if (!commands.applyingHistory) commands.historyIndex = -1
      if (commands.applyingHistory || commands.applyingSuggestion) return
      if (suggestions.active) suggestions.type(root.input.text)
      else suggestions.clear()
    }
    function onRequestedSettings () { root.openSettings() }
    function onKeysRequested () { root.openKeys() }
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

      // The inside of the card, where the bars' frames start, lands on whole
      // monitor pixels. Centred as it was, the left edge fell on a fraction and
      // the bar's left border drew two columns thick (pixels.mjs).
      readonly property real insetX: contentLeftInset + contentRightInset

      // Wider while a translation is split off, and never bigger than the
      // screen: layout.mjs, checked against laptop and desktop screens.
      readonly property var size: Layout.cardSize(panel.width, panel.height, translator.open, Style.gapsOut, px => Style.space(px))

      width: Pixels.snapToDevice(size.width - insetX, root.outputScale) + insetX
      height: size.height
      x: Pixels.snapToDevice((parent.width - width) / 2 + contentLeftInset, root.outputScale) - contentLeftInset
      y: Pixels.snapToDevice((parent.height - height) / 2 + contentTopInset, root.outputScale) - contentTopInset
      host: root
      config: config
      ai: ai
      session: session
      engine: engine
      translator: translator
      commands: commands
      chat: chat
      settingsActions: settingsActions
      suggestions: suggestions
    }
  }
}
