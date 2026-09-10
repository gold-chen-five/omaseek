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
  signal activated(string key, string action) // an action row's button was pressed
  signal closed()                            // esc, or the chord that opened the page
  signal editingFinished()                   // hand the keyboard back to Search.qml

  implicitHeight: layout.implicitHeight

  function open () {
    cursor = 0
    Qt.callLater(() => page.forceActiveFocus())
  }

  function beginEdit (index) {
    if (rows[index] && rows[index].type === "text") editingIndex = index
  }

  function endEdit () {
    if (editingIndex === -1) return          // idempotent: nothing to hand back
    editingIndex = -1
    editingFinished()
  }

  function moveCursor (delta) {
    if (rows.length === 0) return
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta))
  }

  // h/l on a choice row; nothing on the others.
  function cycle (delta) {
    const row = rows[cursor]
    if (row && row.type === "choice") changed(row.key, SettingsLib.cycle(row, delta))
  }

  // Enter: a typed row opens for editing, an action row fires, and a choice
  // row just steps along.
  function press () {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "text") beginEdit(cursor)
    else if (row.type === "action") activated(row.key, row.action)
    else cycle(1)
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    // While a row is being typed into, the field owns the keyboard. Its Enter
    // reaches here too, and would reopen the editor the instant it closed.
    if (editingIndex !== -1) return

    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Escape
        || (ctrl && (event.key === Qt.Key_S || event.key === Qt.Key_Comma))) {
      closed()                               // the same chord that opened it, so it toggles
    } else if (event.key === Qt.Key_Down || event.text === "j") {
      moveCursor(1)
    } else if (event.key === Qt.Key_Up || event.text === "k") {
      moveCursor(-1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.text === "i") {
      press()
    } else if (event.key === Qt.Key_Right || event.text === "l") {
      cycle(1)
    } else if (event.key === Qt.Key_Left || event.text === "h") {
      cycle(-1)
    } else if (event.text === "g") {
      cursor = 0
    } else if (event.text === "G") {
      cursor = rows.length - 1
    }
    event.accepted = true
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
        readonly property bool isChoice: modelData.type === "choice"
        // A handful of chips sit beside the label; more than that would run
        // into it, so they take a line of their own underneath and wrap.
        readonly property bool stacked: isChoice && modelData.options.length > 4

        width: layout.width
        height: body.implicitHeight + Style.spacing.md * 2
        radius: Style.cornerRadius
        color: hasCursor ? page.selectedBackground : "transparent"

        // One chip, used by both the inline row and the stacked flow. The raw
        // option goes back, not its string: the page sizes are numbers, and a
        // string would fail the write-side check and fall back to the default.
        Component {
          id: chip

          Button {
            required property var modelData

            text: String(modelData)
            bordered: true
            selected: String(modelData) === String(settingRow.modelData.value)
            foreground: page.foreground
            accent: page.accent
            fontFamily: page.fontFamily
            fontSize: Style.font.bodySmall

            onClicked: {
              settingRow.owner.cursor = settingRow.index
              settingRow.owner.changed(settingRow.modelData.key, modelData)
            }
          }
        }

        Column {
          id: body

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
                             actionButton.visible ? actionButton.implicitHeight : 0,
                             sequenceField.visible ? sequenceField.implicitHeight : 0)

            Column {
              id: labels

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: settingRow.stacked ? parent.width : parent.width - Style.space(200)
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
                wrapMode: settingRow.stacked ? Text.WordWrap : Text.NoWrap
                elide: settingRow.stacked ? Text.ElideNone : Text.ElideRight
              }
            }

            // An action row has nothing to pick, only something to do. The
            // button lights up with the row cursor so Enter visibly lands on it.
            Button {
              id: actionButton

              visible: settingRow.modelData.type === "action"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: settingRow.modelData.actionLabel || ""
              bordered: true
              hasCursor: settingRow.hasCursor
              foreground: page.foreground
              accent: page.accent
              fontFamily: page.fontFamily
              fontSize: Style.font.body

              onClicked: {
                settingRow.owner.cursor = settingRow.index
                settingRow.owner.activated(settingRow.modelData.key, settingRow.modelData.action)
              }
            }

            Row {
              id: inlineChips

              visible: settingRow.isChoice && !settingRow.stacked
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Repeater {
                model: inlineChips.visible ? settingRow.modelData.options : []
                delegate: chip
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

          Flow {
            id: stackedChips

            visible: settingRow.stacked
            width: parent.width
            spacing: Style.spacing.sm

            Repeater {
              model: stackedChips.visible ? settingRow.modelData.options : []
              delegate: chip
            }
          }
        }
      }
    }
  }
}
