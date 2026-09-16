import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../lib/popup.mjs" as PopupLib

// The settings page's dropdown: Omarchy's qs.Ui Dropdown — its look, its
// tokens, its keys — with one difference that could not be reached from
// outside it. Omarchy's list always opens below the trigger at up to eight
// rows and is not kept inside the window, so a dropdown low on the page (Model,
// on a 1536×864 logical screen) ran off the bottom of the screen. Here the list
// opens where it fits (lib/popup.mjs) and scrolls to the chosen option.
// Theirs lives under /usr/share, read-only; keep this close to it when it moves.
Item {
  id: root

  property string value: ""
  property var options: []

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property int visibleRows: 8

  property bool hasCursor: false

  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }

  signal changed(string value)

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }
  function currentLabel() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    }
    return value
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: rowHeight

  BorderSurface {
    id: trigger
    anchors.fill: parent
    radius: Style.cornerRadius

    readonly property bool _focused: trigger.activeFocus
    readonly property bool _hot: triggerHover.hovered || root.hasCursor
    readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

    color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
    borderSpec: _borderSpec

    activeFocusOnTab: true

    HoverHandler { id: triggerHover }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        popup.opened ? popup.close() : popup.open()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape && popup.opened) {
        popup.close(); event.accepted = true
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
      anchors.rightMargin: trigger.borderRight + Style.spacing.md
      text: root.currentLabel()
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: chevron
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
      text: "󰅀"
      color: Qt.darker(root.foreground, 1.2)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        trigger.forceActiveFocus()
        popup.opened ? popup.close() : popup.open()
      }
    }

    Popup {
      id: popup

      readonly property real gap: Style.spacing.xxs
      readonly property real chrome: topPadding + bottomPadding
      // Every option at full height, up to visibleRows of them.
      readonly property real natural: {
        const rows = Math.min(root.options.length, root.visibleRows)
        return rows * root.popupRowHeight + Math.max(0, rows - 1) * Style.spacing.labelGap + chrome
      }

      x: 0
      y: trigger.height + gap
      width: trigger.width
      height: natural
      padding: Style.spacing.hairline
      leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
      rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
      topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
      bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
      focus: true

      // Placed as it opens: the trigger may have scrolled since the last time,
      // and the window is the screen, so it is the bound.
      onAboutToShow: {
        const windowHeight = trigger.Window.height
        if (!(windowHeight > 0)) return               // no window to measure: Omarchy's placement
        const place = PopupLib.placePopup({
          triggerTop: trigger.mapToItem(null, 0, 0).y,
          triggerHeight: trigger.height,
          windowHeight: windowHeight,
          natural: natural,
          gap: gap,
          margin: Style.spacing.md,
          minimum: root.popupRowHeight + chrome
        })
        popup.y = place.y
        popup.height = place.height
      }

      background: BorderSurface {
        color: root.background
        borderSpec: root.popupBorderSpec
        radius: Style.cornerRadius
      }

      onOpened: {
        optionList.currentIndex = Math.max(0, optionList.indexOfValue(root.value))
        // A long list may start with the chosen option out of sight.
        optionList.positionViewAtIndex(optionList.currentIndex, ListView.Contain)
        optionList.forceActiveFocus()
      }

      contentItem: ListView {
        id: optionList
        spacing: Style.spacing.labelGap

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
          else if (event.key === Qt.Key_Down || event.text === "j") {
            optionList.currentIndex = Math.min(root.options.length - 1, optionList.currentIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            optionList.selectCurrent(); event.accepted = true
          }
        }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.options
        currentIndex: -1
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

        function indexOfValue(v) {
          for (var i = 0; i < root.options.length; i++)
            if (root.optionValue(root.options[i]) === v) return i
          return -1
        }

        function selectCurrent() {
          if (currentIndex < 0 || currentIndex >= root.options.length) return
          var v = root.optionValue(root.options[currentIndex])
          root.value = v
          root.changed(v)
          popup.close()
        }

        delegate: Rectangle {
          required property var modelData
          required property int index
          width: optionList.width
          height: root.popupRowHeight
          color: index === optionList.currentIndex
            ? Style.hoverFillFor(root.foreground, root.accent)
            : "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            text: root.optionLabel(modelData)
            color: index === optionList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: optionList.currentIndex = parent.index
            onClicked: optionList.selectCurrent()
          }
        }
      }
    }
  }
}
