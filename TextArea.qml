import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Multi-line sibling of qs.Ui.TextField, styled from the same tokens. Used
// for a task's details, which is the one field that wants room to breathe.
Item {
  id: root

  property alias text: input.text
  property string placeholderText: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY

  signal edited()

  readonly property bool _focused: input.activeFocus
  readonly property bool _hot: hover.hovered
  readonly property var _borderSpec: Border.controlSpec(
    _focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  function forceActiveFocus() { input.forceActiveFocus() }

  implicitHeight: Style.space(120)

  BorderSurface {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
  }

  HoverHandler { id: hover }

  Flickable {
    anchors.fill: parent
    anchors.leftMargin: root.horizontalPadding + Border.left(root._borderSpec)
    anchors.rightMargin: root.horizontalPadding + Border.right(root._borderSpec)
    anchors.topMargin: root.verticalPadding + Border.top(root._borderSpec)
    anchors.bottomMargin: root.verticalPadding + Border.bottom(root._borderSpec)
    contentWidth: width
    contentHeight: input.contentHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    TextEdit {
      id: input
      width: parent.width
      wrapMode: TextEdit.Wrap
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      selectByMouse: true
      // Esc belongs to the dialog, not the editor, so a stray press closes
      // the task rather than doing nothing inside a focused field.
      Keys.onEscapePressed: function(event) { event.accepted = false }
      onTextChanged: root.edited()

      Text {
        anchors.fill: parent
        visible: input.text === "" && !input.activeFocus
        text: root.placeholderText
        color: Qt.darker(root.foreground, 1.6)
        font: input.font
        wrapMode: Text.Wrap
      }
    }
  }
}
