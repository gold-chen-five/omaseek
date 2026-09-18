import QtQuick
import qs.Commons
import "../shared/states.mjs" as States
import "../ask"
import "../search"
import "../translate"

// The half of the panel that is read: the answer in AI mode, the results in
// search, and — while a translation is open — the panel split off to their
// right. The two panes raise what the reader wants; this sends it where it
// goes: to the commands, the conversation keys, or back to the panel (`host`)
// for focus.
Item {
  id: area

  property var host: null                      // Search.qml: panelMode, focus, settings, toggleMode
  property var commands: null
  property var chat: null
  property var ai: null
  property var session: null
  property var config: null
  property var translator: null
  property var chords: ({})
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property alias answerView: answer
  readonly property alias resultsList: results
  readonly property bool asking: host.panelMode === States.PANEL.AI

  Item {
    id: readingPane

    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: area.translator.open ? Math.round(parent.width * 0.58) : parent.width

    AnswerView {
      id: answer

      binds: area.config.settings
      chords: area.chords
      lineNumbers: area.config.settings.lineNumbers

      visible: area.asking
      anchors.fill: parent
      turns: area.ai.history
      streamText: area.ai.liveStreamText
      thinking: area.ai.status === "thinking"
      agentName: area.ai.agentName

      onHandedOff: context => area.ai.launch(context)
      onLinkOpened: url => area.commands.openUrl(url)
      onSearchRequested: text => area.commands.searchFor(text)
      onAskRequested: text => area.commands.askAboutText(text)
      onTranslateRequested: text => area.commands.translateText(text)
      onEscaped: area.host.focusSearch("normal")
      onNormalRequested: area.host.focusSearch("normal")
      onInsertRequested: area.host.focusSearch("i")
      onAppendRequested: area.host.focusSearch("a")
      onSettingsRequested: area.host.openSettings()
      onTabbed: area.host.toggleMode()
      onAgentSwitchRequested: area.chat.switchAgent()
      onNewSessionRequested: area.chat.newChat()
      onSessionWalked: delta => area.chat.walkChats(delta)
      onCloseSessionRequested: area.chat.closeChat()
      onClearSessionsRequested: area.chat.clearChats()
      onStopRequested: area.chat.stopAnswer()
      onRetryRequested: area.chat.retryAnswer()
      onPutRequested: (text, after) => {
        area.host.focusSearch("normal")
        area.host.input.put(after, text)
      }
    }

    ResultList {
      id: results

      binds: area.config.settings
      lineNumbers: area.config.settings.lineNumbers

      visible: !area.asking
      anchors.fill: parent
      model: area.session.results

      onHandedOff: index => area.ai.launch(area.session.handoffText(index))
      onPageHandedOff: area.ai.launch(area.session.handoffText(-1))
      onYanked: (index, withTitle) => area.commands.yankResult(index, withTitle)
      onAskRequested: index => area.commands.askAboutResult(index)
      onSearchRequested: index => {
        const row = area.session.rowAt(index)
        if (row && row.title) area.commands.searchFor(row.title)
      }
      onActivated: index => area.commands.openResult(index)
      onEscaped: area.host.focusSearch("normal")
      onNormalRequested: area.host.focusSearch("normal")
      onInsertRequested: area.host.focusSearch("i")
      onAppendRequested: area.host.focusSearch("a")
      onSettingsRequested: area.host.openSettings()
      onNextPageRequested: pages => area.session.nextPage(pages)
      onPreviousPageRequested: pages => area.session.previousPage(pages)
      onPageJumpRequested: page => area.session.goToPage(page)
      onTabbed: area.host.toggleMode()
      onAgentSwitchRequested: area.chat.switchAgent()
      onCloseSessionRequested: area.chat.closeChat()
    }
  }

  TranslatePanel {
    visible: area.translator.open
    anchors.left: readingPane.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.spacing.md
    source: area.translator.source
    text: area.translator.text
    status: area.translator.status
    errorMessage: area.translator.errorMessage
    targetLabel: area.translator.targetLabel
    startedAt: area.translator.startedAt
    foreground: area.foreground
    accent: area.accent
    fontFamily: area.fontFamily

    onClosed: area.translator.close()
    onCopied: text => {
      area.host.copyText(text)
      area.host.say("translation copied")
    }
  }
}
