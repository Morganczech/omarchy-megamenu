import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "gruut.megamenu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string iconGlyph: String(setting("icon", "󰀻"))
  readonly property string languageSetting: String(setting("language", "auto"))

  function toggleMegamenu() {
    var payload = JSON.stringify({ language: root.languageSetting })
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "gruut.megamenu", payload])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    tooltipText: "Omarchy Megamenu"
    onPressed: root.toggleMegamenu()
  }
}
