import QtQuick
import Quickshell
import Quickshell.Io
import "../shared"
import "../shared/terminal.mjs" as Terminal

// The SearXNG instance: whether it answers, and the script that manages it.
Item {
  id: engine

  // What the last probe or search saw: unknown | running | stopped.
  property string state: "unknown"
  // The engine bin/searxng-up uses — the one SearXNG was made with, else the
  // one it would choose — as the last probe heard it: podman | docker | "".
  property string engineName: ""
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

  // Whether omaseek ever set SearXNG up: a container or an image it made, under
  // either engine. bin/searxng-up --present answers without sudo or a daemon;
  // exit 0 is yes. `done` gets a bool.
  property var presentCallback: null

  function checkPresent (done) {
    presentCallback = done
    presentProcess.running = false
    presentProcess.running = true
  }

  // /healthz touches no upstream engine, so this is cheap to ask.
  function probe () {
    state = "unknown"
    engineProcess.start([engine.scriptPath, "--engine"])
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
  // `engine`, from a Podman or Docker button: set up there. Anything but those
  // two names is ignored rather than passed on — see run().
  function start (comeBack, engine) { run(isEngine(engine) ? ["--use", engine] : [], comeBack) }
  function stop () { run(["--stop"]) }
  function updateImage () { run(["--update"]) }
  // Settings' choice: set SearXNG up with that engine, or move it there — the
  // script asks before it removes anything from the other.
  function useEngine (engine) { if (isEngine(engine)) run(["--use", engine]) }

  function isEngine (name) { return name === "podman" || name === "docker" }

  // In a terminal: Docker may ask for sudo, and the first pull is worth watching.
  // The script and its arguments go in as arguments ("$0" "$@"), never spliced
  // into the shell text, so no value can become a command.
  function run (args, comeBack) {
    launching()
    state = "unknown"                          // whatever it was, it is changing
    Quickshell.execDetached([
      "xdg-terminal-exec", "bash", "-c",
      '"$0" "$@"; ' + Terminal.terminalEnding(comeBack),
      engine.scriptPath
    ].concat(args))
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

  Process {
    id: presentProcess

    command: [engine.scriptPath, "--present"]
    onExited: exitCode => {
      const done = engine.presentCallback
      engine.presentCallback = null
      if (done) done(exitCode === 0)
    }
  }

  Process {
    id: engineProcess

    function start (command) {
      running = false
      engineProcess.command = command
      running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        const name = String(text || "").trim()
        engine.engineName = engine.isEngine(name) ? name : ""
      }
    }
  }

  JsonProcess {
    id: statusProcess

    onParsed: payload => engine.state = payload.ok && payload.running ? "running" : "stopped"
    onUnreadable: engine.state = "unknown"
  }
}
