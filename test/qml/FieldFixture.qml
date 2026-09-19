import QtQuick
import "../../src/field"

// The field under test, in AI mode with jk as its escape, and a count of every
// signal it raises: each tst_field_* file builds on this.
Item {
  readonly property alias field: fieldObject

  VimTextField {
    id: fieldObject
    anchors.fill: parent
    multiline: true
    escapeSequences: ["jk"]
    escapeTimeout: 1000
  }

  property int nextSessions: 0
  property int closedSessions: 0
  property int clearedSessions: 0
  property int stops: 0
  property int retries: 0
  property int olderAsked: 0
  property int agentSwitches: 0
  property int tabs: 0
  property var translated: []
  property var handedOff: []                 // [text, everything] per ga / gA
  property var barCommands: []               // [command, text] per gd / gj / gs
  property int cancels: 0
  property var opened: []

  Connections {
    target: fieldObject
    function onNextSessionRequested () { nextSessions++ }
    function onCloseSessionRequested () { closedSessions++ }
    function onClearSessionsRequested () { clearedSessions++ }
    function onStopRequested () { stops++ }
    function onCancelled () { cancels++ }
    function onLinkOpened (url) { opened = opened.concat([url]) }
    function onRetryRequested () { retries++ }
    function onHistoryPrevRequested () { olderAsked++ }
    function onAgentSwitchRequested () { agentSwitches++ }
    function onTabbed () { tabs++ }
    function onTranslateRequested (text) { translated = translated.concat([text]) }
    function onHandedOff (text, everything) { handedOff = handedOff.concat([[text, everything]]) }
    function onAskNowRequested (text, whole) { barCommands = barCommands.concat([[whole ? "ask" : "askSelection", text]]) }
    function onAskAboutRequested (text) { barCommands = barCommands.concat([["askAbout", text]]) }
    function onSearchRequested (text) { barCommands = barCommands.concat([["search", text]]) }
  }

}
