import QtQuick
import qs.Commons
import qs.Ui

// Small square glyph button for the card hover bar. Sized off the caption
// font so a row of four still fits inside a narrow lane.
Button {
  id: action

  property string glyph: ""
  property string tip: ""
  property bool danger: false

  signal triggered()

  iconText: glyph
  tooltipText: tip
  iconSize: Style.font.caption
  horizontalPadding: Style.spacing.xs
  verticalPadding: Style.spacing.xxs
  foreground: danger ? Color.urgent : (host ? host.muted : Color.foreground)

  property var host: null

  onClicked: action.triggered()
}
