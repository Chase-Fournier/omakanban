import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One lane. Owns its header, its scrolling stack of cards, and the drop
// target that catches cards dragged in from other lanes.
Item {
  id: lane

  property var host: null
  property var columnData: ({})
  property int columnIndex: 0

  readonly property string columnId: columnData ? String(columnData.id) : ""
  readonly property string columnName: columnData ? String(columnData.name) : ""
  readonly property color accent: columnData && columnData.color
    ? columnData.color : Util.alpha(host.foreground, 0.35)
  readonly property bool collapsed: columnData ? columnData.collapsed === true : false
  readonly property var tasks: host && host.board ? Model.tasksIn(host.board, columnId, host.filterText) : []
  readonly property int totalCount: host && host.board ? Model.countIn(host.board, columnId) : 0
  readonly property int wipLimit: columnData ? Math.max(0, columnData.wip || 0) : 0
  readonly property bool overWip: wipLimit > 0 && totalCount > wipLimit
  readonly property bool isLast: host && host.board ? columnIndex === host.board.columns.length - 1 : false

  width: collapsed ? Style.space(46) : host.columnWidth

  // ------------------------------------------------------------- collapsed

  Loader {
    anchors.fill: parent
    active: lane.collapsed

    sourceComponent: BorderSurface {
      color: host.laneFill
      radius: Style.cornerRadius
      borderSpec: Border.flat(lane.accent, Math.max(1, Style.space(1)))

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: host.patchColumn(lane.columnId, { collapsed: false })
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.sm

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          color: lane.accent
          font.family: host.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: String(lane.totalCount)
          color: host.muted
          font.family: host.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Vertical lane name, so a collapsed lane is still identifiable.
      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Style.space(60)
        rotation: 90
        text: lane.columnName
        color: host.muted
        font.family: host.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // ------------------------------------------------------------- expanded

  Loader {
    anchors.fill: parent
    active: !lane.collapsed
    sourceComponent: expandedLane
  }

  Component {
    id: expandedLane

    Item {
      anchors.fill: parent

      Column {
        anchors.fill: parent
        spacing: Style.spacing.sm

        // ---------------------------------------------------------- header
        Item {
          id: laneHeader
          width: parent.width
          height: Style.spacing.controlHeight + Style.space(4)

          Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(2, Style.space(3))
            height: Style.font.subtitle
            radius: width / 2
            color: lane.accent
          }

          Text {
            id: laneTitle
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - laneActions.width - Style.spacing.lg - Style.spacing.sm)
            text: lane.columnName
            elide: Text.ElideRight
            color: host.foreground
            font.family: host.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Row {
            id: laneActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: lane.wipLimit > 0 ? (lane.totalCount + "/" + lane.wipLimit) : String(lane.totalCount)
              color: lane.overWip ? Color.urgent : host.muted
              font.family: host.fontFamily
              font.pixelSize: Style.font.caption
              rightPadding: Style.spacing.xs
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              iconSize: Style.font.bodySmall
              horizontalPadding: Style.spacing.xs
              verticalPadding: Style.spacing.xxs
              tooltipText: "Add a task here"
              foreground: host.muted
              onClicked: host.createTask(lane.columnId)
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              iconSize: Style.font.bodySmall
              horizontalPadding: Style.spacing.xs
              verticalPadding: Style.spacing.xxs
              tooltipText: "Column settings"
              foreground: host.muted
              onClicked: host.editingColumnId = lane.columnId
            }
          }
        }

        // ----------------------------------------------------------- cards
        Item {
          id: cardArea
          width: parent.width
          height: parent.height - laneHeader.height - addRow.height - Style.spacing.sm * 2

          BorderSurface {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: dropTarget.containsDrag ? Util.alpha(lane.accent, 0.12) : host.laneFill
            borderSpec: dropTarget.containsDrag
              ? Border.flat(lane.accent, Math.max(1, Style.space(1)))
              : Border.none()

            Behavior on color { ColorAnimation { duration: 120 } }
          }

          // Catches cards dragged from anywhere on the board. Where the card
          // lands is decided by which gap the pointer is nearest, so a drop
          // reorders as well as re-columns.
          DropArea {
            id: dropTarget
            anchors.fill: parent
            keys: ["chase.kanban.task"]

            onDropped: function(drop) {
              var taskId = drop.source && drop.source.taskId ? String(drop.source.taskId) : ""
              if (!taskId) { drop.accepted = false; return }
              var before = lane.insertionBefore(drop.y - Style.spacing.xs + cardFlick.contentY, taskId)
              drop.accept(Qt.MoveAction)
              // Deferred: moving the task rebuilds every lane's delegates, and
              // doing that inside the drop handler destroys the card that is
              // still mid-release.
              Qt.callLater(host.moveTask, taskId, lane.columnId, before)
            }
          }

          Flickable {
            id: cardFlick
            anchors.fill: parent
            anchors.margins: Style.spacing.xs
            contentWidth: width
            contentHeight: cardStack.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: cardStack
              width: cardFlick.width
              spacing: Style.spacing.md

              Repeater {
                id: cardRepeater
                model: lane.tasks

                TaskCard {
                  required property var modelData
                  required property int index

                  host: lane.host
                  column: lane
                  taskData: modelData
                  cardIndex: index
                  width: cardStack.width
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: lane.tasks.length === 0
            text: host.filterText ? "No matches" : "Drop tasks here"
            color: Util.alpha(host.foreground, 0.28)
            font.family: host.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ------------------------------------------------------- add a task
        Item {
          id: addRow
          width: parent.width
          height: Style.spacing.controlHeight

          Button {
            anchors.fill: parent
            leftAlign: true
            iconText: ""
            iconSize: Style.font.bodySmall
            text: "Add a task"
            fontSize: Style.font.bodySmall
            foreground: host.muted
            onClicked: host.createTask(lane.columnId)
          }
        }
      }
    }
  }

  // Live card items, keyed by task id, so a drop can be resolved against
  // where the cards actually sit rather than an assumed row height.
  property var cardItems: ({})

  function registerCard(taskId, item) {
    if (!taskId) return
    cardItems[taskId] = item
  }

  function unregisterCard(taskId) {
    if (taskId && cardItems[taskId] !== undefined) delete cardItems[taskId]
  }

  // Which card the dropped one should land in front of. `y` is in card-stack
  // coordinates; a drop past the last card returns "" and appends.
  function insertionBefore(y, draggedId) {
    for (var i = 0; i < lane.tasks.length; i++) {
      var id = lane.tasks[i].id
      if (id === draggedId) continue
      var item = cardItems[id]
      if (!item) continue
      if (y < item.y + item.height / 2) return id
    }
    return ""
  }
}
