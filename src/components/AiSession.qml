import QtQuick
import Quickshell.Io

// The conversation with an AI agent, one print-mode process per turn.
//
// The agent CLI remembers nothing between runs, so the transcript lives here
// and goes out with every question (bin/ask puts the last few turns in the
// prompt). `agents` is what bin/ask --agents found on this machine; the
// settings page offers exactly that list.
Item {
  id: session

  property string askPath: ""
  property string chatAgent: "default"         // from settings: 'default' or an id
  property string launcher: "terminal"

  property string status: "idle"               // idle | thinking | ok | error
  property string errorMessage: ""
  property string agent: ""                    // who answered last, by id
  property var history: []                     // [{ role: 'user'|'assistant', text }]
  property var agents: null                    // { agents: [{id, name}], default, configured } once probed

  // What bin/ask will answer as, for the placeholder and the thinking line.
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
    const payload = { question: question, history: history, agent: chatAgent }
    history = [...history, { role: "user", text: question }]
    run(askProcess, [session.askPath, "--json", JSON.stringify(payload)])
  }

  // Hand text to the agent in a terminal — the selection, or a whole answer.
  function launch (text) {
    const prompt = String(text ?? "").trim()
    if (!prompt) return
    launching()
    run(launchProcess, [session.askPath, "--launch", "--json",
                        JSON.stringify({ prompt: prompt, agent: chatAgent, launcher: launcher })])
  }

  function probeAgents () {
    run(agentsProcess, [session.askPath, "--agents"])
  }

  function reset () {
    askProcess.running = false
    status = "idle"
    errorMessage = ""
    history = []
  }

  function run (process, command) {
    process.running = false
    process.command = command
    process.running = true
  }

  function fail (message) {
    status = "error"
    errorMessage = message
  }

  // The transcript as one Markdown document for the answer view.
  function transcript () {
    const parts = []
    for (let i = 0; i < history.length; i++) {
      const turn = history[i]
      if (turn.role === "user") parts.push("**" + turn.text + "**")
      else parts.push(turn.text)
    }
    return parts.join("\n\n")
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
