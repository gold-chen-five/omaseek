import QtQuick
import qs.Commons
import qs.Ui
import "settings.mjs" as SettingsLib

// One row of the settings page, drawn from its row object (settings.mjs):
// a section heading, or a label and hint with the control its type asks for —
// a switch, a button, a row of chips, a dropdown, or a key to type. A row
// raises what the reader did through the page (`owner`), which it knows only
// as that.
Rectangle {
  id: settingRow

  required property int index
  required property var modelData

  // The settings page, handed in: its cursor, its open dropdown or field, the
  // widths it lines the controls up to, and the signals a row raises through it.
  property var owner: null
  readonly property bool isSection: modelData.type === "section"
  readonly property bool isInfo: modelData.type === "info"
  readonly property bool hasCursor: index === settingRow.owner.cursor && !isSection && !isInfo && !settingRow.owner.filterFocused
  readonly property bool isChoice: modelData.type === "choice"
  readonly property bool isAction: modelData.type === "action"
  readonly property bool isDropdown: isChoice && modelData.control === "dropdown"
  readonly property bool refused: index === settingRow.owner.refusedIndex

  height: isSection ? sectionLabel.implicitHeight + Style.spacing.lg + Style.spacing.md * 2
                    : body.implicitHeight + (isInfo ? Style.spacing.xs * 2 : Style.spacing.md * 2)
  radius: Style.cornerRadius
  color: hasCursor ? settingRow.owner.selectedBackground : "transparent"

  Rectangle {
    visible: settingRow.isSection && settingRow.index > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.spacing.md
    height: Math.max(1, Style.normalBorderWidth)
    color: Util.alpha(settingRow.owner.foreground, 0.18)
  }

  Text {
    id: sectionLabel

    visible: settingRow.isSection
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.spacing.xs
    textFormat: Text.PlainText
    text: settingRow.isSection ? String(settingRow.modelData.label).toUpperCase() : ""
    color: settingRow.owner.foreground
    opacity: 0.5
    font.family: settingRow.owner.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  // Emits the raw option, not its string: page sizes are numbers, and a string
  // fails the write-side check.
  Component {
    id: chip

    Button {
      required property var modelData

      text: String(modelData)
      bordered: true
      active: String(modelData) === String(settingRow.modelData.value)
      foreground: settingRow.owner.foreground
      accent: settingRow.owner.accent
      fontFamily: settingRow.owner.fontFamily
      fontSize: Style.font.bodySmall

      onClicked: {
        settingRow.owner.cursor = settingRow.index
        settingRow.owner.changed(settingRow.modelData.key, modelData)
      }
    }
  }

  Column {
    id: body

    visible: !settingRow.isSection
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Item {
      id: headLine

      width: parent.width
      height: Math.max(labels.implicitHeight, inlineChips.visible ? inlineChips.implicitHeight : 0,
                       picker.visible ? picker.implicitHeight : 0,
                       engineSwitch.visible ? engineSwitch.implicitHeight : 0,
                       actionButton.visible ? actionButton.implicitHeight : 0,
                       sequenceField.visible ? sequenceField.implicitHeight : 0)

      Column {
        id: labels

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - (settingRow.isInfo ? 0
                               : settingRow.isDropdown ? picker.width + Style.spacing.md
                               : Style.space(200))
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: settingRow.modelData.label
          color: settingRow.owner.foreground
          opacity: settingRow.isInfo ? 0.8 : 1
          font.family: settingRow.owner.fontFamily
          font.pixelSize: settingRow.isInfo ? Style.font.body : Style.font.subtitle
          elide: Text.ElideRight
        }

        // The hint, or why the key just typed was refused.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          // Section rows have no hint; an undefined binding warns on every repaint.
          text: settingRow.refused ? settingRow.owner.refusal : (settingRow.modelData.hint || "")
          color: settingRow.refused ? Color.urgent : settingRow.owner.foreground
          opacity: settingRow.refused ? 1 : 0.55
          font.family: settingRow.owner.fontFamily
          font.pixelSize: Style.font.caption
          // Every hint wraps onto as many lines as it needs. Cut short with an
          // ellipsis, a hint hid exactly what it was there to say — which key
          // a binding also works with, or which engine a test was about.
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
        }
      }

      ToggleSwitch {
        id: engineSwitch

        visible: settingRow.modelData.type === "toggle"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: settingRow.modelData.value === true
        busy: settingRow.modelData.busy === true
        hasCursor: settingRow.hasCursor
        foreground: settingRow.owner.foreground
        accent: settingRow.owner.accent

        onToggled: {
          settingRow.owner.cursor = settingRow.index
          settingRow.owner.activated(settingRow.modelData.key, settingRow.modelData.action)
        }
      }

      Button {
        id: actionButton

        visible: settingRow.isAction
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // Its own measure is the text's; the width is the column's.
        width: Math.max(implicitWidth, settingRow.owner.buttonColumn)
        onImplicitWidthChanged: if (visible) settingRow.owner.noteButton(settingRow.index, implicitWidth)
        onVisibleChanged: if (visible) settingRow.owner.noteButton(settingRow.index, implicitWidth)
        Component.onCompleted: if (visible) settingRow.owner.noteButton(settingRow.index, implicitWidth)
        text: settingRow.modelData.button || "Run"
        bordered: true
        hasCursor: settingRow.hasCursor
        foreground: settingRow.owner.foreground
        accent: settingRow.owner.accent
        fontFamily: settingRow.owner.fontFamily
        fontSize: Style.font.bodySmall

        onClicked: {
          settingRow.owner.cursor = settingRow.index
          if (!settingRow.modelData.busy)
            settingRow.owner.activated(settingRow.modelData.key, settingRow.modelData.action)
        }
      }

      Row {
        id: inlineChips

        visible: settingRow.isChoice && !settingRow.isDropdown
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        onWidthChanged: if (width > 0) settingRow.owner.noteChips(settingRow.index, width)   // hidden, it measures 0

        Repeater {
          model: inlineChips.visible ? settingRow.modelData.options : []
          delegate: chip
        }
      }

      // While open, the list has the keys; closing it hands them back to the settingRow.owner.
      // Ours rather than qs.Ui's: its list stays on screen (SettingsDropdown.qml).
      SettingsDropdown {
        id: picker

        readonly property bool asked: settingRow.index === settingRow.owner.dropdownIndex

        visible: settingRow.isDropdown
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: settingRow.owner.chipColumn > 0 ? settingRow.owner.chipColumn : Style.space(200)
        options: picker.visible ? settingRow.modelData.options.map(String) : []
        value: String(settingRow.modelData.value)
        hasCursor: settingRow.hasCursor
        foreground: settingRow.owner.foreground
        accent: settingRow.owner.accent
        background: Color.menu.background
        popupBorder: Color.menu.border
        fontFamily: settingRow.owner.fontFamily

        onAskedChanged: if (asked) open()
        onPopupOpenChanged: {
          if (popupOpen) {
            settingRow.owner.cursor = settingRow.index   // a click lands the cursor too
            settingRow.owner.dropdownIndex = settingRow.index
          } else {
            settingRow.owner.dropdownIndex = -1
            settingRow.owner.forceActiveFocus()
          }
        }

        // Raw option, as the chip sends. The write rebuilds every delegate, this one
        // included, mid-select: release the page's state first and write a tick later,
        // or the rebuilt row reopens.
        onChanged: function (chosen) {
          const options = settingRow.modelData.options
          let raw = chosen
          for (let i = 0; i < options.length; i++) if (String(options[i]) === chosen) raw = options[i]
          const owner = settingRow.owner
          const key = settingRow.modelData.key
          owner.dropdownIndex = -1
          owner.forceActiveFocus()
          Qt.callLater(function () { owner.changed(key, raw) })
        }
      }

      TextField {
        id: sequenceField

        readonly property bool editing: settingRow.index === settingRow.owner.editingIndex

        visible: settingRow.modelData.type === "text"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(120)
        text: String(settingRow.modelData.value)
        placeholderText: settingRow.modelData.placeholder || ""
        readOnly: !editing
        // Declarative, so focus drops the moment editing ends; held, it would swallow
        // the Esc meant for the settingRow.owner.
        focus: editing
        foreground: settingRow.owner.foreground
        accent: settingRow.owner.accent
        font.family: settingRow.owner.fontFamily
        horizontalAlignment: TextInput.AlignHCenter

        // A refused key keeps the old one and says why under the label.
        function commit () {
          const checked = SettingsLib.checkRow(settingRow.modelData, sequenceField.text, settingRow.owner.allRows)
          if (checked.error) settingRow.owner.refuse(settingRow.index, checked.error)
          else if (checked.value !== null) settingRow.owner.changed(settingRow.modelData.key, checked.value)
          // Back to a binding, on the new value or the old one if refused.
          sequenceField.text = Qt.binding(function () { return String(settingRow.modelData.value) })
          settingRow.owner.endEdit()
        }

        onEditingChanged: if (sequenceField.editing) {
          sequenceField.forceActiveFocus()
          // Focus lands asynchronously and resets the selection; select-all must follow.
          Qt.callLater(function () { sequenceField.selectAll() })
        }

        // A plain function, not an arrow: in a Repeater delegate an arrow binds lexical
        // JS scope, and `page` and this object's methods don't resolve.
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (!sequenceField.editing) return    // not this field's keyboard

          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            sequenceField.commit()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            sequenceField.text = Qt.binding(function () { return String(settingRow.modelData.value) })
            settingRow.owner.endEdit()
            event.accepted = true
          }
        }
      }
    }
  }
}
