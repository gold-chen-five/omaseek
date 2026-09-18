import Quickshell.Io

// A helper in bin/ run for one answer. Every one of them prints a single JSON
// object and exits 0 — a handled failure is a well-formed object too — so the
// only unreadable outcome is no output at all, or output nobody could parse.
//
// Restarting rather than reassigning: a Process already running keeps its old
// command until it is stopped, which is why start() does both.
Process {
  id: proc

  signal parsed(var payload)
  signal unreadable(string raw)

  function start (command) {
    running = false
    proc.command = command
    running = true
  }

  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: {
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
