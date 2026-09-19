import QtQuick
import "settings.mjs" as SettingsLib

// What the settings page's switches and buttons do, and what changing a value
// sets off. The page raises intent — this key, this action — and knows nothing
// of the instance, the config file or the Hyprland bindings; this does.
Item {
  id: actions

  property var config: null
  property var engine: null
  property var shortcut: null

  // A value changed on the page. The engine reports describe the engines and
  // language as they were, so a new language clears them.
  function change (key, value) {
    config.change(key, value)
    if (key === "searxngLanguage") forgetReports()
  }

  // A switch flipped or a button pressed.
  function run (key, action) {
    if (key === "stream") {
      config.change("stream", action === "on")
      return
    }
    if (key === "engineUpdate" && action === "update") {
      engine.updateImage()
      return
    }
    if (key === "engineTest" && action === "test") {
      engine.runTest()
      return
    }
    if (key === "shortcut" && action === "add") {
      shortcut.add()
      return
    }
    if (key === "engineSpeed" && action === "time") {
      engine.timeSearch()
      return
    }
    if (key.indexOf("searxngEngine:") === 0) {
      const name = key.slice("searxngEngine:".length)
      config.change("searxngEngines", SettingsLib.toggleEngine(config.settings, name, action === "on"))
      forgetReports()
      return
    }
    if (key !== "engine") return
    if (action === "stop") engine.stop()
    else engine.start()
  }

  function forgetReports () {
    engine.test = null
    engine.speed = null
  }
}
