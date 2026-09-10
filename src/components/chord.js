// A Qt key event as the chord string lib/keys.mjs matches on.
//
// This is the one place Qt's key enums are named, and it is a .js rather
// than part of lib/keys.mjs because that module also has to load in node,
// under test, where Qt does not exist. Nothing here decides anything: it
// spells the keypress, the table says what it means.
//
// A modifier held on its own is the empty string, which leaves a pending
// sequence untouched — reaching for shift in the middle of one should not
// cancel it.

var named = null

function names () {
  if (named) return named
  named = {}
  named[Qt.Key_Escape] = "Escape"
  named[Qt.Key_Tab] = "Tab"
  named[Qt.Key_Backtab] = "Backtab"
  named[Qt.Key_Return] = "Return"
  named[Qt.Key_Enter] = "Return"          // the keypad's; the same intent
  named[Qt.Key_Up] = "Up"
  named[Qt.Key_Down] = "Down"
  named[Qt.Key_Left] = "Left"
  named[Qt.Key_Right] = "Right"
  named[Qt.Key_Home] = "Home"
  named[Qt.Key_End] = "End"
  return named
}

function isModifier (key) {
  return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
      || key === Qt.Key_Meta || key === Qt.Key_AltGr || key === Qt.Key_CapsLock
}

function of (event) {
  if (isModifier(event.key)) return ""

  if ((event.modifiers & Qt.ControlModifier) !== 0) {
    // Ctrl+letter arrives with a control character as its text, so the chord
    // is spelled from the key itself. Qt.Key_A is the codepoint of "A".
    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
      return "C-" + String.fromCharCode(event.key).toLowerCase()
    }
    if (event.key === Qt.Key_Comma) return "C-,"
    const withCtrl = names()[event.key]
    if (withCtrl) return "C-" + withCtrl
    return ""
  }

  const name = names()[event.key]
  if (name) return name
  return event.text || ""
}
