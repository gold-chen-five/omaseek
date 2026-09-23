import Quickshell.Io

// A helper in bin/ run for one answer. Every one of them prints a single JSON
// object and exits 0 — a handled failure is a well-formed object too — so the
// only unreadable outcome is no output at all, or output nobody could parse.
//
// Restarting rather than reassigning: a Process already running keeps its old
// command until it is stopped, which is why start() does both.
//
// A stopped run still finishes its stream — later, as an empty one, after the
// caller has moved on — which read as an unreadable answer: closing the panel
// mid-search left "Search returned nothing" waiting for the next open. Measured:
// each stopped run finishes exactly once, and before the run that replaced it,
// so `stale` counts them out.
Process {
  id: proc

  property int stale: 0

  signal parsed(var payload)
  signal unreadable(string raw)

  function start (command) {
    stop()
    proc.command = command
    running = true
  }

  // Nobody is waiting for this run any more: its answer, if any, is dropped.
  function stop () {
    if (!running) return
    stale = stale + 1
    running = false
  }

  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: {
      if (proc.stale > 0) {
        proc.stale = proc.stale - 1
        return
      }
      const raw = String(text ?? "").trim()
      if (raw === "") {
        proc.unreadable("")
        return
      }
      try {
        proc.parsed(JSON.parse(raw))
      } catch (error) {
        proc.unreadable(raw)
      }
    }
  }
}
