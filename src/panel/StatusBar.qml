import QtQuick
import "../search/search.mjs" as SearchLib
import "../shared/states.mjs" as States
import "../shared/urls.mjs" as Urls

// The status line, fed: which mode the keyboard is in, and on the right what
// the panel is doing — a search typed after /, the second press forgetting
// every conversation waits for, a notice for a beat, else the search's or the
// conversation's state. StatusLine draws it and knows none of this.
StatusLine {
  id: status

  property var host: null                      // Search.qml: view, panelMode, focusArea, the field
  property var session: null
  property var ai: null
  property var answer: null                    // the answer view: selecting, the link under the cursor
  property var config: null
  property var chat: null                      // its armed clear

  readonly property bool asking: host.panelMode === States.PANEL.AI
  readonly property string clearKeyText: config.settings.clearSessionsKey || "ctrl+shift+x"

  isError: (asking ? ai.status : session.status) === "error"
  mode: SearchLib.modeLabel({
    view: host.view, panelMode: host.panelMode, focusArea: host.focusArea,
    mode: host.input.mode, selecting: answer.selecting
  })
  // The destructive key takes the line over while it waits to be sure.
  detail: host.findPrompt ? host.findPrompt
    : chat.clearArmed ? SearchLib.confirmClearText(clearKeyText, ai.sessionCount)
    : host.notice ? host.notice
    : SearchLib.statusText({
      view: host.view,
      panelMode: host.panelMode,
      status: asking ? ai.status : session.status,
      count: session.results.count,
      query: session.lastQuery,
      page: session.pageIndex + 1,
      hasNext: session.hasNext,
      loadingPage: session.loadingPage,
      pageTarget: session.pageTarget,
      pageError: session.pageError,
      nextPageKey: config.settings.nextPageKey,
      errorMessage: asking ? ai.errorMessage : session.errorMessage,
      backend: session.backend,
      agent: ai.agentName,
      effort: ai.chatEffort,
      selecting: answer.selecting,
      link: answer.cursorLink,
      session: ai.sessionLabel,
      // Which key stops depends on where the keyboard is: the answer's q, the
      // field's esc — twice from insert, the first leaving it.
      stopKey: host.focusArea === States.FOCUS.RESULTS ? "q"
        : host.input.mode === "insert" ? "esc esc" : "esc",
      retryKey: config.settings.retryAnswerKey,
      canRetry: ai.canRetry,
      address: !asking && host.focusArea === States.FOCUS.FIELD
        ? Urls.queryUrl(host.input.text.split(host.input.lineBreak).join(" ")) : ""
    })
}
