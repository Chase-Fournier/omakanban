import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Single-select dropdown, sized to a caller-supplied control height so it
// lines up with the text fields beside it.
//
// This exists instead of qs.Ui.Dropdown for two reasons: that one derives its
// height from a shared token the form cannot override, and clicking its
// trigger while the list is open reopens the list — the popup close policy
// dismisses on press, then the click handler sees a closed popup and opens it
// again. The `_closedAt` guard below is what fixes the second one.
Item {
  id: root

  property var options: []
  property string value: ""
  property real controlHeight: Style.spacing.controlHeight
  property color foreground: Color.foreground
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool enabled: true

  signal changed(string value)

  readonly property bool popupOpen: popup.opened
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)

  implicitHeight: controlHeight
  implicitWidth: Style.spacing.dropdownWidth

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object") ? String(o.label) : String(o) }

  function currentLabel() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    return value
  }

  function indexOfValue(v) {
    for (var i = 0; i < options.length; i++) if (optionValue(options[i]) === v) return i
    return -1
  }

  function pick(index) {
    if (index < 0 || index >= options.length) return
    var next = optionValue(options[index])
    popup.close()
    if (next !== root.value) root.changed(next)
  }

  // Timestamp of the last close. A click that lands within a couple of frames
  // of one is the release half of the press that dismissed the popup, not a
  // fresh request to open it.
  property double _closedAt: 0

  BorderSurface {
    id: trigger
    anchors.fill: parent
    radius: Style.cornerRadius
    activeFocusOnTab: root.enabled
    opacity: root.enabled ? 1 : 0.5

    readonly property bool _focused: activeFocus || popup.opened
    readonly property bool _hot: hover.hovered
    color: Style.controlFill(_focused, _hot, root.foreground, root.accent)
    borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"),
                                   root.foreground, root.accent)

    HoverHandler { id: hover; enabled: root.enabled }

    Keys.onPressed: function(event) {
      if (!root.enabled) return
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        if (!popup.opened) popup.open()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape && popup.opened) {
        popup.close()
        event.accepted = true
      }
    }

    Text {
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.sm
      text: root.currentLabel()
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: chevron
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: trigger.borderRight + Style.spacing.controlPaddingX
      text: ""
      color: Util.alpha(root.foreground, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        trigger.forceActiveFocus()
        if (popup.opened) { popup.close(); return }
        if (Date.now() - root._closedAt < 250) return
        popup.open()
      }
    }
  }

  Popup {
    id: popup
    y: root.height + Style.spacing.xxs
    width: root.width
    padding: Style.spacing.hairline
    leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
    rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
    topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
    bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
    focus: true
    implicitHeight: Math.min(list.contentHeight, root.controlHeight * 8) + topPadding + bottomPadding

    onClosed: root._closedAt = Date.now()
    onOpened: {
      list.currentIndex = root.indexOfValue(root.value)
      list.positionViewAtIndex(Math.max(0, list.currentIndex), ListView.Contain)
      list.forceActiveFocus()
    }

    background: BorderSurface {
      color: root.background
      borderSpec: root.popupBorderSpec
      radius: Style.cornerRadius
    }

    contentItem: ListView {
      id: list
      implicitHeight: contentHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.options
      currentIndex: -1

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
        else if (event.key === Qt.Key_Down) {
          list.currentIndex = Math.min(root.options.length - 1, list.currentIndex + 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          list.currentIndex = Math.max(0, list.currentIndex - 1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.pick(list.currentIndex)
          event.accepted = true
        }
      }

      delegate: Rectangle {
        id: row
        required property var modelData
        required property int index

        width: ListView.view.width
        height: root.controlHeight
        readonly property bool selected: root.optionValue(modelData) === root.value
        readonly property bool hot: rowHover.hovered || list.currentIndex === index
        color: hot ? Style.hoverFillFor(root.foreground, root.accent)
          : selected ? Style.selectedFillFor(root.foreground, root.accent)
          : "transparent"

        HoverHandler { id: rowHover }

        Text {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.rightMargin: Style.spacing.controlPaddingX
          text: root.optionLabel(row.modelData)
          color: row.selected ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pick(row.index)
        }
      }
    }
  }
}
