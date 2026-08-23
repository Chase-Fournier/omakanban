import QtQuick
import qs.Commons

// Caption above a form control. One component so every label in the sheet
// picks up the same size, color, and casing.
Text {
  property var host: null

  color: host ? host.muted : Color.foreground
  font.family: host ? host.fontFamily : Style.font.family
  font.pixelSize: Style.font.caption
}
