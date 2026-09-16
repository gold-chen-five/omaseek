import QtQuick

// Enough of the kit's Button to instantiate a strip of them outside the shell:
// the properties the panel sets, and a click.
Item {
  id: button

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property bool selected: false
  property bool active: false
  property bool bordered: false
  property color foreground: "white"
  property color accent: "white"
  property string fontFamily: ""
  property real fontSize: 10

  signal clicked()

  MouseArea {
    anchors.fill: parent
    onClicked: button.clicked()
  }
}
