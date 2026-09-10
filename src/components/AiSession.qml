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
  property var history: []                     // [{ role: 'user'|'assistant'|'error', text }]
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
    const payload = { question: question, history: answeredTurns(), agent: chatAgent }
    history = [...history, { role: "user", text: question }]
    run(askProcess, [session.askPath, "--json", JSON.stringify(payload)])
  }

  // The turns worth repeating to the agent: questions that got an answer,
  // and the answers. A failure and the question it failed on stay on screen
  // but do not travel. Not `answered` — that is the signal above, and a
  // function sharing the name makes the whole component fail to load.
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

  // Hand text to the agent in a terminal — the selection, or a whole answer.
  function launch (text) {
    const prompt = String(text ?? "").trim()
    if (!prompt) return
    launching()
    run(launchProcess, [session.askPath, "--launch", "--json",
                        JSON.stringify({ prompt: prompt, agent: chatAgent, launcher: launcher })])
  }

  // Signed out, or signed in with nothing configured — neither is something
  // the panel can fix: the CLI opens a browser, writes its own credentials,
  // asks which provider to use. So it is handed off like any other context —
  // to the launcher the user picked, carrying the question they just asked,
  // so putting it right ends in the agent with that question already asked
  // rather than back here to retype it. `fix` is which of the two the
  // backend hit; it names a different command for some agents.
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

  // `agent` is who answered, and it outranks the setting when naming the
  // agent on screen — an agent asked for by name should be reported by the
  // name it answered under. It therefore belongs to one conversation and has
  // to go when that conversation does, or the panel keeps offering to ask
  // someone it is no longer going to ask.
  onChatAgentChanged: agent = ""

  function run (process, command) {
    process.running = false
    process.command = command
    process.running = true
  }

  // A failure is written into the transcript under its question, where it
  // is read, rather than only into the status strip, where it is missed.
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
          // Whatever the backend says is fixable in a terminal opens by
          // itself there, with the question already on it. Being out of
          // allowance is not: it is reported and left alone, because no
          // command in a terminal will fix it.
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
