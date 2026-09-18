import QtQuick
import qs.Commons
import qs.Ui

// One square of a numbered strip under the status line — a page of results, a
// saved conversation, or the one at the end that adds another. The strips
// differ in what a square stands for, not in how one looks.
Button {
  property real size: Math.round(Style.font.body * 2)

  width: size
  height: size
  bordered: true
  foreground: Color.menu.text
  accent: Color.menu.selectedText
  fontFamily: Style.font.menuFamily
  fontSize: Style.font.caption
}
