import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omaseek"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf002"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Omaseek — search and ask"
    onPressed: function(button) {
      if (root.bar && button === Qt.LeftButton)
        root.bar.run("omarchy-shell shell toggle omaseek")
    }
  }
}
