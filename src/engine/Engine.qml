import QtQuick
import Quickshell
import "../shared"
import "../shared/terminal.mjs" as Terminal

// The SearXNG instance: whether it answers, and the script that manages it.
Item {
  id: engine

  // What the last probe or search saw: unknown | running | stopped.
  property string state: "unknown"
  // The last endpoint test, as bin/search --test answered it; null before one ran.
  property var test: null
  // The last timed search, as bin/search --time answered it; null before one ran.
  property var speed: null
  // The running version against the newest image, as bin/search --version
  // answered it; null before a check.
  property var version: null

  readonly property string backendPath: Qt.resolvedUrl("../../bin/search").toString().replace(/^file:\/\//, "")
  readonly property string scriptPath: Qt.resolvedUrl("../../bin/searxng-up").toString().replace(/^file:\/\//, "")

  signal launching()                           // a terminal is about to take the screen

  // Omarchy runs nothing from a plugin it removes, so being unloaded is the only
  // notice there is. bin/on-remove says why the copy, and how a disable or a
  // restart is told apart from a removal.
  Component.onCompleted: Quickshell.execDetached([
    Qt.resolvedUrl("../../bin/on-remove").toString().replace(/^file:\/\//, ""), "--stage"
  ])
  Component.onDestruction: Quickshell.execDetached([
    "bash", "-c", '[ -n "$XDG_RUNTIME_DIR" ] && exec bash "$XDG_RUNTIME_DIR/omaseek-removal/on-remove" --watch'
  ])

  // /healthz touches no upstream engine, so this is cheap to ask.
  function probe () {
    state = "unknown"
    statusProcess.start([engine.backendPath, "--status"])
    version = { checking: true }
    versionProcess.start([engine.backendPath, "--version"])
  }

  // A real query with the configured engines and language. Not in a terminal:
  // it needs nothing from the reader and its answer belongs on the page.
  function runTest () {
    test = { running: true }
    testProcess.start([engine.backendPath, "--test"])
  }

  // One search as a keypress sends it, timed. The test asks each engine alone,
  // so only this says what a search actually waits for.
  function timeSearch () {
    speed = { running: true }
    speedProcess.start([engine.backendPath, "--time"])
  }

  // `comeBack`, from the welcome page, is the command that brings the panel
  // back once the terminal is done with (terminal.mjs).
  function start (comeBack) { run("", comeBack) }
  function stop () { run(" --stop") }
  function updateImage () { run(" --update") }

  // In a terminal: Docker may ask for sudo, and the first pull is worth watching.
  function run (flag, comeBack) {
    launching()
    state = "unknown"                          // whatever it was, it is changing
    Quickshell.execDetached([
      "xdg-terminal-exec", "bash", "-c",
      engine.scriptPath + flag + "; " + Terminal.terminalEnding(comeBack)
    ])
  }

  JsonProcess {
    id: testProcess

    onParsed: payload => {
      engine.test = payload
      engine.state = payload.ok ? "running" : payload.setup === true ? "stopped" : engine.state
    }
    onUnreadable: engine.test = ({ ok: false, message: "could not read the test's output" })
  }

  JsonProcess {
    id: speedProcess

    onParsed: payload => {
      engine.speed = payload
      engine.state = payload.ok ? "running" : payload.setup === true ? "stopped" : engine.state
    }
    onUnreadable: engine.speed = ({ ok: false, message: "could not read the search's output" })
  }

  JsonProcess {
    id: versionProcess

    onParsed: payload => engine.version = payload
    onUnreadable: engine.version = ({ ok: true, version: null, latest: null, current: null })
  }

  JsonProcess {
    id: statusProcess

    onParsed: payload => engine.state = payload.ok && payload.running ? "running" : "stopped"
    onUnreadable: engine.state = "unknown"
  }
}
