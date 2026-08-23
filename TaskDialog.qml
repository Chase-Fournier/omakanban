import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Task detail sheet. Text fields hold their own draft and write back on
// editingFinished / close rather than on every keystroke: committing per
// character would rebuild the board object under the cursor and bounce it to
// the end of the line.
Item {
  id: dialog

  property var host: null
  property string taskId: ""

  signal closed()

  // Unhandled keys bubble up the parent chain to here, so Esc closes the
  // sheet from any field that doesn't claim it.
  Keys.onEscapePressed: function(event) { dialog.finish(); event.accepted = true }

  readonly property var taskData: host && host.board && taskId ? Model.task(host.board, taskId) : null
  readonly property var columns: host && host.board ? host.board.columns : []
  readonly property var links: taskData && taskData.links ? taskData.links : []
  // Every control on a row is pinned to this so fields, dropdowns, and
  // buttons share a baseline instead of each picking its own implicit height.
  readonly property real controlHeight: Math.max(Style.spacing.controlHeight + Style.space(4),
                                                 Style.font.body + Style.spacing.inputPaddingY * 2)
  readonly property var images: taskData && taskData.images ? taskData.images : []

  function columnOptions() {
    var out = []
    for (var i = 0; i < columns.length; i++) out.push({ value: columns[i].id, label: columns[i].name })
    return out
  }

  function priorityOptions() {
    return [
      { value: "none", label: "No priority" },
      { value: "low", label: "Low" },
      { value: "medium", label: "Medium" },
      { value: "high", label: "High" },
      { value: "urgent", label: "Urgent" }
    ]
  }

  function patch(fields) {
    if (!taskId) return
    host.patchTask(taskId, fields)
  }

  function commitTitle() {
    if (!taskData) return
    var value = titleField.text.trim()
    if (!value) { titleField.text = taskData.title; return }
    if (value !== taskData.title) dialog.patch({ title: value })
  }

  function commitDetails() {
    if (!taskData) return
    if (detailsField.text !== taskData.details) dialog.patch({ details: detailsField.text })
  }

  function commitTags() {
    if (!taskData) return
    var parsed = Model.parseTags(tagsField.text)
    if (Model.tagsText(parsed) !== Model.tagsText(taskData.tags)) dialog.patch({ tags: parsed })
    tagsField.text = Model.tagsText(parsed)
  }

  function commitAll() {
    commitTitle()
    commitDetails()
    commitTags()
  }

  function addLink(value) {
    if (!taskData) return
    var link = Model.normalizeLink(value)
    if (!link) return
    var next = taskData.links.slice()
    if (next.indexOf(link) !== -1) return
    next.push(link)
    dialog.patch({ links: next })
    linkField.text = ""
  }

  function removeLink(index) {
    if (!taskData) return
    var next = taskData.links.slice()
    next.splice(index, 1)
    dialog.patch({ links: next })
  }

  function addImage(value) {
    if (!taskData) return
    var path = String(value || "").trim()
    if (!path) return
    if (path.charAt(0) === "~") path = host.home + path.slice(1)
    var next = taskData.images.slice()
    if (next.indexOf(path) !== -1) return
    next.push(path)
    dialog.patch({ images: next })
    imageField.text = ""
  }

  function removeImage(index) {
    if (!taskData) return
    var next = taskData.images.slice()
    next.splice(index, 1)
    dialog.patch({ images: next })
  }

  function finish() {
    dialog.commitAll()
    dialog.closed()
  }

  // A task deleted from under the sheet (via the confirm dialog) closes it.
  onTaskDataChanged: if (!taskData) dialog.closed()

  Component.onCompleted: Qt.callLater(function() { titleField.forceActiveFocus() })

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
    width: Math.min(Style.space(780), parent.width - Style.space(48))
    height: Math.min(Style.space(760), parent.height - Style.space(32))
    radius: Style.cornerRadius
    color: host.surface
    borderSpec: host.cardBorderSpec
    padding: Style.spacing.panelPadding

    MouseArea { anchors.fill: parent; onClicked: {} }

    Column {
      anchors.fill: parent
      anchors.topMargin: sheet.contentTopInset
      anchors.rightMargin: sheet.contentRightInset
      anchors.bottomMargin: sheet.contentBottomInset
      anchors.leftMargin: sheet.contentLeftInset
      spacing: Style.spacing.md

      // ---------------------------------------------------------- title row
      Item {
        id: titleRow
        width: parent.width
        height: Math.max(titleField.height, closeButton.height)

        TextField {
          id: titleField
          anchors.left: parent.left
          anchors.right: closeButton.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          height: dialog.controlHeight + Style.space(6)
          verticalPadding: 0
          font.pixelSize: Style.font.title
          placeholderText: "Task title"
          text: dialog.taskData ? dialog.taskData.title : ""
          onEditingFinished: dialog.commitTitle()
          Keys.onEscapePressed: function(event) { dialog.finish(); event.accepted = true }
        }

        Button {
          id: closeButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: dialog.controlHeight + Style.space(6)
          height: dialog.controlHeight + Style.space(6)
          horizontalPadding: 0
          verticalPadding: 0
          iconText: ""
          tooltipText: "Close (Esc)"
          foreground: host.foreground
          onClicked: dialog.finish()
        }
      }

      // ------------------------------------------------------------- body
      Flickable {
        id: body
        width: parent.width
        height: parent.height - titleRow.height - footer.height - Style.spacing.md * 2
        contentWidth: width
        contentHeight: bodyColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: bodyColumn
          width: body.width - Style.spacing.sm
          spacing: Style.spacing.lg

          // ------------------------------------------------------ metadata
          Grid {
            width: parent.width
            columns: 3
            columnSpacing: Style.spacing.md
            rowSpacing: Style.spacing.sm

            readonly property real cellWidth: (width - columnSpacing * 2) / 3

            Column {
              width: parent.cellWidth
              spacing: Style.spacing.labelGap

              FieldLabel { host: dialog.host; text: "Column" }

              Select {
                width: parent.width
                controlHeight: dialog.controlHeight
                foreground: host.foreground
                background: host.surface
                fontFamily: host.fontFamily
                options: dialog.columnOptions()
                value: dialog.taskData ? dialog.taskData.columnId : ""
                onChanged: function(value) {
                  if (dialog.taskData && value !== dialog.taskData.columnId)
                    host.moveTask(dialog.taskId, value, "")
                }
              }
            }

            Column {
              width: parent.cellWidth
              spacing: Style.spacing.labelGap

              FieldLabel { host: dialog.host; text: "Priority" }

              Select {
                width: parent.width
                controlHeight: dialog.controlHeight
                foreground: host.foreground
                background: host.surface
                fontFamily: host.fontFamily
                options: dialog.priorityOptions()
                value: dialog.taskData ? dialog.taskData.priority : "none"
                onChanged: function(value) { dialog.patch({ priority: value }) }
              }
            }

            Column {
              width: parent.cellWidth
              spacing: Style.spacing.labelGap

              FieldLabel { host: dialog.host; text: "Due" }

              DatePicker {
                id: dueField
                width: parent.width
                controlHeight: dialog.controlHeight
                foreground: host.foreground
                background: host.surface
                fontFamily: host.fontFamily
                value: dialog.taskData ? dialog.taskData.due : ""
                onPicked: function(date) { dialog.patch({ due: date }) }
                onRejected: host.notify("Due dates use YYYY-MM-DD")
              }
            }
          }

          // ---------------------------------------------------------- tags
          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            FieldLabel { host: dialog.host; text: "Tags (comma separated)" }

            TextField {
              id: tagsField
              width: parent.width
              height: dialog.controlHeight
              verticalPadding: 0
              placeholderText: "design, urgent, someday"
              text: dialog.taskData ? Model.tagsText(dialog.taskData.tags) : ""
              onEditingFinished: dialog.commitTags()
            }
          }

          // ------------------------------------------------------- details
          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            FieldLabel { host: dialog.host; text: "Details" }

            TextArea {
              id: detailsField
              width: parent.width
              implicitHeight: Style.space(150)
              foreground: host.foreground
              placeholderText: "Notes, acceptance criteria, whatever the task needs…"
              text: dialog.taskData ? dialog.taskData.details : ""
              onEdited: detailsSaveTimer.restart()
            }
          }

          // --------------------------------------------------------- links
          Column {
            width: parent.width
            spacing: Style.spacing.sm

            FieldLabel { host: dialog.host; text: "Links" }

            Repeater {
              model: dialog.links

              Item {
                id: linkRow
                required property string modelData
                required property int index
                width: bodyColumn.width
                height: dialog.controlHeight

                Button {
                  anchors.left: parent.left
                  anchors.right: dropLink.left
                  anchors.rightMargin: Style.spacing.xs
                  anchors.verticalCenter: parent.verticalCenter
                  height: dialog.controlHeight
                  verticalPadding: 0
                  leftAlign: true
                  bordered: true
                  iconText: ""
                  iconSize: Style.font.caption
                  fontSize: Style.font.bodySmall
                  text: Model.linkLabel(linkRow.modelData)
                  tooltipText: linkRow.modelData
                  foreground: dialog.host.foreground
                  onClicked: dialog.host.openExternal(linkRow.modelData)
                }

                Button {
                  id: dropLink
                  bordered: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: dialog.controlHeight
                  height: dialog.controlHeight
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: ""
                  iconSize: Style.font.caption
                  tooltipText: "Remove this link"
                  foreground: dialog.host.muted
                  onClicked: dialog.removeLink(linkRow.index)
                }
              }
            }

            Item {
              width: parent.width
              height: dialog.controlHeight

              TextField {
                id: linkField
                anchors.left: parent.left
                anchors.right: addLinkButton.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                height: dialog.controlHeight
                verticalPadding: 0
                placeholderText: "https://… or /path/to/file"
                onAccepted: dialog.addLink(text)
              }

              Button {
                id: addLinkButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: dialog.controlHeight
                height: dialog.controlHeight
                horizontalPadding: 0
                verticalPadding: 0
                iconText: ""
                bordered: true
                tooltipText: "Add this link"
                foreground: host.foreground
                onClicked: dialog.addLink(linkField.text)
              }
            }
          }

          // -------------------------------------------------------- images
          Column {
            width: parent.width
            spacing: Style.spacing.sm

            FieldLabel { host: dialog.host; text: "Images" }

            Flow {
              width: parent.width
              spacing: Style.spacing.sm
              visible: dialog.images.length > 0

              Repeater {
                model: dialog.images

                Rectangle {
                  id: thumb
                  required property string modelData
                  required property int index

                  width: Style.space(132)
                  height: Style.space(96)
                  radius: Style.cornerRadius
                  color: Util.alpha(host.foreground, 0.06)
                  clip: true

                  Image {
                    id: thumbImage
                    anchors.fill: parent
                    source: Util.fileUrl(thumb.modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.round(width * 2)
                  }

                  // A path that no longer resolves still has to be
                  // identifiable, and removable, from the sheet.
                  Text {
                    anchors.centerIn: parent
                    visible: thumbImage.status === Image.Error
                    width: parent.width - Style.spacing.sm * 2
                    text: Model.fileName(thumb.modelData)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: host.muted
                    font.family: host.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: host.previewImage(dialog.images, thumb.index)

                    Button {
                      visible: parent.containsMouse
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.spacing.xxs
                      iconText: ""
                      iconSize: Style.font.caption
                      horizontalPadding: Style.spacing.xs
                      verticalPadding: Style.spacing.xxs
                      background: Util.alpha(Color.background, 0.7)
                      foreground: Color.urgent
                      tooltipText: "Remove this image"
                      onClicked: dialog.removeImage(thumb.index)
                    }
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: dialog.controlHeight

              TextField {
                id: imageField
                anchors.left: parent.left
                anchors.right: imageButtons.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                height: dialog.controlHeight
                verticalPadding: 0
                placeholderText: "/path/to/image.png"
                onAccepted: dialog.addImage(text)
              }

              Row {
                id: imageButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Button {
                  width: dialog.controlHeight
                  height: dialog.controlHeight
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: ""
                  bordered: true
                  tooltipText: "Add the path above"
                  foreground: host.foreground
                  onClicked: dialog.addImage(imageField.text)
                }

                Button {
                  width: dialog.controlHeight
                  height: dialog.controlHeight
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: ""
                  bordered: true
                  tooltipText: "Paste an image from the clipboard"
                  foreground: host.foreground
                  onClicked: host.attachClipboardImage(dialog.taskId)
                }

                Button {
                  width: dialog.controlHeight
                  height: dialog.controlHeight
                  horizontalPadding: 0
                  verticalPadding: 0
                  iconText: ""
                  bordered: true
                  tooltipText: "Choose a file…"
                  foreground: host.foreground
                  onClicked: host.browseForImage(dialog.taskId)
                }
              }
            }
          }
        }
      }

      // ------------------------------------------------------------ footer
      Item {
        id: footer
        width: parent.width
        height: dialog.controlHeight + Style.space(6)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: dialog.taskData
            ? "Created " + Qt.formatDateTime(new Date(dialog.taskData.created), "d MMM yyyy")
              + " · Updated " + Qt.formatDateTime(new Date(dialog.taskData.updated), "d MMM HH:mm")
            : ""
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlGap

          Button {
            height: dialog.controlHeight
            verticalPadding: 0
            iconText: dialog.taskData && dialog.taskData.done ? "" : ""
            text: dialog.taskData && dialog.taskData.done ? "Done" : "Mark done"
            bordered: true
            foreground: host.foreground
            onClicked: host.toggleTaskDone(dialog.taskId)
          }

          Button {
            height: dialog.controlHeight
            verticalPadding: 0
            iconText: ""
            text: "Duplicate"
            bordered: true
            foreground: host.foreground
            onClicked: { dialog.commitAll(); host.duplicateTask(dialog.taskId) }
          }

          Button {
            height: dialog.controlHeight
            verticalPadding: 0
            iconText: ""
            text: "Delete"
            bordered: true
            foreground: Color.urgent
            onClicked: host.deleteTask(dialog.taskId)
          }
        }
      }
    }

    Timer {
      id: detailsSaveTimer
      interval: 700
      repeat: false
      onTriggered: dialog.commitDetails()
    }
  }
}
