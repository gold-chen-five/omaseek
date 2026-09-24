import QtQuick
import "../shared/states.mjs" as States
import "../settings/settings.mjs" as SettingsLib

// What the conversation keys and the session strip do: a new conversation, a
// step through the saved ones, forgetting one or all, stopping and retrying a
// reply, and switching agent. Not in AiSession, which knows conversations and
// nothing of the screen: each of these also decides where the reader lands
// afterwards, which only the panel (`host`) can arrange.
Item {
  id: chat

  property var host: null                      // Search.qml: panelMode, the field, focus, say
  property var ai: null
  property var config: null
  property var translator: null

  property bool clearArmed: false              // the first press; the second forgets them

  // A fresh start. In AI mode the conversation left behind stays in the ring, a
  // Ctrl+N away; in search there is nothing to keep, so the results and the bar
  // are cleared.
  function newChat () {
    if (host.panelMode !== States.PANEL.AI) {
      host.clearSearch()
      return
    }
    disarmClear()
    ai.reset()
    host.input.clear()
    host.focusSearch("insert")
  }

  // Ctrl+N, and L / H in the answer: a step through the ring. Both leave a
  // half-typed question alone, and land in the transcript when there is one.
  function nextChat () {
    walkChats(1)
  }

  function walkChats (delta) {
    if (host.panelMode !== States.PANEL.AI) return
    disarmClear()
    if (ai.walkSessions(delta)) showChat()
  }

  // Ctrl+X closes what the keyboard is in: the translation once ctrl+l has
  // moved there, else the conversation on screen, showing the one below it.
  // Search has no conversation to close, so there it closes the translation.
  function closeChat () {
    if (translator.open && (host.focusArea === States.FOCUS.TRANSLATION || host.panelMode !== States.PANEL.AI)) {
      translator.close()
      return
    }
    if (host.panelMode !== States.PANEL.AI) return
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
    if (host.panelMode !== States.PANEL.AI || ai.sessionCount === 0) return
    if (!clearArmed) {
      clearArmed = true
      clearWindow.restart()
      return
    }
    disarmClear()
    ai.clearSessions()
    host.input.clear()
    host.focusSearch("insert")
  }

  // Stop the reply being written, keeping the conversation; retry the last
  // question once it failed, was stopped, or was lost to a restart.
  function stopAnswer () {
    if (host.panelMode !== States.PANEL.AI) return
    disarmClear()
    ai.stop()
  }

  function retryAnswer () {
    if (host.panelMode !== States.PANEL.AI) return
    disarmClear()
    if (ai.retry()) host.focusSearch("insert")  // as asking does
  }

  function disarmClear () {
    clearArmed = false
    clearWindow.stop()
  }

  // Shift+tab: the next installed agent answers from now on. The conversation
  // does not change hands — every question already carries the turns before it
  // in its prompt, whoever wrote them — so the new agent picks it up as it is.
  function switchAgent () {
    const next = SettingsLib.nextAgent(ai.agents, config.settings.chatAgent)
    if (!next) {
      host.say(ai.agents && ai.agents.agents && ai.agents.agents.length ? "no other agent installed" : "no agent installed")
      return
    }
    config.change("chatAgent", next)
    host.say("now asking " + next + (ai.history.length > 0 ? " — it sees the conversation so far" : ""))
  }

  function showChat () {
    if (ai.history.length === 0) host.focusSearch("insert")
    else host.focusResults()
  }

  Timer {
    id: clearWindow
    interval: 4000
    onTriggered: chat.clearArmed = false
  }
}
