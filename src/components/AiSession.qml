import QtQuick
import Quickshell.Io

// The conversation with an agent, one print-mode process per turn. The CLI
// remembers nothing, so the transcript lives here and travels in each prompt.
Item {
  id: session

  property string askPath: ""
  property string chatAgent: "default"         // from settings: 'default' or an id
  property string launcher: "terminal"

  property string status: "idle"               // idle | thinking | ok | error
  property string errorMessage: ""
  property string agent: ""                    // who answered last, by id
  property var history: []                     // [{ role: 'user'|'assistant'|'error', text }]
  property var agents: null                    // { agents: [{id, name}], default, configured } once probed

  readonly property string agentName: agent !== "" ? agent
    : chatAgent !== "default" ? chatAgent
    : agents && agents.default ? agents.default
    : "the agent"

  signal answered()
  signal launching()                           // a terminal is about to take the screen

  function ask (question) {
    if (status === "thinking") return
    status = "thinking"
    errorMessage = ""
    const payload = { question: question, history: answeredTurns(), agent: chatAgent }
    history = [...history, { role: "user", text: question }]
    run(askProcess, [session.askPath, "--json", JSON.stringify(payload)])
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
                        JSON.stringify({ prompt: prompt, agent: chatAgent, launcher: launcher })])
  }

  // Sign-in and setup belong to the CLI: hand them to a terminal with the pending
  // question chained after. `fix` picks which command runs.
  function login (fix) {
    launching()
    run(launchProcess, [session.askPath, "--login", "--json",
                        JSON.stringify({ agent: chatAgent, launcher: launcher,
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

  function reset () {
    askProcess.running = false
    status = "idle"
    errorMessage = ""
    history = []
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

  Process {
    id: askProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        let payload
        try {
          payload = JSON.parse(String(text ?? "").trim())
        } catch (error) {
          session.fail("Could not read the agent's output")
          return
        }
        if (!payload.ok) {
          session.fail(payload.message ?? "The agent failed")
          // Out of allowance is only reported: nothing in a terminal fixes it.
          if (payload.login === true) session.login(payload.fix)
          return
        }
        session.agent = payload.agent ?? ""
        session.history = [...session.history, { role: "assistant", text: String(payload.text ?? "") }]
        session.status = "ok"
        session.answered()
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
          if (payload.ok) session.agents = payload
        } catch (error) {
          session.agents = { agents: [], default: "", configured: false }
        }
      }
    }
  }
}
