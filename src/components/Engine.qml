import QtQuick
import Quickshell
import Quickshell.Io

// The SearXNG instance, as far as the panel can see it: whether it answers,
// and the one script that starts or stops it.
//
// Both scripts are resolved through Qt.resolvedUrl so they are found through
// the dev symlink rather than under ~/.config/omarchy/plugins.
Item {
  id: engine

  // What the last probe or search saw: unknown | running | stopped.
  property string state: "unknown"

  readonly property string backendPath: Qt.resolvedUrl("../../bin/search").toString().replace(/^file:\/\//, "")
  readonly property string scriptPath: Qt.resolvedUrl("../../bin/searxng-up").toString().replace(/^file:\/\//, "")

  signal launching()                           // a terminal is about to take the screen

  // A cheap question — /healthz, no upstream engines — so the settings page
  // can show whether the instance is up without running a search.
  function probe () {
    state = "unknown"
    statusProcess.running = false
    statusProcess.running = true
  }

  function start () { run("") }
  function stop () { run(" --stop") }

  // A terminal, not a detached process: docker asks for sudo unless you are
  // in the docker group, and the first run pulls an image worth watching. So
  // this opens the user's terminal and leaves it open afterwards.
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
