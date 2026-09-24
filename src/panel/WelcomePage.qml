import QtQuick
import qs.Commons
import qs.Ui
import "welcome.mjs" as WelcomeLib
import "../settings/hyprkey.mjs" as HyprKey

// The first open after install: what omaseek needs before it is useful —
// SearXNG running, and a key to open it — each set up from here, in a
// terminal, instead of a pointer into Settings. Drawn as SetupPrompt is. A
// step's button raises its signal and the panel runs what Settings runs;
// Change key opens a field for another key than SUPER + d. Start searching,
// or esc, is the end of the page.
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
  property bool editingKey: false              // the key field is open
  property string keyError: ""                 // why the typed key was refused
  property string preferred: ""                // the button to land on once the probe answers

  signal engineRequested()                     // Set up: bin/searxng-up in a terminal
  signal shortcutRequested()                   // Add, or Change to: bin/keybind --add in a terminal
  signal keyChosen(string key)                 // another key, normalized: check it
  signal finished()                            // Start searching, or esc

  // Land on the first thing left to do, or on Start when nothing is.
  function open () {
    selectedIndex = 0
    editingKey = false
    keyError = ""
    Qt.callLater(() => page.forceActiveFocus())
  }

  // A probe answering changes which buttons there are: after a key was chosen,
  // land on the one that applies it; else keep the cursor on a button.
  onButtonsChanged: {
    const at = preferred ? buttons.indexOf(preferred) : -1
    if (at !== -1) {
      selectedIndex = at
      preferred = ""
    } else if (selectedIndex >= buttons.length) selectedIndex = buttons.length - 1
  }

  function activate (action) {
    if (action === "start") page.engineRequested()
    else if (action === "add") page.shortcutRequested()
    else if (action === "rebind") editKey()
    else page.finished()
  }

  function move (delta) {
    selectedIndex = (selectedIndex + delta + buttons.length) % buttons.length
  }

  function editKey () {
    keyError = ""
    editingKey = true
  }

  // Enter in the key field: a key Hyprland can bind is checked by the panel,
  // anything else is refused where it was typed.
  function commitKey (raw) {
    const key = HyprKey.normalizeHyprKey(raw)
    if (!key) {
      keyError = HyprKey.OPEN_KEY_RULE
      return
    }
    editingKey = false
    keyError = ""
    preferred = "add"
    page.keyChosen(key)
    page.forceActiveFocus()
  }

  function cancelKey () {
    editingKey = false
    keyError = ""
    page.forceActiveFocus()
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
    readonly property bool selected: !page.editingKey && page.buttons[page.selectedIndex] === action

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
      onEntered: if (!page.editingKey) page.selectedIndex = Math.max(0, page.buttons.indexOf(button.action))
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

      Column {
        id: step

        required property var modelData
        required property int index
        readonly property bool keyStep: modelData.key === "shortcut"

        width: layout.width
        spacing: Style.spacing.sm

        Item {
          width: parent.width
          height: Math.max(stepText.implicitHeight, stepButtons.height)

          Text {
            id: mark
            textFormat: Text.PlainText
            anchors.top: parent.top
            text: step.modelData.done ? "✓" : String(step.index + 1)
            color: step.modelData.done ? page.accent : page.foreground
            opacity: step.modelData.done ? 1 : 0.6
            font.family: page.fontFamily
            font.pixelSize: Style.font.body
            width: Style.space(24)
          }

          Column {
            id: stepText
            anchors.left: mark.right
            anchors.right: stepButtons.left
            anchors.rightMargin: Style.spacing.lg
            spacing: Style.spacing.xs

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: step.modelData.title
              color: page.foreground
              font.family: page.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: step.modelData.detail
              color: page.foreground
              opacity: 0.55
              font.family: page.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Row {
            id: stepButtons
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.spacing.sm

            Repeater {
              model: step.modelData.buttons

              ActionButton {
                required property var modelData
                label: modelData.label
                action: modelData.action
              }
            }
          }
        }

        // Change key: the key typed here, as "super + s" or "SUPER + SHIFT + s".
        Row {
          visible: step.keyStep && page.editingKey
          x: Style.space(24)
          spacing: Style.spacing.md

          BorderSurface {
            width: Style.space(220)
            height: Style.space(34)
            color: "transparent"
            borderSpec: Border.flat(page.accent, Style.normalBorderWidth)
            radius: Style.cornerRadius

            TextInput {
              id: keyField
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              verticalAlignment: TextInput.AlignVCenter
              color: page.foreground
              selectionColor: page.selectedBackground
              font.family: page.fontFamily
              font.pixelSize: Style.font.body
              clip: true

              Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  page.commitKey(keyField.text)
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  page.cancelKey()
                  event.accepted = true
                }
              }
            }

            Connections {
              target: page
              function onEditingKeyChanged () {
                if (!page.editingKey || !step.keyStep) return
                keyField.text = page.shortcutStatus && page.shortcutStatus.wanted ? page.shortcutStatus.wanted
                  : page.shortcutStatus && page.shortcutStatus.key ? page.shortcutStatus.key : HyprKey.DEFAULT_OPEN_KEY
                keyField.forceActiveFocus()
                keyField.selectAll()
              }
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: page.keyError || "enter checks it · esc keeps the key"
            color: page.keyError ? Color.urgent : page.foreground
            opacity: page.keyError ? 0.95 : 0.55
            font.family: page.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: "Until then, the  just left of the bar's clock opens it. Tab switches between "
          + "searching the web and asking an agent; ctrl+k lists every key."
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
