import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One card in a lane. The outer Item holds the slot open in the stack while
// the inner surface is reparented into the board's drag layer mid-drag, so
// neighbouring cards don't collapse under the pointer.
Item {
  id: slot

  property var host: null
  property var column: null
  property var taskData: ({})
  property int cardIndex: 0

  readonly property string taskId: taskData ? String(taskData.id) : ""
  readonly property string title: taskData ? String(taskData.title) : ""
  readonly property bool done: taskData ? taskData.done === true : false
  readonly property string priority: taskData ? String(taskData.priority) : "none"
  readonly property var tags: taskData && taskData.tags ? taskData.tags : []
  readonly property var links: taskData && taskData.links ? taskData.links : []
  readonly property var images: taskData && taskData.images ? taskData.images : []
  readonly property string details: taskData ? String(taskData.details) : ""
  readonly property string due: taskData ? String(taskData.due) : ""
  readonly property string dueState: Model.dueState(due)

  readonly property bool compact: host && host.settings ? host.settings.compact === true : false
  readonly property bool showImages: host && host.settings ? host.settings.showImages !== false : true
  readonly property bool showTags: host && host.settings ? host.settings.showTags !== false : true
  readonly property bool showDue: host && host.settings ? host.settings.showDueDates !== false : true

  readonly property string thumbnail: showImages && images.length > 0 ? String(images[0]) : ""

  readonly property color priorityColor: priority === "urgent" ? Color.urgent
    : priority === "high" ? "#e08a5a"
    : priority === "medium" ? "#e8c46a"
    : priority === "low" ? "#6ea8fe"
    : "transparent"

  readonly property bool hasMeta: details !== "" || links.length > 0
    || images.length > 0 || (showDue && due !== "")

  readonly property color dueColor: dueState === "overdue" ? Color.urgent
    : dueState === "today" ? "#e8c46a"
    : host.muted

  height: surface.height

  Component.onCompleted: if (column) column.registerCard(taskId, slot)
  Component.onDestruction: if (column) column.unregisterCard(taskId)

  BorderSurface {
    id: surface
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: content.implicitHeight + Style.spacing.md * 2
    radius: Style.cornerRadius
    color: dragArea.drag.active ? Util.alpha(host.foreground, 0.20)
      : cardHover.hovered ? Util.alpha(host.foreground, 0.14)
      : Util.alpha(host.foreground, 0.09)
    borderSpec: dragArea.drag.active
      ? Border.flat(Color.accent, Math.max(1, Style.space(1)))
      : Border.flat(Util.alpha(host.foreground, 0.16), Math.max(1, Style.space(1)))
    opacity: slot.done ? 0.55 : 1.0

    Behavior on color { ColorAnimation { duration: 110 } }

    HoverHandler { id: cardHover }

    Drag.active: dragArea.drag.active
    Drag.source: slot
    Drag.keys: ["chase.kanban.task"]
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: Style.space(20)

    states: State {
      when: dragArea.drag.active
      AnchorChanges {
        target: surface
        anchors.left: undefined
        anchors.right: undefined
        anchors.top: undefined
      }
      ParentChange { target: surface; parent: host.dragHost }
    }

    // Priority stripe. A colorless "none" leaves the edge clean rather than
    // painting a grey bar that reads as a fifth priority.
    Rectangle {
      visible: slot.priority !== "none"
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Math.max(1, Style.space(1))
      width: Math.max(2, Style.space(3))
      radius: width / 2
      color: slot.priorityColor
    }

    Column {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.spacing.md + Style.space(4)
      anchors.rightMargin: Style.spacing.md
      anchors.topMargin: Style.spacing.md
      spacing: Style.spacing.sm

      // -------------------------------------------------------- thumbnail
      Rectangle {
        visible: slot.thumbnail !== "" && !slot.compact
        width: parent.width
        height: Style.space(104)
        radius: Style.cornerRadius
        color: Util.alpha(host.foreground, 0.06)
        clip: true

        Image {
          anchors.fill: parent
          source: Util.fileUrl(slot.thumbnail)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          sourceSize.width: Math.round(parent.width * 2)
        }

        Rectangle {
          visible: slot.images.length > 1
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.xs
          width: badge.implicitWidth + Style.spacing.sm * 2
          height: badge.implicitHeight + Style.spacing.xxs * 2
          radius: Style.cornerRadius
          color: Util.alpha(Color.background, 0.75)

          Text {
            id: badge
            anchors.centerIn: parent
            text: "+" + (slot.images.length - 1)
            color: host.foreground
            font.family: host.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ------------------------------------------------------------ title
      Text {
        width: parent.width
        text: slot.title
        color: host.foreground
        font.family: host.fontFamily
        font.pixelSize: slot.compact ? Style.font.bodySmall : Style.font.body
        font.strikeout: slot.done
        wrapMode: Text.WordWrap
        maximumLineCount: slot.compact ? 1 : 3
        elide: Text.ElideRight
      }

      // ------------------------------------------------------------- tags
      Flow {
        visible: slot.showTags && slot.tags.length > 0 && !slot.compact
        width: parent.width
        spacing: Style.spacing.xxs

        Repeater {
          model: slot.tags

          Rectangle {
            required property string modelData
            width: tagLabel.implicitWidth + Style.spacing.sm * 2
            height: tagLabel.implicitHeight + Style.spacing.xxs * 2
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            color: Util.alpha(host.foreground, 0.10)

            Text {
              id: tagLabel
              anchors.centerIn: parent
              text: parent.modelData
              color: host.muted
              font.family: host.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // ------------------------------------------------------------- meta
      Row {
        width: parent.width
        spacing: Style.spacing.sm
        visible: slot.hasMeta

        Text {
          visible: slot.showDue && slot.due !== ""
          text: " " + Model.dueLabel(slot.due)
          color: slot.dueColor
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: slot.details !== ""
          text: ""
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: slot.links.length > 0
          text: " " + slot.links.length
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: slot.images.length > 0 && (slot.compact || slot.thumbnail === "")
          text: " " + slot.images.length
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ----------------------------------------------------------- hover bar
    Row {
      visible: cardHover.hovered && !dragArea.drag.active
      z: 5
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.xxs
      spacing: 0

      CardAction {
        host: slot.host
        glyph: slot.done ? "" : ""
        tip: slot.done ? "Mark as not done" : "Mark as done"
        onTriggered: slot.host.toggleTaskDone(slot.taskId)
      }

      CardAction {
        host: slot.host
        glyph: ""
        tip: "Move to the previous column"
        onTriggered: slot.host.shiftTask(slot.taskId, -1)
      }

      CardAction {
        host: slot.host
        glyph: ""
        tip: "Move to the next column"
        onTriggered: slot.host.shiftTask(slot.taskId, 1)
      }

      CardAction {
        host: slot.host
        glyph: ""
        tip: "Delete this task"
        danger: true
        onTriggered: slot.host.deleteTask(slot.taskId)
      }
    }

    // Drag and click share one area: a press that never moves opens the
    // task, a press that travels drags the card. The hover actions sit above
    // this area and take their own clicks first.
    MouseArea {
      id: dragArea
      anchors.fill: parent
      drag.target: surface
      drag.axis: Drag.XAndYAxis
      cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton

      onClicked: function(event) {
        if (event.button === Qt.RightButton) slot.host.duplicateTask(slot.taskId)
        else slot.host.openTaskId = slot.taskId
      }

      onReleased: {
        // A drop outside every lane leaves the card where it was; either way
        // the state reverts and the anchors put it back on its slot.
        if (surface.Drag.active) surface.Drag.drop()
      }
    }
  }
}
