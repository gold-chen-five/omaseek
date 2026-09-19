import QtQuick
import qs.Commons
import qs.Ui
import "../shared/states.mjs" as States
import "../ask"
import "../engine"
import "../search"
import "../settings"

// The panel's card: the field bar and the status line on top, the strip of
// pages or conversations under them, and below that whichever view is showing
// — the answer or the results, settings, or the SearXNG setup. Laid out here;
// what each one does comes from the stores and commands Search.qml hands in.
BorderSurface {
  id: panelCard

  property var host: null                      // Search.qml: view, panelMode, focus, the panel keys
  property var config: null
  property var ai: null
  property var session: null
  property var engine: null
  property var translator: null
  property var commands: null
  property var chat: null
  property var settingsActions: null

  // What Search.qml reaches into: the field, the two reading panes, and the
  // two views it opens itself.
  readonly property Item field: fieldBar.field
  readonly property Item answerView: reading.answerView
  readonly property Item resultsList: reading.resultsList
  readonly property Item translationPanel: reading.translationPanel
  readonly property Item translationReader: reading.translationReader
  readonly property alias settingsPage: settingsPage
  readonly property alias setupPrompt: setupPrompt
  readonly property alias keysLookup: keysLookup

  radius: Style.cornerRadius
  color: host.background
  borderSpec: host.borderSpec
  padding: Style.spacing.panelPadding

  MouseArea { anchors.fill: parent; onClicked: {} }

  Column {
    id: content

    // The view below fills what the field, the strip and the status line
    // leave; a strip is there in one mode or the other — pages in search,
    // conversations in AI — and takes a gap with it.
    readonly property real viewHeight: Math.max(0, height - fieldBar.height - statusBar.height
      - Style.spacing.md * 2
      - (sessionTabs.visible ? sessionTabs.height + Style.spacing.md : 0)
      - (pageTabs.visible ? pageTabs.height + Style.spacing.md : 0))

    anchors.fill: parent
    anchors.topMargin: panelCard.contentTopInset
    anchors.rightMargin: panelCard.contentRightInset
    anchors.bottomMargin: panelCard.contentBottomInset
    anchors.leftMargin: panelCard.contentLeftInset
    spacing: Style.spacing.md

    FieldBar {
      id: fieldBar

      width: parent.width
      panelMode: panelCard.host.panelMode
      ai: panelCard.ai
      keymap: panelCard.config.keymap
      chords: panelCard.host.chords
      normalChords: panelCard.host.normalChords
      foreground: panelCard.host.foreground
      accent: panelCard.host.accent
      fontFamily: panelCard.host.fontFamily

      onTranslateClicked: panelCard.commands.translateBar()
      onSubmitClicked: panelCard.commands.runSearch()
      onStopClicked: panelCard.chat.stopAnswer()
      onRetryClicked: panelCard.chat.retryAnswer()
      onNewSessionClicked: panelCard.chat.newChat()
    }

    StatusBar {
      id: statusBar

      width: parent.width
      host: panelCard.host
      session: panelCard.session
      ai: panelCard.ai
      answer: reading.answerView
      config: panelCard.config
      chat: panelCard.chat
    }

    // The mouse's h, l and 5gp: one square a page, and a › for the page
    // not fetched yet. Search's answer to the AI strip below.
    PageTabs {
      id: pageTabs

      visible: panelCard.host.view === States.VIEW.SEARCH && panelCard.host.panelMode === States.PANEL.SEARCH
        && panelCard.session.status === "ok" && (panelCard.session.pageCount > 1 || panelCard.session.hasNext)
      width: parent.width
      pageCount: panelCard.session.pageCount
      current: panelCard.session.pageIndex
      hasNext: panelCard.session.hasNext
      loading: panelCard.session.loadingPage
      numbering: panelCard.config.settings.pageNumbers

      onPicked: page => panelCard.session.goToPage(page)
      onNextRequested: panelCard.session.nextPage()
    }

    SessionTabs {
      id: sessionTabs

      visible: panelCard.host.view === States.VIEW.SEARCH && panelCard.host.panelMode === States.PANEL.AI
        && panelCard.ai.sessionCount > 0
      width: parent.width
      sessions: panelCard.ai.sessions
      pending: panelCard.ai.pendingIds
      current: panelCard.ai.sessionIndex

      onPicked: index => panelCard.chat.pickChat(index)
      onStarted: panelCard.chat.newChat()
    }

    SetupPrompt {
      id: setupPrompt

      visible: panelCard.host.view === States.VIEW.SETUP
      width: parent.width
      reason: panelCard.host.setupReason

      onConfirmed: panelCard.engine.start()
      onCancelled: panelCard.host.closeSetup()
    }

    SettingsPage {
      id: settingsPage

      visible: panelCard.host.view === States.VIEW.SETTINGS
      width: parent.width
      height: content.viewHeight
      incomingRows: panelCard.host.settingsRows
      settingsChord: panelCard.host.chords.settings

      onChanged: (key, value) => panelCard.settingsActions.change(key, value)
      onActivated: (key, action) => panelCard.settingsActions.run(key, action)
      onClosed: panelCard.host.closeSettings()
      onEditingFinished: Qt.callLater(() => settingsPage.forceActiveFocus())
    }

    ReadingArea {
      id: reading

      visible: panelCard.host.view === States.VIEW.SEARCH
      width: parent.width
      height: content.viewHeight
      host: panelCard.host
      commands: panelCard.commands
      chat: panelCard.chat
      ai: panelCard.ai
      session: panelCard.session
      config: panelCard.config
      translator: panelCard.translator
      chords: panelCard.host.chords
      foreground: panelCard.host.foreground
      accent: panelCard.host.accent
      fontFamily: panelCard.host.fontFamily
    }
  }

  // ctrl+k, over everything else on the card until it closes.
  KeysLookup {
    id: keysLookup

    visible: panelCard.host.keysOpen
    anchors.fill: content
    z: 10
    settings: panelCard.config.settings
    closeChord: panelCard.host.chords.keysHelp
    foreground: panelCard.host.foreground
    accent: panelCard.host.accent
    fontFamily: panelCard.host.fontFamily

    onClosed: panelCard.host.closeKeys()
  }
}
