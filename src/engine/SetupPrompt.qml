import QtQuick
import qs.Commons
import qs.Ui

// Shown when the SearXNG instance is down. It says what starting it involves
// (Podman or Docker, a download, maybe sudo) before asking.
Item {
  id: prompt

  property string reason: ""                 // what the backend actually reported
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  // Confirm is the landing button, as in the shell's ConfirmDialog.
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
          + "runs on your own machine, in Podman or Docker. It queries the upstream "
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

    // Drawn like the shell's ConfirmDialog.
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
          radius: Style.cornerRadius

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
