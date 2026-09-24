import QtQuick
import "../shared/vim/keys.mjs" as KeysLib

// The panel's keys, caught in every mode before the field types anything:
// copy and paste, settings, the session keys, retry, submit, the mode and agent
// switches, and translating the bar. A key found here raises the field's
// signal for it, or — copy and paste — is done here and now.
Item {
  id: panelKeys

  property var field: null

  // In the order they are checked, so the first match wins. Ctrl+, was the
  // original settings binding and still works; Shift+Tab always switches,
  // because left alone it would move focus.
  function panelCommand (chord) {
    if (chord === "") return ""
    const clipboard = KeysLib.clipboardCommand(chord)
    if (clipboard !== "") return clipboard
    // Vim's insert-mode completion keys, while suggestions show — search mode,
    // where the session key ctrl+n has no ring to walk.
    if (field.completing && field.mode === "insert" && (chord === "C-n" || chord === "C-p")) return chord === "C-n" ? "completeNext" : "completePrevious"
    if (chord === field.chords.settings || chord === "C-,") return "settings"
    if (chord === field.chords.keysHelp) return "keysHelp"
    if (chord === field.chords.newSession) return "newSession"
    if (chord === field.chords.nextSession) return "nextSession"
    if (chord === field.chords.clearSessions) return "clearSessions"
    if (chord === field.chords.closeSession) return "closeSession"
    if (chord === field.chords.retryAnswer) return "retryAnswer"
    if (chord === field.chords.search) return "submit"
    if (chord === field.chords.switchMode) return "toggleMode"
    if (chord === field.chords.switchAgent) return "switchAgent"
    if (chord === field.chords.translateBarAnywhere) return "translateBar"
    return ""
  }

  function raisePanel (command) {
    switch (command) {
    case "completeNext":     field.completionStepped(1); break
    case "completePrevious": field.completionStepped(-1); break
    case "copy":          field.edits.copySelection(); break
    case "paste":         field.edits.pasteClipboard(); break
    case "settings":      field.requestedSettings(); break
    case "keysHelp":      field.insertKeys.clearEscapePending(); field.keysRequested(); break
    case "newSession":    field.newSessionRequested(); break
    case "nextSession":   field.nextSessionRequested(); break
    case "clearSessions": field.clearSessionsRequested(); break
    case "closeSession":  field.closeSessionRequested(); break
    case "retryAnswer":   field.retryRequested(); break
    // Both leave the field for good; a half-typed escape sequence goes with it.
    case "submit":        field.insertKeys.clearEscapePending(); field.submitted(); break
    case "toggleMode":    field.insertKeys.clearEscapePending(); field.tabbed(); break
    case "switchAgent":   field.agentSwitchRequested(); break
    // ctrl+t: gT without leaving insert mode — the words just typed, translated.
    case "translateBar":  field.insertKeys.clearEscapePending(); field.translateRequested(field.text); break
    }
  }
}
