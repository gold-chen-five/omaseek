import QtQuick
import qs.Commons
import qs.Ui
import "../lib/settings.mjs" as SettingsLib

// The settings page. One row per setting: what it is, what it does, and the
// choices laid out so the current one is visible without opening anything.
//
// Rows come from lib/settings.mjs so the page and the backend cannot disagree
// about which options exist. A FocusScope rather than a plain Column: the
// typed row hands the keyboard to a real text field and has to be able to take
// it back, which an Item that does not own focus cannot arrange.
FocusScope {
  id: page

  property var rows: []
  property int cursor: 0
  property int editingIndex: -1              // which text row is being typed into
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)
  signal editingFinished()                   // hand the keyboard back to Search.qml

  implicitHeight: layout.implicitHeight

  function beginEdit (index) {
    if (rows[index] && rows[index].type === "text") editingIndex = index
  }

  function endEdit () {
    if (editingIndex === -1) return          // idempotent: nothing to hand back
    editingIndex = -1
    editingFinished()
  }

  Column {
    id: layout

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.xs

    Repeater {
      model: page.rows

      delegate: Rectangle {
        id: settingRow

        required property int index
        required property var modelData

        // Bindings inside a Repeater delegate resolve the outer id, but
        // imperative code in the same delegate cannot — so the page is held in
        // a property and called through that.
        readonly property var owner: page
        readonly property bool hasCursor: index === page.cursor

        width: layout.width
        height: rowContent.implicitHeight + Style.spacing.md * 2
        radius: Style.cornerRadius
        color: hasCursor ? page.selectedBackground : "transparent"

        Item {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.rightMargin: Style.spacing.controlPaddingX

          Column {
            id: rowContent

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(200)
            spacing: Style.spacing.xxs

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: settingRow.modelData.label
              color: settingRow.hasCursor ? page.accent : page.foreground
              font.family: page.fontFamily
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: settingRow.modelData.hint
              color: page.foreground
              opacity: 0.55
              font.family: page.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          ButtonGroup {
            id: chips

            visible: settingRow.modelData.type !== "text"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: visible ? settingRow.modelData.options.map(option => String(option)) : []
            value: String(settingRow.modelData.value)
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            focusable: false                 // Search.qml drives the keyboard
            cursorIndex: -1

            onChanged: function (picked) {
              settingRow.owner.cursor = settingRow.index
              settingRow.owner.changed(settingRow.modelData.key, picked)
            }
          }

          // A typed setting: any sequence, not a menu of them. The field takes
          // the keyboard only while this row is being edited, so j/k keep
          // walking the page the rest of the time.
          TextField {
            id: sequenceField

            readonly property bool editing: settingRow.index === page.editingIndex

            visible: settingRow.modelData.type === "text"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(180)
            text: String(settingRow.modelData.value)
            placeholderText: settingRow.modelData.placeholder || ""
            readOnly: !editing
            // Declarative, so the field releases the keyboard the moment
            // editing ends. Left holding focus it would swallow the next Esc,
            // which the user means for the settings page.
            focus: editing
            foreground: page.foreground
            accent: page.accent
            font.family: page.fontFamily
            horizontalAlignment: TextInput.AlignHCenter

            function commit () {
              const cleaned = SettingsLib.normalizeSequence(sequenceField.text)
              if (cleaned !== null) settingRow.owner.changed(settingRow.modelData.key, cleaned)
              // Back to a binding, on the new value or the old one if refused.
              sequenceField.text = Qt.binding(function () { return String(settingRow.modelData.value) })
              settingRow.owner.endEdit()
            }

            onEditingChanged: if (sequenceField.editing) {
              sequenceField.forceActiveFocus()
              // Focus lands asynchronously and resets the selection, so the
              // select-all has to follow it — otherwise typing appends to the
              // existing sequence instead of replacing it.
              Qt.callLater(function () { sequenceField.selectAll() })
            }

            // A plain function, not an arrow: inside a Repeater delegate an
            // arrow handler is bound to lexical JS scope instead of the QML
            // scope chain, so ids like `page` and this object's own methods
            // are simply not resolvable from it.
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
  }
}
