import QtQuick
import qs.Commons
import qs.Ui

// Shown when the SearXNG instance is not running.
//
// It appears on its own rather than behind a key: an engine that is down is
// not a search result the user can read past, and the plugin cannot start a
// service on its own — Omarchy runs no install hooks — so the one useful thing
// the panel can do is explain what it needs and ask.
//
// The explanation is not decoration. Docker, a download and a password prompt
// are all consequences of saying yes, and nobody should meet them for the
// first time after agreeing.
Item {
  id: prompt

  property string reason: ""                 // what the backend actually reported
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  // Which button the keyboard is on. Confirm is the landing point, as in
  // the shell's own ConfirmDialog: the person summoned a search bar and
  // was told the engine is off, so Enter should be the way forward.
  property int selectedIndex: 1
  property color selectedBackground: Color.menu.selectedBackground

  signal confirmed()
  signal cancelled()

  function activate (index) {
    if (index === 0) prompt.cancelled()
    else prompt.confirmed()
  }

  function open () {
    selectedIndex = 1                          // land on "Start it" every time
    Qt.callLater(() => prompt.forceActiveFocus())
  }

  implicitHeight: layout.implicitHeight

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape) {
      prompt.cancelled()
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
               || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
               || event.text === "h" || event.text === "l") {
      prompt.selectedIndex = prompt.selectedIndex === 0 ? 1 : 0
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
               || event.key === Qt.Key_Space) {
      prompt.activate(prompt.selectedIndex)
    }
    event.accepted = true
  }

  Column {
    id: layout

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "SearXNG isn’t running"
      color: prompt.accent
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.heading
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "This panel searches through SearXNG — a metasearch engine that "
          + "runs on your own machine, in Docker. It queries the upstream "
          + "engines for you, so searches go to a service you control."
      color: prompt.foreground
      opacity: 0.75
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
      lineHeight: 1.3
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Start it now? A terminal opens and runs bin/searxng-up. The first "
          + "run downloads about 200 MB and asks for your password."
      color: prompt.foreground
      opacity: 0.75
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
      lineHeight: 1.3
    }

    Text {
      width: parent.width
      visible: prompt.reason !== ""
      textFormat: Text.PlainText
      text: prompt.reason
      color: prompt.foreground
      opacity: 0.45
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    // Two buttons drawn the way the shell's ConfirmDialog draws its own, so
    // saying yes here looks like saying yes to an update in the menu.
    Row {
      anchors.right: parent.right
      spacing: Style.space(10)

      Repeater {
        model: ["Not now", "Start it"]

        BorderSurface {
          required property int index
          required property string modelData

          readonly property bool selected: prompt.selectedIndex === index

          width: Style.space(88)
          height: Style.space(34)
          color: selected ? prompt.selectedBackground : "transparent"
          borderSpec: Border.flat(selected ? prompt.accent : Util.alpha(prompt.foreground, 0.38),
                                  Style.normalBorderWidth)
          radius: 0

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData
            color: selected ? prompt.accent : prompt.foreground
            font.family: prompt.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: prompt.selectedIndex = index
            onClicked: prompt.activate(index)
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "h l  choose        enter  confirm        esc  not now"
      color: prompt.foreground
      opacity: 0.45
      font.family: prompt.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
