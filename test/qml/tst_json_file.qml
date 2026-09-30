import QtQuick
import QtTest
import "../../src/shared"

// Where each kind of file lives. "plugin" is the plugin's own folder — the one
// `omarchy plugin remove` deletes and an update fast-forwards — so what is kept
// there is forgotten by a reinstall and kept by an update.
Item {
  JsonFile { id: inPlugin; base: "plugin"; name: ".state/hints.json" }
  JsonFile { id: inData; name: "omaseek/sessions.json" }

  TestCase {
    name: "JsonFile"

    function test_a_plugin_file_lives_in_the_plugin_root() {
      const root = Qt.resolvedUrl("../..").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
      compare(inPlugin.root, root, "the checkout's root, not src/shared")
      compare(inPlugin.path, root + "/.state/hints.json")
      compare(inPlugin.dir, root + "/.state")
      verify(inPlugin.path.indexOf("file:") === -1, "a path, not a URL")
    }

    function test_data_files_stay_under_the_xdg_data_home() {
      verify(inData.path.endsWith("/omaseek/sessions.json"))
      verify(inData.path.indexOf("/.state/") === -1)
    }
  }
}
