import QtQuick
import "settings.mjs" as SettingsLib
import "../shared/vim/keymap.mjs" as KeymapLib
import "../shared"

// ~/.config/omaseek/config.json. Writes only the keys the settings page owns;
// everything else (searxng_url above all) passes through untouched.
Item {
  id: store

  property string source: ""                   // kept so a write preserves unknown keys
  property var keymap: KeymapLib.readKeymap("")
  property var settings: SettingsLib.readSettings("")

  // Re-read on every summon on top of the watch, so an edit lands whether the
  // file was changed, deleted, or created after the shell started.
  function reload () { file.reload() }

  // A change is written straight through — there is no save button to forget.
  function change (key, value) {
    const text = SettingsLib.writeSettings(SettingsLib.changeSetting(settings, key, value), source)
    apply(text)                                // reflect it now; the watcher confirms
    file.write(text)
  }

  function apply (text) {
    source = text
    keymap = KeymapLib.readKeymap(text)
    settings = SettingsLib.readSettings(text)
  }

  JsonFile {
    id: file

    base: "config"
    name: "omaseek/config.json"
    watch: true
    onLoaded: text => store.apply(text)        // absent or unreadable is "", which means defaults
  }
}
