import QtQuick
import Quickshell.Io
import "../lib/sessions.mjs" as Sessions

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
  property string launcher: "terminal"

  property string status: "idle"               // idle | thinking | ok | error
  property string errorMessage: ""
  property string agent: ""                    // who answered last, by id
  property var history: []                     // [{ role: 'user'|'assistant'|'error', text }]
  property var agents: null                    // { agents: [{id, name}], default, configured } once probed
  property int sessionIndex: -1                // where in the ring the live conversation sits, -1 unsaved
  property bool restoring: false               // a conversation being loaded is not a new one to record
  property string liveId: ""                   // the id of the conversation on screen, "" when it has no turns
  property var pendingIds: []                  // conversations with a question in flight
  property var pendingTurns: ({})              // id -> its Process; not for bindings
  readonly property var sessions: store.sessions
  readonly property int sessionCount: sessions.length
  readonly property string sessionLabel: Sessions.sessionLabel(sessionIndex, sessionCount)
  function isPending (id) { return id !== "" && pendingIds.indexOf(id) !== -1 }
  property var models: null                    // { agent, models, message } for the selected CLI
  readonly property string modelAgent: chatAgent !== "default" ? chatAgent
    : agents && agents.default ? agents.default : ""
  onModelAgentChanged: probeModels()

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
    id: store
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
    const at = sessionIndex
    const step = Sessions.removeSession(store.sessions, at)
    store.save(step.sessions)
    sessionIndex = -1
    return at
  }

  // Ctrl+N: the next saved conversation, wrapping; from an unsaved one, the
  // newest. Nothing saved, nothing to show.
  function nextSession () {
    const dropped = dropUnanswered()
    // Stepping on from the slot the stub vacated lands on what was below it.
    const from = dropped >= 0 ? dropped - 1 : sessionIndex
    const next = Sessions.stepSession(store.sessions, from, 1)
    if (next < 0) return false
    show(next)
    return true
  }

  // Ctrl+X: forget this conversation and show whichever takes its place.
  function closeSession () {
    if (sessionIndex < 0) return false          // an unsaved conversation is empty already
    cancelTurn(liveId)                          // nobody will read this answer
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
    for (let i = 0; i < running.length; i++) cancelTurn(running[i])
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
    restoring = false
    sessionIndex = index
    liveId = entry.id
    agent = entry.agent || ""
    // Coming back to a conversation still being answered picks the wait up again.
    status = isPending(liveId) ? "thinking" : (history.length > 0 ? "ok" : "idle")
    errorMessage = ""
  }

  // Only this conversation is barred from asking twice at once; another may ask
  // while this one waits.
  function ask (question) {
    if (status === "thinking") return
    errorMessage = ""
    const payload = { question: question, history: answeredTurns(), agent: chatAgent, model: chatModel }
    history = [...history, { role: "user", text: question }]   // remember() gives it its id
    status = "thinking"
    startTurn(liveId, payload)
  }

  function startTurn (id, payload) {
    const turn = turnComponent.createObject(session, { sessionId: id })
    if (!turn) {
      fail("Could not start the agent")
      return
    }
    pendingTurns[id] = turn
    pendingIds = pendingIds.concat([id])
    turn.command = [session.askPath, "--json", JSON.stringify(payload)]
    turn.running = true
  }

  // Disowned first: stopping a process ends its stream, and a stream nobody
  // waits for must not be read as an answer.
  function cancelTurn (id) {
    const turn = pendingTurns[id]
    if (!turn) return
    forget(id)
    turn.running = false
  }

  function forget (id) {
    const turn = pendingTurns[id]
    if (turn) {
      delete pendingTurns[id]
      turn.destroy(0)
    }
    const rest = []
    for (let i = 0; i < pendingIds.length; i++) if (pendingIds[i] !== id) rest.push(pendingIds[i])
    pendingIds = rest
  }

  // A finished turn, by the conversation that asked it.
  function deliver (id, output) {
    if (!isPending(id)) return                  // cancelled, or its conversation was closed
    forget(id)
    let payload
    try {
      payload = JSON.parse(String(output ?? "").trim())
    } catch (error) {
      report(id, "error", "Could not read the agent's output", "")
      return
    }
    if (!payload.ok) {
      report(id, "error", payload.message ?? "The agent failed", "")
      // Signing in takes the screen, so it is only offered for the conversation
      // the reader is actually in. Out of allowance is only reported.
      if (payload.login === true && id === liveId) login(payload.fix)
      return
    }
    report(id, "assistant", String(payload.text ?? ""), payload.agent ?? "")
  }

  // The answer lands where it was asked: in the transcript if that conversation
  // is on screen, otherwise written into the ring, leaving the reader alone.
  function report (id, role, text, agentId) {
    if (id === liveId) {
      if (agentId) agent = agentId
      history = [...history, { role: role, text: text }]
      if (role === "error") {
        status = "error"
        errorMessage = text
      } else {
        status = "ok"
        answered()
      }
      return
    }
    const index = Sessions.indexOfSession(store.sessions, id)
    if (index < 0) return                       // the conversation went while it ran
    const entry = store.sessions[index]
    const step = Sessions.record(store.sessions, index,
                                 entry.turns.concat([{ role: role, text: text }]),
                                 agentId || entry.agent, Date.now())
    store.save(step.sessions)
  }

  // Answered questions and their answers; failures stay on screen only. Not named
  // `answered`: a function sharing a signal's name fails the whole component.
  function answeredTurns () {
    const kept = []
    for (let i = 0; i < history.length; i++) {
      const turn = history[i]
      if (turn.role === "user") {
        const next = history[i + 1]
        if (next && next.role === "assistant") kept.push(turn)
      } else if (turn.role === "assistant") {
        kept.push(turn)
      }
    }
    return kept
  }

  function launch (text) {
    const prompt = String(text ?? "").trim()
    if (!prompt) return
    launching()
    run(launchProcess, [session.askPath, "--launch", "--json",
                        JSON.stringify({ prompt: prompt, agent: chatAgent, model: chatModel, launcher: launcher })])
  }

  // Sign-in and setup belong to the CLI: hand them to a terminal with the pending
  // question chained after. `fix` picks which command runs.
  function login (fix) {
    launching()
    run(launchProcess, [session.askPath, "--login", "--json",
                        JSON.stringify({ agent: chatAgent, model: chatModel, launcher: launcher,
                                         fix: fix || "login", prompt: lastQuestion() })])
  }

  function lastQuestion () {
    for (let i = history.length - 1; i >= 0; i--) {
      if (history[i].role === "user") return history[i].text
    }
    return ""
  }

  function probeAgents () {
    run(agentsProcess, [session.askPath, "--agents"])
  }

  function probeModels () {
    if (!askPath || !modelAgent) return
    // Serialize discovery so a slow old agent can never overwrite a newer one.
    // The completion handler notices a changed selection and starts it next.
    if (modelsProcess.running) return
    if (models && models.agent === modelAgent) return
    modelsProcess.requestedAgent = modelAgent
    run(modelsProcess, [askPath, "--models", "--json", JSON.stringify({ agent: modelAgent })])
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
    agent = ""
  }

  // `agent` belongs to one conversation; clear it so the placeholder names who
  // answers next.
  onChatAgentChanged: agent = ""

  function run (process, command) {
    process.running = false
    process.command = command
    process.running = true
  }

  function fail (message) {
    status = "error"
    errorMessage = message
    history = [...history, { role: "error", text: message }]
  }

  // One per question in flight. It carries the id of the conversation that asked
  // so a late answer cannot land in whichever one is on screen when it arrives.
  Component {
    id: turnComponent

    Process {
      id: turn

      property string sessionId: ""

      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: session.deliver(turn.sessionId, String(text ?? ""))
      }
    }
  }

  Process {
    id: launchProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const payload = JSON.parse(String(text ?? "").trim())
          if (!payload.ok) session.fail(payload.message ?? "Could not open the agent")
        } catch (error) {
          session.fail("Could not open the agent")
        }
      }
    }
  }

  Process {
    id: agentsProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const payload = JSON.parse(String(text ?? "").trim())
          if (payload.ok) {
            session.agents = payload
            session.probeModels()
          }
        } catch (error) {
          session.agents = { agents: [], default: "", configured: false }
        }
      }
    }
  }

  Process {
    id: modelsProcess
    property string requestedAgent: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let result
        try {
          result = JSON.parse(String(text ?? "").trim())
        } catch (error) {
          result = { models: [], message: "could not read the model list" }
        }
        if (modelsProcess.requestedAgent === session.modelAgent) {
          session.models = { agent: modelsProcess.requestedAgent,
                             models: result.models || [], message: result.message || "" }
        }
      }
    }
    onExited: Qt.callLater(session.probeModels)
  }
}
