import QtQuick
import QtTest

// A TestCase for the field, with the helpers every tst_field_* file uses: type a
// string, put the field in normal mode at a position, and start each test from
// an empty field in insert mode with the keyboard.
TestCase {
  property Item field: null

  when: windowShown

  function typeText(text) {
    for (let i = 0; i < text.length; i++) keyClick(text[i])
  }

  function setNormal(text, cursor) {
    field.text = text
    field.setMode("normal")
    field.cursorPosition = cursor
  }

  function init() {
    field.text = ""
    field.cursorPosition = 0
    field.setMode("insert")
    field.forceActiveFocus()
    tryCompare(field, "activeFocus", true)
  }
}
