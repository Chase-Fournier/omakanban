import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Board-wide preferences. Everything here is stored in board.json alongside
// the tasks, so the board travels as one file.
Item {
  id: dialog

  property var host: null

  signal closed()

  readonly property var settings: host && host.board ? host.board.settings : Model.defaultSettings()

  Keys.onEscapePressed: function(event) { dialog.finish(); event.accepted = true }

  function commitTitle() {
    var value = titleField.text.trim() || "Kanban"
    if (value !== settings.boardTitle) host.patchSettings({ boardTitle: value })
  }

  function finish() {
    dialog.commitTitle()
    dialog.closed()
  }

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
    width: Math.min(Style.space(500), parent.width - Style.space(48))
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

      Text {
        text: "Board settings"
        color: host.foreground
        font.family: host.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel { host: dialog.host; text: "Board name" }

        TextField {
          id: titleField
          width: parent.width
          text: dialog.settings.boardTitle
          onEditingFinished: dialog.commitTitle()
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        Item {
          width: parent.width
          height: sizeHeading.implicitHeight

          FieldLabel {
            id: sizeHeading
            host: dialog.host
            anchors.left: parent.left
            text: "Size on this screen · " + host.screenKey
              + (host.sizeIsAuto ? " · auto" : "")
          }

          Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.spacing.controlHeight
            verticalPadding: 0
            text: "Fit automatically"
            fontSize: Style.font.caption
            bordered: true
            foreground: host.foreground
            enabled: !host.sizeIsAuto
            opacity: enabled ? 1 : 0.4
            tooltipText: "Size this screen from the columns instead of a fixed percentage"
            onClicked: if (enabled) host.resetBoardSize()
          }
        }

        // Sized per screen: a percentage that suits a 3440-wide ultrawide is
        // not the same percentage that suits a 1440-wide laptop panel, so each
        // screen keeps its own and unvisited screens size themselves.
        FieldLabel {
          host: dialog.host
          text: "Width — " + host.boardWidthPercent + "%  ("
            + Math.round(host.screenWidth * host.boardWidthPercent / 100) + " px)"
        }

        PanelSlider {
          width: parent.width
          minimum: 30
          maximum: 100
          step: 1
          integer: true
          value: host.boardWidthPercent
          fillColor: host.foreground
          knobColor: host.foreground
          trackColor: Util.alpha(host.foreground, 0.18)
          onMoved: function(value) { host.setBoardSize({ width: Math.round(value) }) }
        }

        FieldLabel {
          host: dialog.host
          text: "Height — " + host.boardHeightPercent + "%  ("
            + Math.round(host.screenHeight * host.boardHeightPercent / 100) + " px)"
        }

        PanelSlider {
          width: parent.width
          minimum: 30
          maximum: 100
          step: 1
          integer: true
          value: host.boardHeightPercent
          fillColor: host.foreground
          knobColor: host.foreground
          trackColor: Util.alpha(host.foreground, 0.18)
          onMoved: function(value) { host.setBoardSize({ height: Math.round(value) }) }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel { host: dialog.host; text: "Column width — " + dialog.settings.columnWidth }

        PanelSlider {
          width: parent.width
          minimum: 200
          maximum: 560
          step: 10
          integer: true
          value: dialog.settings.columnWidth
          fillColor: host.foreground
          knobColor: host.foreground
          trackColor: Util.alpha(host.foreground, 0.18)
          onMoved: function(value) { host.patchSettings({ columnWidth: Math.round(value) }) }
        }
      }

      Toggle {
        width: parent.width
        label: "Compact cards"
        description: "One-line titles, no thumbnails or tags"
        checked: dialog.settings.compact === true
        foreground: host.foreground
        onClicked: host.patchSettings({ compact: !dialog.settings.compact })
      }

      Toggle {
        width: parent.width
        label: "Image thumbnails"
        description: "Show the first attached image on the card"
        checked: dialog.settings.showImages !== false
        foreground: host.foreground
        onClicked: host.patchSettings({ showImages: !dialog.settings.showImages })
      }

      Toggle {
        width: parent.width
        label: "Tags on cards"
        checked: dialog.settings.showTags !== false
        foreground: host.foreground
        onClicked: host.patchSettings({ showTags: !dialog.settings.showTags })
      }

      Toggle {
        width: parent.width
        label: "Due dates on cards"
        checked: dialog.settings.showDueDates !== false
        foreground: host.foreground
        onClicked: host.patchSettings({ showDueDates: !dialog.settings.showDueDates })
      }

      Toggle {
        width: parent.width
        label: "Confirm before deleting"
        description: "Ask before a task or column disappears"
        checked: dialog.settings.confirmDelete !== false
        foreground: host.foreground
        onClicked: host.patchSettings({ confirmDelete: !dialog.settings.confirmDelete })
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        color: host.faint
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap

        FieldLabel { host: dialog.host; text: "Board file" }

        Text {
          width: parent.width
          text: host.boardPath.replace(host.home, "~")
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      Item {
        width: parent.width
        height: footerRow.implicitHeight

        Row {
          id: footerRow
          anchors.right: parent.right
          spacing: Style.spacing.xs

          Button {
            iconText: ""
            text: "Open folder"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            onClicked: host.revealDataDir()
          }

          Button {
            text: "Archive done"
            fontSize: Style.font.bodySmall
            bordered: true
            foreground: host.foreground
            tooltipText: "Remove every finished task from the board"
            onClicked: { dialog.closed(); host.archiveDone() }
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
