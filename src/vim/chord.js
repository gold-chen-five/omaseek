// Qt key event -> chord string for vim/keys.mjs. A .js file so it can see Qt;
// keys.mjs also runs under node. A bare modifier is "", which keeps a pending
// sequence.

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
    // Shift is only ever part of a ctrl chord: on its own it is how a capital
    // is typed, and the letter already says so.
    const prefix = (event.modifiers & Qt.ShiftModifier) !== 0 ? "C-S-" : "C-"
    // Ctrl+letter arrives with a control character as its text, so the chord
    // is spelled from the key itself. Qt.Key_A is the codepoint of "A".
    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
      return prefix + String.fromCharCode(event.key).toLowerCase()
    }
    if (event.key === Qt.Key_Comma) return prefix + ","
    const withCtrl = names()[event.key]
    if (withCtrl) return prefix + withCtrl
    return ""
  }

  const name = names()[event.key]
  if (name) return name
  return event.text || ""
}

// The keys a find prompt reads as commands rather than as pattern text.
// Everything else it takes from event.text, so a chord's spelling (which folds
// shift and names the arrows) never reaches the pattern.
function findKey (event) {
  if (event.key === Qt.Key_Escape) return "Escape"
  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return "Return"
  if (event.key === Qt.Key_Backspace) return "Backspace"
  return ""
}
