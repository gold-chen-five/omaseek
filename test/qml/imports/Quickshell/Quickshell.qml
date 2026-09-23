pragma Singleton
import QtQml

QtObject {
  function env(name) { return "" }
  // What was run, so a test can see what reached wl-copy, or that nothing did.
  property var detached: []
  function execDetached(command) { detached = detached.concat([command]) }
}
