import QtQuick
import "../core"

// The agent CLIs through bin/ask: which are installed, the models the chosen
// one offers, and the two hand-offs to a terminal — a draft to the agent, and
// its sign-in. Discovery is serialised, so a slow answer for an agent nobody
// selects any more is dropped. Reads and writes the session (`session`).
Item {
  id: cli

  property var session: null

  function launch (text) {
    const prompt = String(text ?? "").trim()
    if (!prompt) return
    session.launching()
    launchProcess.start([session.askPath, "--launch", "--json",
                         JSON.stringify({ prompt: prompt, agent: session.chatAgent, model: session.chatModel, launcher: session.launcher })])
  }

  // Sign-in and setup belong to the CLI: hand them to a terminal with the pending
  // question chained after. `fix` picks which command runs.
  function login (fix) {
    session.launching()
    launchProcess.start([session.askPath, "--login", "--json",
                         JSON.stringify({ agent: session.chatAgent, model: session.chatModel, launcher: session.launcher,
                                          fix: fix || "login", prompt: lastQuestion() })])
  }

  function lastQuestion () {
    for (let i = session.history.length - 1; i >= 0; i--) {
      if (session.history[i].role === "user") return session.history[i].text
    }
    return ""
  }

  function probeAgents () {
    agentsProcess.start([session.askPath, "--agents"])
  }

  function probeModels () {
    if (!session.askPath || !session.modelAgent) return
    // Serialize discovery so a slow old agent can never overwrite a newer one.
    // The completion handler notices a changed selection and starts it next.
    if (modelsProcess.running) return
    if (session.models && session.models.agent === session.modelAgent) return
    modelsProcess.requestedAgent = session.modelAgent
    modelsProcess.start([session.askPath, "--models", "--json", JSON.stringify({ agent: session.modelAgent })])
  }

  JsonProcess {
    id: launchProcess

    onParsed: payload => { if (!payload.ok) session.fail(payload.message ?? "Could not open the agent") }
    onUnreadable: session.fail("Could not open the agent")
  }

  JsonProcess {
    id: agentsProcess

    onParsed: payload => {
      if (!payload.ok) return
      session.agents = payload
      session.probeModels()
    }
    onUnreadable: session.agents = ({ agents: [], default: "", configured: false })
  }

  // Discovery is serialised, so a slow answer for an agent nobody selected any
  // more is dropped rather than overwriting a newer one.
  JsonProcess {
    id: modelsProcess

    property string requestedAgent: ""

    function keep (result) {
      if (requestedAgent !== session.modelAgent) return
      session.models = { agent: requestedAgent, models: result.models || [], message: result.message || "" }
    }

    onParsed: payload => modelsProcess.keep(payload)
    onUnreadable: modelsProcess.keep({ models: [], message: "could not read the model list" })
    onExited: Qt.callLater(session.probeModels)
  }
}
