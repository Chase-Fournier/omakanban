import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Due-date field: a text input you can still type into, plus a calendar
// button. Typing stays supported because "2026-08-24" is faster than six
// clicks when you already know the date.
Item {
  id: root

  property string value: ""
  property real controlHeight: Style.spacing.controlHeight
  property color foreground: Color.foreground
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  // Emitted with a YYYY-MM-DD string, or "" when the date is cleared.
  signal picked(string date)
  // Emitted when a typed value is not a date we can store.
  signal rejected(string text)

  readonly property bool popupOpen: popup.opened
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)

  implicitHeight: controlHeight

  function isValid(text) { return /^\d{4}-\d{2}-\d{2}$/.test(String(text || "").trim()) }

  function pad(n) { return (n < 10 ? "0" : "") + n }
  function iso(date) { return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) }

  function commitTyped() {
    var text = field.text.trim()
    if (text === "") { root.picked(""); return }
    if (!root.isValid(text)) { root.rejected(text); field.text = root.value; return }
    root.picked(text)
  }

  function choose(date) {
    popup.close()
    root.picked(root.iso(date))
  }

  // The month the grid is showing. Follows `value` while the popup is closed
  // so reopening always lands on the date you already have.
  property date shownMonth: new Date()

  function syncShownMonth() {
    var base = root.isValid(root.value) ? new Date(root.value + "T12:00:00") : new Date()
    root.shownMonth = new Date(base.getFullYear(), base.getMonth(), 1)
  }

  function stepMonth(delta) {
    root.shownMonth = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth() + delta, 1)
  }

  onValueChanged: if (!popup.opened) field.text = root.value

  TextField {
    id: field
    anchors.left: parent.left
    anchors.right: calendarButton.left
    anchors.rightMargin: Style.spacing.xs
    height: root.controlHeight
    verticalPadding: 0
    placeholderText: "YYYY-MM-DD"
    foreground: root.foreground
    text: root.value
    onEditingFinished: root.commitTyped()
  }

  Button {
    id: calendarButton
    anchors.right: parent.right
    width: root.controlHeight
    height: root.controlHeight
    horizontalPadding: 0
    verticalPadding: 0
    bordered: true
    iconText: ""
    iconSize: Style.font.caption
    tooltipText: "Pick a date"
    foreground: root.foreground
    onClicked: {
      if (popup.opened) { popup.close(); return }
      if (Date.now() - popup.closedAt < 250) return
      root.syncShownMonth()
      popup.open()
    }
  }

  Popup {
    id: popup

    property double closedAt: 0

    // Right-aligned under the field so a picker on the last column of a form
    // row does not run off the sheet.
    x: root.width - width
    y: root.height + Style.spacing.xxs
    width: Style.space(252)
    implicitHeight: grid.implicitHeight + header.height + weekdays.height + footer.height
      + Style.spacing.sm * 3 + topPadding + bottomPadding
    padding: Style.spacing.sm
    leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.sm
    rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.sm
    topPadding: Border.top(root.popupBorderSpec) + Style.spacing.sm
    bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.sm
    focus: true

    onClosed: closedAt = Date.now()

    background: BorderSurface {
      color: root.background
      borderSpec: root.popupBorderSpec
      radius: Style.cornerRadius
    }

    Keys.onEscapePressed: function(event) { popup.close(); event.accepted = true }

    contentItem: Column {
      spacing: Style.spacing.sm

      // ------------------------------------------------------------ header
      Item {
        id: header
        width: parent.width
        height: Style.spacing.controlHeight

        Button {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: Style.spacing.controlHeight
          horizontalPadding: Style.spacing.sm
          verticalPadding: 0
          iconText: ""
          iconSize: Style.font.caption
          foreground: root.foreground
          onClicked: root.stepMonth(-1)
        }

        Text {
          anchors.centerIn: parent
          text: Qt.formatDate(root.shownMonth, "MMMM yyyy")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.spacing.controlHeight
          horizontalPadding: Style.spacing.sm
          verticalPadding: 0
          iconText: ""
          iconSize: Style.font.caption
          foreground: root.foreground
          onClicked: root.stepMonth(1)
        }
      }

      // ---------------------------------------------------------- weekdays
      Row {
        id: weekdays
        width: parent.width

        Repeater {
          model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

          Text {
            required property string modelData
            width: weekdays.width / 7
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            color: Util.alpha(root.foreground, 0.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // -------------------------------------------------------------- grid
      Grid {
        id: grid
        width: parent.width
        columns: 7

        readonly property real cell: width / 7
        readonly property string todayIso: root.iso(new Date())

        // Six rows always, so stepping months never resizes the popup.
        readonly property var days: {
          var first = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth(), 1)
          // getDay() is Sunday-based; the grid starts on Monday.
          var lead = (first.getDay() + 6) % 7
          var start = new Date(first.getFullYear(), first.getMonth(), 1 - lead)
          var out = []
          for (var i = 0; i < 42; i++) {
            var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
            out.push({
              iso: root.iso(d),
              day: d.getDate(),
              outside: d.getMonth() !== root.shownMonth.getMonth()
            })
          }
          return out
        }

        Repeater {
          model: grid.days

          Rectangle {
            id: cell
            required property var modelData

            width: grid.cell
            height: grid.cell
            radius: Style.cornerRadius > 0 ? width / 2 : 0

            readonly property bool selected: root.value === modelData.iso
            readonly property bool isToday: grid.todayIso === modelData.iso

            color: selected ? Style.selectedFillFor(root.foreground, root.accent)
              : cellHover.hovered ? Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"
            border.width: cell.isToday && !cell.selected ? Math.max(1, Style.space(1)) : 0
            border.color: Util.alpha(root.accent, 0.7)

            HoverHandler { id: cellHover }

            Text {
              anchors.centerIn: parent
              text: cell.modelData.day
              color: cell.selected ? Style.selectedStateColor(root.foreground, root.accent)
                : cell.modelData.outside ? Util.alpha(root.foreground, 0.3)
                : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: cell.selected || cell.isToday
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.choose(new Date(cell.modelData.iso + "T12:00:00"))
            }
          }
        }
      }

      // ------------------------------------------------------------ footer
      Item {
        id: footer
        width: parent.width
        height: Style.spacing.controlHeight

        Button {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: Style.spacing.controlHeight
          verticalPadding: 0
          text: "Today"
          fontSize: Style.font.bodySmall
          bordered: true
          foreground: root.foreground
          onClicked: root.choose(new Date())
        }

        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.spacing.controlHeight
          verticalPadding: 0
          text: "Clear"
          fontSize: Style.font.bodySmall
          bordered: true
          foreground: root.foreground
          onClicked: { popup.close(); root.picked("") }
        }
      }
    }
  }
}
