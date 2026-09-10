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
  property int dropdownIndex: -1             // which choice row has its list open
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)
  signal activated(string key, string action) // a toggle row was flipped
  signal closed()                            // esc, or the chord that opened the page
  signal editingFinished()                   // hand the keyboard back to Search.qml

  implicitHeight: layout.implicitHeight

  function open () {
    cursor = firstSetting()                  // never a heading, which has nothing to do
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

  // A section header is a label, not a setting, so the cursor steps over it
  // rather than landing on a row with nothing to do.
  function moveCursor (delta) {
    const step = delta < 0 ? -1 : 1
    let next = cursor
    for (let i = 0; i < rows.length; i++) {
      next += step
      if (next < 0 || next >= rows.length) return
      if (rows[next].type !== "section") { cursor = next; return }
    }
  }

  function firstSetting () {
    for (let i = 0; i < rows.length; i++) if (rows[i].type !== "section") return i
    return 0
  }

  // h/l on a choice row steps it; on a toggle row l is on and h is off, and
  // only a flip that changes something fires — starting a running instance
  // would open a terminal for nothing.
  function cycle (delta) {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "choice") changed(row.key, SettingsLib.cycle(row, delta))
    else if (row.type === "toggle" && !row.busy && (delta > 0) !== (row.value === true)) activated(row.key, row.action)
  }

  // Enter opens what can be opened: a typed row for editing, an action row
  // fires. A choice row has nothing to open — h and l step through its
  // options and each step is written straight through — so Enter used to
  // step it along too, which meant pressing Enter to settle on a value
  // changed it to the next one instead. It does nothing there now.
  function press () {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "text") beginEdit(cursor)
    else if (row.type === "toggle") { if (!row.busy) activated(row.key, row.action) }
    else if (row.control === "dropdown") dropdownIndex = cursor
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    // While a row is being typed into, the field owns the keyboard. Its Enter
    // reaches here too, and would reopen the editor the instant it closed.
    if (editingIndex !== -1 || dropdownIndex !== -1) return

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
      cursor = firstSetting()
    } else if (event.text === "G") {
      cursor = rows.length - 1
      if (rows[cursor] && rows[cursor].type === "section") moveCursor(-1)
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
        readonly property bool isSection: modelData.type === "section"
        readonly property bool hasCursor: index === page.cursor && !isSection
        readonly property bool isChoice: modelData.type === "choice"
        // A handful of options are chips beside the label. More than that is
        // a list behind a dropdown, so the row stays one line tall.
        readonly property bool isDropdown: isChoice && modelData.control === "dropdown"

        width: layout.width
        // A heading row is the rule, a breath, then the label: enough air
        // above and below the rule that it separates rather than underlines.
        height: isSection ? sectionLabel.implicitHeight + Style.spacing.lg + Style.spacing.md * 2
                          : body.implicitHeight + Style.spacing.md * 2
        radius: Style.cornerRadius
        color: hasCursor ? page.selectedBackground : "transparent"

        // A heading, not a setting: it names what the rows under it are for
        // and the cursor walks past it. The rule is what actually separates
        // the groups — the label alone left the page reading as one list with
        // a stray word in it.
        Rectangle {
          visible: settingRow.isSection && settingRow.index > 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: Style.spacing.md
          height: Math.max(1, Style.normalBorderWidth)
          color: Util.alpha(page.foreground, 0.18)
        }

        Text {
          id: sectionLabel

          visible: settingRow.isSection
          anchors.left: parent.left
          anchors.bottom: parent.bottom               // flush with the search field above
          anchors.bottomMargin: Style.spacing.xs
          textFormat: Text.PlainText
          text: settingRow.isSection ? String(settingRow.modelData.label).toUpperCase() : ""
          color: page.foreground
          opacity: 0.5
          font.family: page.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
        }

        // One chip, for the short choices. The raw
        // option goes back, not its string: the page sizes are numbers, and a
        // string would fail the write-side check and fall back to the default.
        Component {
          id: chip

          Button {
            required property var modelData

            text: String(modelData)
            bordered: true
            active: String(modelData) === String(settingRow.modelData.value)
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
                             sequenceField.visible ? sequenceField.implicitHeight : 0)

            Column {
              id: labels

              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(200)
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: settingRow.modelData.label
                color: page.foreground     // the row's background says where the cursor is
                font.family: page.fontFamily
                font.pixelSize: Style.font.subtitle
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                // A section row carries no hint, and an undefined binding is
                // a warning on every repaint even while the body is hidden.
                text: settingRow.modelData.hint || ""
                color: page.foreground
                opacity: 0.55
                font.family: page.fontFamily
                font.pixelSize: Style.font.caption
                // A dropdown row's hint has the most to say and the least
                // room, so it wraps; the others stay one line.
                wrapMode: settingRow.isDropdown ? Text.WordWrap : Text.NoWrap
                elide: settingRow.isDropdown ? Text.ElideNone : Text.ElideRight
              }
            }

            // A toggle row: the switch shows the state, flipping it acts. It
            // lights up with the row cursor so Enter visibly lands on it, and
            // goes busy while the probe is still out so a flip cannot race it.
            ToggleSwitch {
              id: engineSwitch

              visible: settingRow.modelData.type === "toggle"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: settingRow.modelData.value === true
              busy: settingRow.modelData.busy === true
              hasCursor: settingRow.hasCursor
              foreground: page.foreground
              accent: page.accent

              onToggled: {
                settingRow.owner.cursor = settingRow.index
                settingRow.owner.activated(settingRow.modelData.key, settingRow.modelData.action)
              }
            }

            Row {
              id: inlineChips

              visible: settingRow.isChoice && !settingRow.isDropdown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              Repeater {
                model: inlineChips.visible ? settingRow.modelData.options : []
                delegate: chip
              }
            }

            // The list behind a long choice. While it is open its own ListView
            // has the keys — the page steps aside the way it does for a text
            // row being typed into — and when it closes the page takes them
            // back, whichever way it was opened.
            Dropdown {
              id: picker

              readonly property bool asked: settingRow.index === page.dropdownIndex

              visible: settingRow.isDropdown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(200)
              showLabel: false
              options: picker.visible ? settingRow.modelData.options.map(String) : []
              value: String(settingRow.modelData.value)
              hasCursor: settingRow.hasCursor
              foreground: page.foreground
              accent: page.accent
              background: Color.menu.background
              popupBorder: Color.menu.border
              fontFamily: page.fontFamily

              onAskedChanged: if (asked) open()
              onPopupOpenChanged: {
                if (popupOpen) {
                  settingRow.owner.cursor = settingRow.index   // a click lands the cursor too
                } else {
                  settingRow.owner.dropdownIndex = -1
                  settingRow.owner.forceActiveFocus()
                }
              }

              // The raw option goes back, not its string — see the chip.
              //
              // Writing a setting recomputes the rows, and the Repeater rebuilds
              // every delegate — this one included, popup and all, while the
              // Dropdown is still inside its own select. So the page's state is
              // released first, so the rebuilt row does not reopen, and the
              // write itself waits a tick for the Dropdown to finish closing.
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

            // A typed setting: any sequence, not a menu of them. The field takes
            // the keyboard only while this row is being edited, so j/k keep
            // walking the page the rest of the time.
            TextField {
              id: sequenceField

              readonly property bool editing: settingRow.index === page.editingIndex

              visible: settingRow.modelData.type === "text"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(120)
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
                const cleaned = SettingsLib.normalizeRow(settingRow.modelData, sequenceField.text)
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
}
