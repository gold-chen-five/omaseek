import QtQuick
import Quickshell.Io
import "sessions.mjs" as Sessions
import "../shared"

// The conversation with an agent, one print-mode process per turn. The CLI
// remembers nothing, so the transcript lives here and travels in each prompt.
//
// A question outlives the conversation being on screen: ctrl+c, ctrl+n and the
// strip all leave the turn running and start or show another, so each turn is
// its own Process tagged with the id of the conversation that asked, and the
// answer is written home — to the transcript if it is still in front of the
// reader, otherwise straight into the ring.
Item {
  id: session

  property string askPath: ""
  property string chatAgent: "default"         // from settings: 'default' or an id
  property string chatModel: ""                 // validated discovery result; empty is CLI default
  property string chatEffort: ""                // the level for chatAgent; empty is CLI default
  property string launcher: "terminal"

  property string status: "idle"               // idle | thinking | ok | error | stopped
  property string errorMessage: ""
  property string agent: ""                    // who answered last, by id
  property var history: []                     // [{ role: 'user'|'assistant'|'error', text }]
  property var agents: null                    // { agents: [{id, name}], default, configured } once probed
  property int sessionIndex: -1                // where in the ring the live conversation sits, -1 unsaved
  property bool restoring: false               // a conversation being loaded is not a new one to record
  property string liveId: ""                   // the id of the conversation on screen, "" when it has no turns
  property var pendingIds: []                  // conversations with a question in flight
  property var pendingTurns: ({})              // id -> its Process; not for bindings
  property bool streaming: true                // show a reply as it is written
  property var streamBuffers: ({})             // id -> the reply so far; not for bindings
  property string liveStreamText: ""           // the buffer of the conversation on screen
  readonly property var sessions: store.sessions
  readonly property int sessionCount: sessions.length
  readonly property string sessionLabel: Sessions.sessionLabel(sessionIndex, sessionCount)
  function isPending (id) { return id !== "" && pendingIds.indexOf(id) !== -1 }
  // A failed, stopped or interrupted last question, and nothing running for it.
  readonly property bool canRetry: !isPending(liveId) && Sessions.retryPoint(history) !== -1
  property var models: null                    // { agent, models, message } for the selected CLI
  readonly property string modelAgent: chatAgent !== "default" ? chatAgent
    : agents && agents.default ? agents.default : ""
  onModelAgentChanged: cli.probeModels()

  readonly property string agentName: agent !== "" ? agent
    : chatAgent !== "default" ? chatAgent
    : agents && agents.default ? agents.default
    : "the agent"

  signal answered()
  signal launching()                           // a terminal is about to take the screen

  // Every turn is saved as it happens: the panel is dismissed, not closed, and
  // a question asked before a shell restart is still worth having afterwards.
  onHistoryChanged: if (!restoring) remember()

  SessionStore {
    id: storePart
    // The file is read asynchronously: a question asked before it lands waits
    // for it, or it would be recorded into a ring that is about to be replaced.
    onReadyChanged: if (ready) session.remember()
  }

  function remember () {
    if (history.length === 0) return            // an emptied conversation writes nothing
    if (liveId === "") liveId = Sessions.newId(Date.now())
    if (!store.ready) return                    // the saved conversations are not known yet
    const step = Sessions.record(store.sessions, sessionIndex, history, agent, Date.now(), liveId)
    sessionIndex = step.index
    store.save(step.sessions)
  }

  // A question that was never answered is not worth a square once its
  // conversation is left: it was recorded so a turn in flight survives a
  // restart, not to keep the stub. Returns where it sat, or -1.
  function dropUnanswered () {
    if (sessionIndex < 0 || Sessions.isAnswered(history)) return -1
    if (isPending(liveId)) return -1            // its answer is still on its way
    if (Sessions.endsStopped(history)) return -1  // stopped on purpose, to come back and retry
    const at = sessionIndex
    const step = Sessions.removeSession(store.sessions, at)
    store.save(step.sessions)
    sessionIndex = -1
    return at
  }

  // Ctrl+N and the answer's L: the next saved conversation, wrapping; from an
  // unsaved one, the newest. H and a count walk the other way and further.
  // Nothing saved, nothing to show.
  function nextSession () { return walkSessions(1) }

  function walkSessions (delta) {
    const step = delta === undefined || delta === 0 ? 1 : delta
    const dropped = dropUnanswered()
    // The stub vacated a slot: stepping on lands on what was below it, stepping
    // back on what was above, both of which have shifted up by one.
    const from = dropped >= 0 ? (step > 0 ? dropped - 1 : dropped) : sessionIndex
    const next = Sessions.stepSession(store.sessions, from, step)
    if (next < 0) return false
    show(next)
    return true
  }

  // Ctrl+X: forget this conversation and show whichever takes its place.
  function closeSession () {
    if (sessionIndex < 0) return false          // an unsaved conversation is empty already
    turns.cancelTurn(liveId)                          // nobody will read this answer
    const step = Sessions.removeSession(store.sessions, sessionIndex)
    store.save(step.sessions)
    if (step.index < 0) reset()
    else show(step.index)
    return true
  }

  // Ctrl+Shift+X: forget every saved conversation, the one on screen with them.
  // Questions still running belong to conversations nobody will read, so they
  // are stopped rather than left to finish.
  function clearSessions () {
    if (store.sessions.length === 0 && history.length === 0) return false
    const running = pendingIds.slice(0)
    for (let i = 0; i < running.length; i++) turns.cancelTurn(running[i])
    reset()
    store.save([])
    return true
  }

  // A square on the strip: show that conversation, if it is still there.
  function openSession (index) {
    if (index < 0 || index >= store.sessions.length) return false
    show(index)
    return true
  }

  function show (index) {
    const entry = store.sessions[index]
    if (!entry) return
    restoring = true
    history = entry.turns
    liveStreamText = streamBuffers[entry.id] || ""
    restoring = false
    sessionIndex = index
    liveId = entry.id
    agent = entry.agent || ""
    // Coming back to a conversation still being answered picks the wait up
    // again; one that ended badly says so, with its retry.
    errorMessage = ""
    const last = history.length > 0 ? history[history.length - 1] : null
    if (isPending(liveId)) status = "thinking"
    else if (!last || last.role === "user") status = "idle"
    else if (last.stopped === true) status = "stopped"
    else if (last.role === "error") {
      status = "error"
      errorMessage = last.text
    } else status = "ok"
  }

  // Only this conversation is barred from asking twice at once; another may ask
  // while this one waits.
  function ask (question) {
    if (status === "thinking") return
    errorMessage = ""
    const payload = { question: question, history: Sessions.promptTurns(history), agent: chatAgent, model: chatModel,
                      effort: chatEffort }
    history = [...history, { role: "user", text: question }]   // remember() gives it its id
    status = "thinking"
    turns.startTurn(liveId, payload)
  }

  // Stop the reply being written for the conversation on screen. The question
  // stays, and the words so far with it, marked stopped so a retry can take
  // them back out; nothing else in the conversation changes.
  function stop () {
    if (!isPending(liveId)) return false
    const partial = streamBuffers[liveId] || ""
    turns.cancelTurn(liveId)
    history = [...history, Sessions.stoppedTurn(partial)]
    status = "stopped"
    errorMessage = ""
    return true
  }

  // Ask the last question again: after a failure, a stop, or a turn the shell
  // lost. What it left behind goes, so the new answer takes its place.
  function retry () {
    if (!canRetry) return false
    const at = Sessions.retryPoint(history)
    const question = history[at].text
    restoring = true                            // ask() records the conversation once
    history = history.slice(0, at)
    restoring = false
    status = "idle"
    ask(question)
    return true
  }

  // A new conversation. What was on screen stays in the ring — unless it was a
  // question that was never asked of anyone — and a turn still running keeps
  // running: its answer goes home to the conversation that asked it.
  function reset () {
    dropUnanswered()
    status = "idle"
    errorMessage = ""
    restoring = true
    history = []
    restoring = false
    sessionIndex = -1
    liveId = ""
    liveStreamText = ""              // the turn left running keeps writing into its own buffer
    agent = ""
  }

  // `agent` belongs to one conversation; clear it so the placeholder names who
  // answers next.
  onChatAgentChanged: agent = ""

  function fail (message) {
    status = "error"
    errorMessage = message
    history = [...history, { role: "error", text: message }]
  }

  // What the panel calls: a hand-off, the agent probe. The work is AgentCli's.
  function launch (text) { cli.launch(text) }
  function probeAgents () { cli.probeAgents() }
  function probeModels () { cli.probeModels() }

  AskTurns { id: turnsPart; session: session }
  AgentCli { id: cliPart; session: session }

  // The parts, reached from each other as session.<part>.
  readonly property var turns: turnsPart
  readonly property var cli: cliPart
  readonly property var store: storePart
}
