import QtQuick
import qs.Commons
import qs.Ui
import "../shared/states.mjs" as States
import "../shared/pixels.mjs" as Pixels
import "../field"

// The field in its frame, and the buttons beside it: translate, then search —
// or, in AI mode, chat and new session. The field's own signals are the panel's
// to connect (Search.qml reaches it as `field`); the buttons raise theirs here.
Item {
  id: bar

  property string panelMode: States.PANEL.SEARCH
  property var ai: null                        // its status, retry and agent name, for the buttons
  property var keymap: ({ sequences: [], timeoutMs: 0 })
  property var chords: ({})
  property var normalChords: ({})
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property real outputScale: 1                 // the monitor's, for whole-pixel frames

  readonly property alias field: input
  readonly property bool asking: panelMode === States.PANEL.AI
  readonly property bool thinking: asking && ai !== null && ai.status === "thinking"
  readonly property bool canRetry: ai !== null && ai.canRetry && input.text.trim() === ""

  signal translateClicked()
  signal submitClicked()                       // search, or chat: what Enter does
  signal stopClicked()
  signal retryClicked()
  signal newSessionClicked()

  height: fieldFrame.height

  // The field's frame, drawn here rather than by the field: the field scrolls
  // inside it, and a frame it drew itself would scroll too. One line tall at
  // rest — the single-line field's height — and a row taller for each line
  // added with Ctrl+J or o/O, up to six.
  BorderSurface {
    id: fieldFrame

    readonly property real insetTop: Border.top(input.borderSpec) + input.verticalPadding
    readonly property real insetBottom: Border.bottom(input.borderSpec) + input.verticalPadding
    // Whole device pixels, or at a fractional scale the bottom border can
    // straddle two rows and draw heavier than the top (pixels.mjs).
    readonly property real oneLineHeight: Pixels.snapToDevice(input.lineHeight + insetTop + insetBottom, bar.outputScale)

    width: parent.width - actions.width - Style.spacing.sm
    height: Pixels.snapToDevice(Math.min(input.lineCount, 6) * input.lineHeight + insetTop + insetBottom, bar.outputScale)
    radius: Style.cornerRadius
    color: Style.controlFill(input.activeFocus, input.hovered, bar.foreground, bar.accent)
    borderSpec: input.borderSpec

    Flickable {
      id: fieldScroll

      anchors.fill: parent
      anchors.leftMargin: Border.left(input.borderSpec) + input.horizontalPadding
      anchors.rightMargin: Border.right(input.borderSpec) + input.horizontalPadding
      anchors.topMargin: fieldFrame.insetTop
      anchors.bottomMargin: fieldFrame.insetBottom
      clip: true
      interactive: false                       // it follows the cursor; nothing drags it
      contentWidth: input.width
      contentHeight: input.height

      VimTextField {
        id: input

        width: Math.max(fieldScroll.width, implicitWidth)
        height: Math.max(fieldScroll.height, implicitHeight)
        multiline: bar.asking
        stoppable: bar.thinking
        foreground: bar.foreground
        accent: bar.accent
        font.family: bar.fontFamily
        font.pixelSize: Style.font.body
        verticalPadding: Style.spacing.md
        placeholderText: bar.asking ? "Ask " + (bar.ai ? bar.ai.agentName : "the agent") + "…" : "Search the web…"
        escapeSequences: bar.keymap.sequences
        escapeTimeout: bar.keymap.timeoutMs
        chords: bar.chords
        normalChords: bar.normalChords

        // The frame scrolls to keep the cursor in view as it passes an edge.
        onCursorRectangleChanged: {
          const r = cursorRectangle
          if (r.x < fieldScroll.contentX) fieldScroll.contentX = r.x
          else if (r.x + r.width > fieldScroll.contentX + fieldScroll.width) fieldScroll.contentX = r.x + r.width - fieldScroll.width
          if (r.y < fieldScroll.contentY) fieldScroll.contentY = r.y
          else if (r.y + r.height > fieldScroll.contentY + fieldScroll.height) fieldScroll.contentY = r.y + r.height - fieldScroll.height
        }
      }
    }
  }

  // Reserves the wider arrangement, so the field keeps its width across modes.
  Row {
    id: actions

    anchors.right: parent.right
    anchors.top: parent.top                    // the field grows down; the buttons stay a line
    height: fieldFrame.oneLineHeight
    spacing: Style.spacing.sm

    // gT with a mouse: whatever is in the bar, into the panel beside the
    // results or the answer.
    Button {
      height: actions.height
      text: "translate"
      tooltipText: "translate the bar (gT, ctrl+t)"
      active: true
      foreground: bar.foreground
      accent: bar.accent
      fontFamily: bar.fontFamily
      fontSize: Style.font.body

      onClicked: bar.translateClicked()
    }

    Item {
      height: actions.height
      width: Math.max(searchButton.implicitWidth, askActions.implicitWidth)

      Button {
        id: searchButton

        visible: !bar.asking
        anchors.fill: parent
        text: "search"
        active: true
        foreground: bar.foreground
        accent: bar.accent
        fontFamily: bar.fontFamily
        fontSize: Style.font.body

        onClicked: bar.submitClicked()
      }

      Row {
        id: askActions

        visible: bar.asking
        anchors.right: parent.right
        height: parent.height
        spacing: Style.spacing.sm

        // While a reply is being written the button stops it, and after a
        // failure or a stop it asks again — the keys, with a mouse.
        Button {
          height: askActions.height
          text: bar.thinking ? "stop" : bar.canRetry ? "retry" : "chat"
          active: true
          foreground: bar.foreground
          accent: bar.accent
          fontFamily: bar.fontFamily
          fontSize: Style.font.body

          onClicked: {
            if (bar.thinking) bar.stopClicked()
            else if (bar.canRetry) bar.retryClicked()
            else bar.submitClicked()
          }
        }

        Button {
          height: askActions.height
          text: "new session"
          active: true
          foreground: bar.foreground
          accent: bar.accent
          fontFamily: bar.fontFamily
          fontSize: Style.font.body

          onClicked: bar.newSessionClicked()
        }
      }
    }
  }
}
