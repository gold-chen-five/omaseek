import QtQuick
import qs.Commons
import qs.Ui
import "welcome.mjs" as WelcomeLib

// The first open after install: what omaseek needs before it is useful —
// SearXNG running, and a key to open it — each set up from here, in a
// terminal, instead of a pointer into Settings. Drawn as SetupPrompt is. A
// step's button raises its signal and the panel runs what Settings runs;
// Start searching, or esc, is the end of the page.
Item {
  id: page

  property string engineState: "unknown"       // Engine.state
  property var shortcutStatus: null            // Shortcut.status: bin/keybind --status
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  readonly property var steps: WelcomeLib.welcomeSteps(engineState, shortcutStatus)
  readonly property var buttons: WelcomeLib.welcomeButtons(steps)
  property int selectedIndex: 0                // into `buttons`

  signal engineRequested()                     // Set up: bin/searxng-up in a terminal
  signal shortcutRequested()                   // Add: bin/keybind --add in a terminal
  signal finished()                            // Start searching, or esc

  // Land on the first thing left to do, or on Start when nothing is.
  function open () {
    selectedIndex = 0
    Qt.callLater(() => page.forceActiveFocus())
  }

  // A probe answering changes which buttons there are: keep the cursor on one.
  onButtonsChanged: if (selectedIndex >= buttons.length) selectedIndex = buttons.length - 1

  function activate (action) {
    if (action === "start") page.engineRequested()
    else if (action === "add") page.shortcutRequested()
    else page.finished()
  }

  function move (delta) {
    selectedIndex = (selectedIndex + delta + buttons.length) % buttons.length
  }

  implicitHeight: layout.implicitHeight

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape) page.finished()
    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right || event.key === Qt.Key_Tab
             || event.text === "j" || event.text === "l") page.move(1)
    else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left || event.key === Qt.Key_Backtab
             || event.text === "k" || event.text === "h") page.move(-1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
      page.activate(page.buttons[page.selectedIndex])
    event.accepted = true
  }

  component ActionButton: BorderSurface {
    id: button

    property string label: ""
    property string action: ""
    readonly property bool selected: page.buttons[page.selectedIndex] === action

    width: Math.max(Style.space(88), caption.implicitWidth + Style.space(24))
    height: Style.space(34)
    color: selected ? page.selectedBackground : "transparent"
    borderSpec: Border.flat(selected ? page.accent : Util.alpha(page.foreground, 0.38), Style.normalBorderWidth)
    radius: Style.cornerRadius

    Text {
      id: caption
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: button.label
      color: button.selected ? page.accent : page.foreground
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: page.selectedIndex = Math.max(0, page.buttons.indexOf(button.action))
      onClicked: page.activate(button.action)
    }
  }

  Column {
    id: layout

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.lg

    Column {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Welcome to omaseek"
        color: page.accent
        font.family: page.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: "Web search and AI, driven with vim keys. Two things to set up first. "
            + "Each opens a terminal you can watch — the panel steps aside while it needs the "
            + "keyboard, and comes back here when you press a key to close it."
        color: page.foreground
        opacity: 0.75
        font.family: page.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        lineHeight: 1.3
      }
    }

    Repeater {
      model: page.steps

      Item {
        required property var modelData
        required property int index

        width: layout.width
        height: Math.max(stepText.implicitHeight, stepButton.height)

        Text {
          id: mark
          textFormat: Text.PlainText
          anchors.top: parent.top
          text: modelData.done ? "✓" : String(index + 1)
          color: modelData.done ? page.accent : page.foreground
          opacity: modelData.done ? 1 : 0.6
          font.family: page.fontFamily
          font.pixelSize: Style.font.body
          width: Style.space(24)
        }

        Column {
          id: stepText
          anchors.left: mark.right
          anchors.right: stepButton.visible ? stepButton.left : parent.right
          anchors.rightMargin: Style.spacing.lg
          spacing: Style.spacing.xs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.title
            color: page.foreground
            font.family: page.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: modelData.detail
            color: page.foreground
            opacity: 0.55
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        ActionButton {
          id: stepButton
          anchors.right: parent.right
          anchors.top: parent.top
          visible: modelData.action !== ""
          label: modelData.button
          action: modelData.action
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Until then, the  in the middle of the bar opens it. Tab switches between searching "
          + "the web and asking an agent; ctrl+k lists every key."
      color: page.foreground
      opacity: 0.55
      font.family: page.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    ActionButton {
      anchors.right: parent.right
      label: "Start searching"
      action: "finish"
    }
  }
}
