import QtQuick
import qs.Commons
import qs.Ui
import "../lib/settings.mjs" as SettingsLib
import "chord.js" as Chord

// One row per setting; the rows come from lib/settings.mjs. A FocusScope because
// a typed row lends the keyboard to a text field and has to take it back.
FocusScope {
  id: page

  property var rows: []
  property int cursor: 0
  property int editingIndex: -1              // which text row is being typed into
  property int dropdownIndex: -1             // which choice row has its list open
  property int refusedIndex: -1              // a key just refused, and why, until the cursor moves
  property string refusal: ""
  property string settingsChord: "C-s"       // the key that opened the page closes it

  // The widest row of chips on the page, measured as laid out. A dropdown takes
  // this width, so it lines up with the chips under it edge for edge.
  property var chipWidths: ({})
  readonly property real chipColumn: {
    let widest = 0
    for (const key in chipWidths) widest = Math.max(widest, chipWidths[key])
    return widest
  }
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color selectedBackground: Color.menu.selectedBackground
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)
  signal activated(string key, string action) // a toggle row was flipped
  signal closed()                            // /, esc, or the chord that opened the page
  signal editingFinished()                   // hand the keyboard back to Search.qml

  implicitHeight: layout.implicitHeight

  onCursorChanged: {
    refusedIndex = -1
    Qt.callLater(ensureCursorVisible)
  }
  onRowsChanged: Qt.callLater(ensureCursorVisible)

  function ensureCursorVisible () {
    const row = rowRepeater.itemAt(cursor)
    if (!row) return
    const top = row.y
    const bottom = top + row.height
    if (top < scroll.contentY) scroll.contentY = top
    else if (bottom > scroll.contentY + scroll.height) scroll.contentY = bottom - scroll.height
    scroll.contentY = Math.max(0, Math.min(scroll.contentY, Math.max(0, scroll.contentHeight - scroll.height)))
  }

  function open () {
    cursor = firstSetting()
    refusedIndex = -1
    scroll.contentY = 0
    Qt.callLater(() => page.forceActiveFocus())
  }

  function beginEdit (index) {
    if (rows[index] && rows[index].type === "text") {
      refusedIndex = -1
      editingIndex = index
    }
  }

  function endEdit () {
    if (editingIndex === -1) return          // idempotent: nothing to hand back
    editingIndex = -1
    editingFinished()
  }

  function refuse (index, reason) {
    refusal = reason
    refusedIndex = index
  }

  function noteChips (index, width) {
    const next = {}
    for (const key in chipWidths) next[key] = chipWidths[key]
    next[index] = width
    chipWidths = next
  }

  // Section headings and the fixed-key reference are read, not changed.
  function selectable (row) {
    return !!row && row.type !== "section" && row.type !== "info"
  }

  function moveCursor (delta) {
    const step = delta < 0 ? -1 : 1
    let next = cursor
    for (let i = 0; i < rows.length; i++) {
      next += step
      if (next < 0 || next >= rows.length) return
      if (selectable(rows[next])) { cursor = next; return }
    }
  }

  function firstSetting () {
    for (let i = 0; i < rows.length; i++) if (selectable(rows[i])) return i
    return 0
  }

  function lastSetting () {
    for (let i = rows.length - 1; i >= 0; i--) if (selectable(rows[i])) return i
    return 0
  }

  // On a toggle, l is on and h is off; only a flip that changes the state fires.
  function cycle (delta) {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "choice") changed(row.key, SettingsLib.cycle(row, delta))
    else if (row.type === "toggle" && !row.busy && (delta > 0) !== (row.value === true)) activated(row.key, row.action)
  }

  // A choice row has nothing to open: h and l change it.
  function press () {
    const row = rows[cursor]
    if (!row) return
    if (row.type === "text") beginEdit(cursor)
    else if (row.type === "toggle") { if (!row.busy) activated(row.key, row.action) }
    else if (row.control === "dropdown") dropdownIndex = cursor
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: event => {
    // A row being edited owns the keyboard; its Enter reaches here too and would
    // reopen the editor.
    if (editingIndex !== -1 || dropdownIndex !== -1) return

    const chord = Chord.of(event)
    if (event.key === Qt.Key_Escape || event.text === "/" || (chord !== "" && (chord === page.settingsChord || chord === "C-,"))) {
      closed()
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
      cursor = lastSetting()
    }
    event.accepted = true
  }

  Flickable {
    id: scroll
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: layout.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    onHeightChanged: Qt.callLater(page.ensureCursorVisible)

  Column {
    id: layout

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.xs

    Repeater {
      id: rowRepeater
      model: page.rows

      delegate: Rectangle {
        id: settingRow

        required property int index
        required property var modelData

        // Imperative code in a Repeater delegate can't resolve outer ids, so the page
        // is held in a property.
        readonly property var owner: page
        readonly property bool isSection: modelData.type === "section"
        readonly property bool isInfo: modelData.type === "info"
        readonly property bool hasCursor: index === page.cursor && !isSection && !isInfo
        readonly property bool isChoice: modelData.type === "choice"
        readonly property bool isDropdown: isChoice && modelData.control === "dropdown"
        readonly property bool refused: index === page.refusedIndex

        width: layout.width
        height: isSection ? sectionLabel.implicitHeight + Style.spacing.lg + Style.spacing.md * 2
                          : body.implicitHeight + (isInfo ? Style.spacing.xs * 2 : Style.spacing.md * 2)
        radius: Style.cornerRadius
        color: hasCursor ? page.selectedBackground : "transparent"

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
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.spacing.xs
          textFormat: Text.PlainText
          text: settingRow.isSection ? String(settingRow.modelData.label).toUpperCase() : ""
          color: page.foreground
          opacity: 0.5
          font.family: page.fontFamily
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
              width: parent.width - (settingRow.isInfo ? 0
                                     : settingRow.isDropdown ? picker.width + Style.spacing.md
                                     : Style.space(200))
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: settingRow.modelData.label
                color: page.foreground
                opacity: settingRow.isInfo ? 0.8 : 1
                font.family: page.fontFamily
                font.pixelSize: settingRow.isInfo ? Style.font.body : Style.font.subtitle
                elide: Text.ElideRight
              }

              // The hint, or why the key just typed was refused.
              Text {
                width: parent.width
                textFormat: Text.PlainText
                // Section rows have no hint; an undefined binding warns on every repaint.
                text: settingRow.refused ? page.refusal : (settingRow.modelData.hint || "")
                color: settingRow.refused ? Color.urgent : page.foreground
                opacity: settingRow.refused ? 1 : 0.55
                font.family: page.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: settingRow.isDropdown || settingRow.isInfo || settingRow.refused ? Text.WordWrap : Text.NoWrap
                elide: settingRow.isDropdown || settingRow.isInfo || settingRow.refused ? Text.ElideNone : Text.ElideRight
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

              onWidthChanged: if (width > 0) settingRow.owner.noteChips(settingRow.index, width)   // hidden, it measures 0

              Repeater {
                model: inlineChips.visible ? settingRow.modelData.options : []
                delegate: chip
              }
            }

            // While open, the list has the keys; closing it hands them back to the page.
            Dropdown {
              id: picker

              readonly property bool asked: settingRow.index === page.dropdownIndex

              visible: settingRow.isDropdown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: page.chipColumn > 0 ? page.chipColumn : Style.space(200)
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

              readonly property bool editing: settingRow.index === page.editingIndex

              visible: settingRow.modelData.type === "text"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(120)
              text: String(settingRow.modelData.value)
              placeholderText: settingRow.modelData.placeholder || ""
              readOnly: !editing
              // Declarative, so focus drops the moment editing ends; held, it would swallow
              // the Esc meant for the page.
              focus: editing
              foreground: page.foreground
              accent: page.accent
              font.family: page.fontFamily
              horizontalAlignment: TextInput.AlignHCenter

              // A refused key keeps the old one and says why under the label.
              function commit () {
                const checked = SettingsLib.checkRow(settingRow.modelData, sequenceField.text, settingRow.owner.rows)
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
    }
  }
  }
}
