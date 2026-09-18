import QtQuick
import qs.Commons
import qs.Ui
import "../shared/thinking.mjs" as Thinking
import "../shared/vim/keys.mjs" as KeysLib
import "../shared/vim/chord.js" as Chord

// The translation, split to the right of the results or the answer: what was
// asked about, dimmed, and what it says in the target language below. The
// keyboard stays with the pane beside it until ctrl+l moves it here. The
// translation itself is read with vim keys by the answer's view, which
// panel/ReadingArea puts in `body` — a feature does not import another — so
// the keys below are only what works before it has arrived: ctrl+x, ctrl+h and
// the way back to the field. Knows nothing of Translator: it is handed the
// words and raises what the reader wants done.
FocusScope {
  id: panel

  property string source: ""
  property string text: ""
  property string status: "idle"               // idle | translating | done | error
  property string errorMessage: ""
  property string targetLabel: ""
  property real startedAt: 0
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property var binds: null                     // the settings: where the rebindable commands sit
  readonly property var readerKeys: KeysLib.readerKeys("translation", binds)
  property var navigation: ({ pending: "", count: 0 })
  // Where the reader of a finished translation goes, filling what is left.
  readonly property alias body: bodySlot

  readonly property real squareSize: Math.round(Style.font.body * 2)
  readonly property int dotDiameter: Math.round(Style.font.body * 0.55)
  property int tick: 0

  signal closed()                              // × or ctrl+x
  signal copied(string text)                   // the copy button
  signal leftRequested()                       // ctrl+h, esc: back to the pane beside it
  signal insertRequested()                     // i, gi: the field, insert mode
  signal appendRequested()                     // a
  signal normalRequested()                     // gn: the field, normal mode
  signal settingsRequested()
  signal tabbed()
  signal agentSwitchRequested()

  onActiveFocusChanged: navigation = { pending: "", count: 0 }

  // Reached only while nothing is in `body` to take the keys: translating, or failed.
  Keys.onPressed: event => {
    const step = KeysLib.resolveCounted(readerKeys, navigation, Chord.of(event))
    navigation = step.state
    switch (step.command) {
    case "settings":     settingsRequested(); break
    case "toggleMode":   tabbed(); break
    case "switchAgent":  agentSwitchRequested(); break
    case "closeSession": closed(); break
    case "cancel":
    case "paneLeft":     leftRequested(); break
    case "insert":       insertRequested(); break
    case "append":       appendRequested(); break
    case "fieldNormal":  normalRequested(); break
    }
    event.accepted = true
  }

  Timer {
    interval: Thinking.CLOCK_MS
    running: panel.visible && panel.status === "translating"
    repeat: true
    onTriggered: panel.tick = panel.tick + 1
  }

  // The seam against the pane on the left.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(1, Style.normalBorderWidth)
    color: panel.activeFocus ? panel.accent : Util.alpha(panel.foreground, 0.18)
  }

  Item {
    id: header

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.spacing.md
    height: panel.squareSize

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: ("translation" + (panel.targetLabel ? " · " + panel.targetLabel : "")).toUpperCase()
      // Lit while it has the keyboard, so ctrl+x is seen to mean this.
      color: panel.activeFocus ? panel.accent : panel.foreground
      opacity: panel.activeFocus ? 1 : 0.5
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.5
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Button {
        visible: panel.status === "done" && panel.text !== ""
        height: panel.squareSize
        text: "copy"
        tooltipText: "copy the translation"
        bordered: true
        foreground: panel.foreground
        accent: panel.accent
        fontFamily: panel.fontFamily
        fontSize: Style.font.caption

        onClicked: panel.copied(panel.text)
      }

      Button {
        width: panel.squareSize
        height: panel.squareSize
        text: "×"
        tooltipText: "close (ctrl+x)"
        bordered: true
        foreground: panel.foreground
        accent: panel.accent
        fontFamily: panel.fontFamily
        fontSize: Style.font.caption

        onClicked: panel.closed()
      }
    }
  }

  Column {
    id: above

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.leftMargin: Style.spacing.md
    anchors.topMargin: Style.spacing.md
    spacing: Style.spacing.md

    // What was asked about, so a translation of a selection says of what.
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: panel.source
      color: panel.foreground
      opacity: 0.5
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      maximumLineCount: 6
      elide: Text.ElideRight
    }

    // Waiting: the answer's own breathing dot, and how long it has been.
    Row {
      visible: panel.status === "translating"
      spacing: Style.spacing.sm

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: panel.dotDiameter
        height: width
        radius: width / 2
        color: panel.foreground

        SequentialAnimation on opacity {
          running: panel.visible && panel.status === "translating"
          loops: Animation.Infinite
          NumberAnimation { to: 0.2; duration: Thinking.PULSE_MS / 2; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: Thinking.PULSE_MS / 2; easing.type: Easing.InOutSine }
        }
      }

      Text {
        textFormat: Text.PlainText
        // tick is read so the clock re-evaluates.
        text: panel.tick >= 0 ? "translating · " + Thinking.elapsedText(Date.now() - panel.startedAt) : ""
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Text {
      visible: panel.status === "error"
      width: parent.width
      textFormat: Text.PlainText
      text: panel.errorMessage
      color: Color.urgent
      font.family: panel.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }
  }

  Item {
    id: bodySlot

    visible: panel.status === "done"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: above.bottom
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.spacing.md
    anchors.topMargin: Style.spacing.md
  }
}
