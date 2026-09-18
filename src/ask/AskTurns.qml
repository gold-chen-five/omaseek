import QtQuick
import Quickshell.Io
import "sessions.mjs" as Sessions

// The questions in flight: one process each, tagged with the conversation that
// asked, so an answer lands where it was asked however the reader has moved on
// — in the transcript if that conversation is on screen, else straight into its
// saved entry. The reply streams into a buffer per conversation, painted a few
// times a second. Reads and writes the session (`session`).
Item {
  id: turns

  property var session: null

  function startTurn (id, payload) {
    const turn = turnComponent.createObject(session, { sessionId: id })
    if (!turn) {
      session.fail("Could not start the agent")
      return
    }
    session.pendingTurns[id] = turn
    session.pendingIds = session.pendingIds.concat([id])
    session.streamBuffers[id] = ""
    if (id === session.liveId) session.liveStreamText = ""
    const command = [session.askPath]
    if (session.streaming) command.push("--stream")
    turn.command = command.concat(["--json", JSON.stringify(payload)])
    turn.running = true
  }

  // One line of the turn's output. A delta only ever shows: what is saved is the
  // text in the done event, so a delta misread here cannot corrupt the answer.
  function absorb (id, line) {
    const text = String(line ?? "").trim()
    if (!text || !session.isPending(id)) return
    let event
    try {
      event = JSON.parse(text)
    } catch (error) {
      return                                    // narration, not an event
    }
    if (event.event === "delta") {
      session.streamBuffers[id] = (session.streamBuffers[id] || "") + String(event.text ?? "")
      if (id === session.liveId) paint.start()          // coalesced: a repaint per token is wasted work
      return
    }
    if (event.event === "done" || event.ok !== undefined) deliver(id, event)
  }

  // Disowned first: stopping a process ends its stream, and a stream nobody
  // waits for must not be read as an answer.
  function cancelTurn (id) {
    const turn = session.pendingTurns[id]
    if (!turn) return
    forget(id)
    turn.running = false
  }

  function forget (id) {
    const turn = session.pendingTurns[id]
    if (turn) {
      delete session.pendingTurns[id]
      turn.destroy(0)
    }
    delete session.streamBuffers[id]
    if (id === session.liveId) {
      paint.stop()
      session.liveStreamText = ""
    }
    const rest = []
    for (let i = 0; i < session.pendingIds.length; i++) if (session.pendingIds[i] !== id) rest.push(session.pendingIds[i])
    session.pendingIds = rest
  }

  // A finished turn, by the conversation that asked it. `payload` is the done
  // event, whose body is the same object a whole answer would have been.
  function deliver (id, payload) {
    if (!session.isPending(id)) return                  // cancelled, or its conversation was closed
    forget(id)
    if (!payload || typeof payload !== "object") {
      report(id, "error", "Could not read the agent's output", "")
      return
    }
    if (!payload.ok) {
      report(id, "error", payload.message ?? "The agent failed", "")
      // Signing in takes the screen, so it is only offered for the conversation
      // the reader is actually in. Out of allowance is only reported.
      if (payload.login === true && id === session.liveId) session.cli.login(payload.fix)
      return
    }
    report(id, "assistant", String(payload.text ?? ""), payload.agent ?? "")
  }

  // The answer lands where it was asked: in the transcript if that conversation
  // is on screen, otherwise written into the ring, leaving the reader alone.
  function report (id, role, text, agentId) {
    if (id === session.liveId) {
      if (agentId) session.agent = agentId
      session.history = [...session.history, { role: role, text: text }]
      if (role === "error") {
        session.status = "error"
        session.errorMessage = text
      } else {
        session.status = "ok"
        session.answered()
      }
      return
    }
    const index = Sessions.indexOfSession(session.store.sessions, id)
    if (index < 0) return                       // the conversation went while it ran
    const entry = session.store.sessions[index]
    const step = Sessions.record(session.store.sessions, index,
                                 entry.turns.concat([{ role: role, text: text }]),
                                 agentId || entry.agent, Date.now())
    session.store.save(step.sessions)
  }

  // The reply so far reaches the screen a few times a second rather than once
  // per token: rendering the transcript is not free, and a token is not a frame.
  Timer {
    id: paint

    interval: 80
    onTriggered: session.liveStreamText = session.streamBuffers[session.liveId] || ""
  }

  // One per question in flight. It carries the id of the conversation that asked
  // so a late answer cannot land in whichever one is on screen when it arrives.
  Component {
    id: turnComponent

    Process {
      id: turn

      property string sessionId: ""

      // A line at a time rather than one blob at the end: the deltas are the
      // point. A turn that never reaches its done event — killed, or output
      // nobody could parse — is reported when the process exits.
      stdout: SplitParser {
        splitMarker: "\n"
        onRead: line => turns.absorb(turn.sessionId, line)
      }

      onExited: if (session.isPending(turn.sessionId)) {
        turns.deliver(turn.sessionId, { ok: false, message: "Could not read the agent's output" })
      }
    }
  }
}
