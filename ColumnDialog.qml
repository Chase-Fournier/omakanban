import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Per-column settings: name, accent, WIP limit, position, and the two
// destructive actions that belong to a column rather than to the board.
Item {
  id: dialog

  property var host: null
  property string columnId: ""

  signal closed()

  readonly property var columnData: host && host.board && columnId ? Model.column(host.board, columnId) : null
  readonly property int index: host && host.board ? Model.columnIndex(host.board, columnId) : -1
  readonly property int total: host && host.board ? host.board.columns.length : 0
  readonly property int taskCount: host && host.board ? Model.countIn(host.board, columnId) : 0

  Keys.onEscapePressed: function(event) { dialog.finish(); event.accepted = true }

  function commitName() {
    if (!columnData) return
    var value = nameField.text.trim()
    if (!value) { nameField.text = columnData.name; return }
    if (value !== columnData.name) host.patchColumn(columnId, { name: value })
  }

  function finish() {
    dialog.commitName()
    dialog.closed()
  }

  onColumnDataChanged: if (!columnData) dialog.closed()

  Component.onCompleted: Qt.callLater(function() { nameField.forceActiveFocus() })

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.66)
  }

  MouseArea {
    anchors.fill: parent
    onClicked: dialog.finish()
  }

  BorderSurface {
    id: sheet
    anchors.centerIn: parent
    width: Math.min(Style.space(460), parent.width - Style.space(48))
    height: Math.min(sheetColumn.implicitHeight + sheet.contentTopInset + sheet.contentBottomInset,
                     parent.height - Style.space(40))
    radius: Style.cornerRadius
    color: host.surface
    borderSpec: host.cardBorderSpec
    padding: Style.spacing.panelPadding

    MouseArea { anchors.fill: parent; onClicked: {} }

    // These sheets grow with the number of controls; on a short screen the
    // list has to scroll rather than run off the bottom.
    Flickable {
      id: sheetScroll
      anchors.fill: parent
      anchors.topMargin: sheet.contentTopInset
      anchors.bottomMargin: sheet.contentBottomInset
      anchors.leftMargin: sheet.contentLeftInset
      anchors.rightMargin: sheet.contentRightInset
      contentWidth: width
      contentHeight: sheetColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

    Column {
      id: sheetColumn
      width: sheetScroll.width
      spacing: Style.spacing.lg

      Item {
        width: parent.width
        height: heading.implicitHeight

        Text {
          id: heading
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Column"
          color: host.foreground
          font.family: host.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: dialog.taskCount + (dialog.taskCount === 1 ? " task" : " tasks")
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel { host: dialog.host; text: "Name" }

        TextField {
          id: nameField
          width: parent.width
          text: dialog.columnData ? dialog.columnData.name : ""
          onEditingFinished: dialog.commitName()
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel { host: dialog.host; text: "Accent" }

        Row {
          spacing: Style.spacing.sm

          Repeater {
            model: Model.SWATCHES

            Rectangle {
              id: swatch
              required property string modelData

              readonly property bool picked: dialog.columnData
                && String(dialog.columnData.color) === modelData

              width: Style.space(26)
              height: Style.space(26)
              radius: Style.cornerRadius > 0 ? width / 2 : 0
              color: modelData === "" ? "transparent" : modelData
              border.width: Math.max(1, Style.space(swatch.picked ? 3 : 1))
              border.color: swatch.picked ? host.foreground : Util.alpha(host.foreground, 0.18)
              opacity: swatch.picked ? 1.0 : 0.65

              // The empty swatch means "no accent"; a slash reads as off in a
              // row of colors better than an empty circle does.
              Text {
                anchors.centerIn: parent
                visible: swatch.modelData === ""
                text: ""
                color: host.muted
                font.family: host.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: host.patchColumn(dialog.columnId, { color: swatch.modelData })
              }
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel {
          host: dialog.host
          text: "WIP limit — " + (dialog.columnData && dialog.columnData.wip > 0
            ? ("warn above " + dialog.columnData.wip) : "off")
        }

        PanelSlider {
          width: parent.width
          minimum: 0
          maximum: 20
          step: 1
          integer: true
          value: dialog.columnData ? dialog.columnData.wip : 0
          fillColor: host.foreground
          knobColor: host.foreground
          trackColor: Util.alpha(host.foreground, 0.18)
          onMoved: function(value) { host.patchColumn(dialog.columnId, { wip: Math.round(value) }) }
        }
      }

      Toggle {
        width: parent.width
        label: "Finished work"
        description: "Cards dropped here are marked done"
        checked: dialog.columnData ? dialog.columnData.done === true : false
        foreground: host.foreground
        onClicked: host.patchColumn(dialog.columnId,
          { done: !(dialog.columnData && dialog.columnData.done) })
      }

      Toggle {
        width: parent.width
        label: "Collapsed"
        description: "Show this column as a narrow strip"
        checked: dialog.columnData ? dialog.columnData.collapsed === true : false
        foreground: host.foreground
        onClicked: {
          host.patchColumn(dialog.columnId,
            { collapsed: !(dialog.columnData && dialog.columnData.collapsed) })
          dialog.finish()
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel { host: dialog.host; text: "Sort the cards in this column" }

        Row {
          spacing: Style.spacing.xs

          Button {
            text: "Priority"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            onClicked: host.sortColumn(dialog.columnId, "priority")
          }

          Button {
            text: "Due date"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            onClicked: host.sortColumn(dialog.columnId, "due")
          }

          Button {
            text: "Title"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            onClicked: host.sortColumn(dialog.columnId, "title")
          }

          Button {
            text: "Oldest"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            onClicked: host.sortColumn(dialog.columnId, "created")
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        color: host.faint
      }

      Item {
        width: parent.width
        height: actions.implicitHeight

        Row {
          spacing: Style.spacing.xs
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          Button {
            iconText: ""
            tooltipText: "Move this column left"
            bordered: true
            foreground: host.foreground
            enabled: dialog.index > 0
            opacity: enabled ? 1 : 0.4
            onClicked: if (enabled) host.moveColumn(dialog.columnId, -1)
          }

          Button {
            iconText: ""
            tooltipText: "Move this column right"
            bordered: true
            foreground: host.foreground
            enabled: dialog.index >= 0 && dialog.index < dialog.total - 1
            opacity: enabled ? 1 : 0.4
            onClicked: if (enabled) host.moveColumn(dialog.columnId, 1)
          }
        }

        Row {
          id: actions
          spacing: Style.spacing.xs
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter

          Button {
            text: "Empty"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: Color.urgent
            enabled: dialog.taskCount > 0
            opacity: enabled ? 1 : 0.4
            tooltipText: "Remove every task in this column"
            onClicked: if (enabled) { dialog.closed(); host.clearColumn(dialog.columnId) }
          }

          Button {
            text: "Delete"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: Color.urgent
            enabled: dialog.total > 1
            opacity: enabled ? 1 : 0.4
            tooltipText: dialog.total > 1 ? "Delete this column" : "A board needs at least one column"
            onClicked: if (enabled) { dialog.closed(); host.deleteColumn(dialog.columnId) }
          }

          Button {
            text: "Done"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            onClicked: dialog.finish()
          }
        }
      }
    }
    }
  }
}
