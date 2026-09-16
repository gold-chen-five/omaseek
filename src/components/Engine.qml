import QtQuick
import Quickshell
import Quickshell.Io

// The SearXNG instance: whether it answers, and the script that manages it.
Item {
  id: engine

  // What the last probe or search saw: unknown | running | stopped.
  property string state: "unknown"

  readonly property string backendPath: Qt.resolvedUrl("../../bin/search").toString().replace(/^file:\/\//, "")
  readonly property string scriptPath: Qt.resolvedUrl("../../bin/searxng-up").toString().replace(/^file:\/\//, "")

  signal launching()                           // a terminal is about to take the screen

  // /healthz touches no upstream engine, so this is cheap to ask.
  function probe () {
    state = "unknown"
    statusProcess.running = false
    statusProcess.running = true
  }

  function start () { run("") }
  function stop () { run(" --stop") }
  function updateImage () { run(" --update") }

  // In a terminal: docker may ask for sudo, and the first pull is worth watching.
  function run (flag) {
    launching()
    state = "unknown"                          // whatever it was, it is changing
    Quickshell.execDetached([
      "xdg-terminal-exec", "bash", "-c",
      engine.scriptPath + flag + "; echo; read -n1 -r -p 'press any key to close'"
    ])
  }

  Process {
    id: statusProcess

    command: [engine.backendPath, "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const payload = JSON.parse(String(text ?? ""))
          engine.state = payload.ok && payload.running ? "running" : "stopped"
        } catch (error) {
          engine.state = "unknown"
        }
      }
    }
  }
}
