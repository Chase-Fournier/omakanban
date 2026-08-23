import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Fullscreen kanban board. Summoned through the shell:
//
//   omarchy-shell shell toggle chase.kanban '{}'
//
// The overlay owns all board state and file IO; BoardColumn and TaskCard are
// pure views that call back into the functions defined here. Every mutation
// goes through commit(), which reassigns `board` (so bindings re-evaluate)
// and schedules the debounced write.
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string dataDir: home + "/.local/share/omarchy/kanban"
  readonly property string boardPath: dataDir + "/board.json"
  readonly property string imagesDir: dataDir + "/images"

  property bool opened: false
  property var board: Model.defaultBoard()
  property bool loaded: false
  property bool loadError: false
  property string filterText: ""

  // Task detail / settings / column editor are modal over the board.
  property string openTaskId: ""
  property string editingColumnId: ""
  property bool settingsOpen: false

  // Set while zenity owns the screen. The layer surface has to let go of the
  // keyboard for the duration or the file chooser cannot be typed into.
  property bool externalDialogOpen: false

  readonly property var settings: board && board.settings ? board.settings : Model.defaultSettings()
  readonly property int columnWidth: Math.round(Style.spaceReal(settings.columnWidth))

  // ------------------------------------------------------------ board size
  //
  // A summoned overlay belongs on the screen you are looking at, and how big
  // it should be there depends on that screen. Sizes are stored per screen,
  // keyed by logical resolution.

  property var targetScreen: null

  function resolveScreen() {
    var name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    if (!name) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === name) return screens[i]
    }
    return null
  }

  readonly property real screenWidth: targetScreen ? targetScreen.width : 0
  readonly property real screenHeight: targetScreen ? targetScreen.height : 0
  readonly property string screenKey: screenWidth > 0 && screenHeight > 0
    ? (Math.round(screenWidth) + "x" + Math.round(screenHeight)) : ""

  // What the lanes actually need: the columns themselves, the gaps between
  // them, the add-a-column strip, and the sheet's own padding.
  readonly property real contentWidthNeeded: {
    var columns = root.board && root.board.columns ? root.board.columns : []
    var total = Style.space(52) + Style.spacing.panelPadding * 2 + Style.space(6)
    for (var i = 0; i < columns.length; i++) {
      total += (columns[i].collapsed ? Style.space(46) : root.columnWidth) + Style.spacing.md
    }
    return total
  }

  // A comfortable board height in absolute terms. On a tall screen this is
  // well under the cap; on a short one the cap wins.
  readonly property real contentHeightWanted: Style.space(1020)

  // Auto size for a screen with no stored override, as a percentage so the
  // slider and the stored value speak the same units.
  readonly property int autoWidth: screenWidth > 0
    ? Math.max(30, Math.min(96, Math.round(contentWidthNeeded / screenWidth * 100))) : 90
  readonly property int autoHeight: screenHeight > 0
    ? Math.max(30, Math.min(94, Math.round(contentHeightWanted / screenHeight * 100))) : 88

  readonly property var storedSize: root.screenKey ? Model.screenSize(root.board, root.screenKey) : null
  readonly property bool sizeIsAuto: !storedSize
    || (storedSize.width === 0 && storedSize.height === 0)
  readonly property int boardWidthPercent: storedSize && storedSize.width > 0
    ? storedSize.width : autoWidth
  readonly property int boardHeightPercent: storedSize && storedSize.height > 0
    ? storedSize.height : autoHeight

  function setBoardSize(patch) {
    if (!root.screenKey) return
    root.commit(Model.setScreenSize(root.board, root.screenKey, patch))
  }

  function resetBoardSize() {
    if (!root.screenKey) return
    root.commit(Model.clearScreenSize(root.board, root.screenKey))
  }

  // Surface tokens. The board shares [menu] so a theme that styles the
  // launcher styles the board too.
  readonly property color surface: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color muted: Util.alpha(foreground, 0.55)
  readonly property color faint: Util.alpha(foreground, 0.10)
  readonly property color laneFill: Util.alpha(foreground, 0.05)
  readonly property var cardBorderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    var payload = {}
    try { payload = payloadJson ? JSON.parse(payloadJson) : {} } catch (e) { payload = {} }

    root.targetScreen = root.resolveScreen()
    root.opened = true
    root.filterText = ""
    root.settingsOpen = false
    root.editingColumnId = ""
    boardFile.reload()

    if (payload.newTask === true || payload.add === true) Qt.callLater(function() { root.createTask("") })
    else if (payload.task) Qt.callLater(function() { root.openTaskId = String(payload.task) })
    else if (payload.column) Qt.callLater(function() { root.editingColumnId = String(payload.column) })
    else if (payload.settings === true) Qt.callLater(function() { root.settingsOpen = true })
    else root.openTaskId = ""

    root.refocus()
  }

  function close() {
    root.openTaskId = ""
    root.settingsOpen = false
    root.editingColumnId = ""
    root.flushSave()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ------------------------------------------------------------- persistence

  function loadBoard(raw) {
    var parsed = Model.parse(raw)
    if (parsed === null) {
      // Unreadable JSON: show an empty board but never write over the file,
      // so a hand-edit with a typo in it stays recoverable.
      root.loadError = true
      root.loaded = true
      return
    }
    root.loadError = false
    root.board = parsed
    root.loaded = true
    Qt.callLater(root.migrateSize)
  }

  // Runs once, after the first load that happens with a screen resolved: the
  // old single boardWidth/boardHeight becomes this screen's entry.
  function migrateSize() {
    if (!root.loaded || root.loadError || !root.screenKey) return
    var next = Model.migrateLegacySize(root.board, root.screenKey)
    if (next !== root.board) root.commit(next)
  }

  function commit(next) {
    if (!next || next === root.board) return
    root.board = next
    if (root.loadError) return
    saveTimer.restart()
  }

  function flushSave() {
    if (!root.loaded || root.loadError) return
    saveTimer.stop()
    boardFile.setText(Model.serialize(root.board))
  }

  // --------------------------------------------------------------- actions

  function createTask(columnId) {
    var target = columnId || (root.board.columns.length ? root.board.columns[0].id : "")
    if (!target) return
    var result = Model.addTask(root.board, target, { title: "New task" })
    root.commit(result.board)
    root.openTaskId = result.id
  }

  function patchTask(taskId, patch) {
    root.commit(Model.updateTask(root.board, taskId, patch))
  }

  function deleteTask(taskId) {
    var t = Model.task(root.board, taskId)
    if (!t) return
    if (root.settings.confirmDelete) {
      root.askConfirm("Delete \"" + t.title + "\"?", "Delete", function() {
        if (root.openTaskId === taskId) root.openTaskId = ""
        root.commit(Model.removeTask(root.board, taskId))
      })
      return
    }
    if (root.openTaskId === taskId) root.openTaskId = ""
    root.commit(Model.removeTask(root.board, taskId))
  }

  function toggleTaskDone(taskId) {
    var t = Model.task(root.board, taskId)
    if (!t) return
    root.patchTask(taskId, { done: !t.done })
  }

  function moveTask(taskId, columnId, beforeTaskId) {
    root.commit(Model.moveTask(root.board, taskId, columnId, beforeTaskId || ""))
  }

  function shiftTask(taskId, delta) {
    root.commit(Model.shiftTask(root.board, taskId, delta))
  }

  function reorderTask(taskId, delta) {
    root.commit(Model.reorderTask(root.board, taskId, delta))
  }

  function duplicateTask(taskId) {
    var result = Model.duplicateTask(root.board, taskId)
    root.commit(result.board)
  }

  function addColumn() {
    var next = Model.addColumn(root.board, "New column")
    root.commit(next)
    root.editingColumnId = next.columns[next.columns.length - 1].id
  }

  function patchColumn(columnId, patch) {
    root.commit(Model.updateColumn(root.board, columnId, patch))
  }

  function moveColumn(columnId, delta) {
    root.commit(Model.moveColumn(root.board, columnId, delta))
  }

  function deleteColumn(columnId) {
    if (root.board.columns.length <= 1) return
    var col = Model.column(root.board, columnId)
    if (!col) return
    var count = Model.countIn(root.board, columnId)
    var message = count > 0
      ? "Delete \"" + col.name + "\" and its " + count + (count === 1 ? " task?" : " tasks?")
      : "Delete \"" + col.name + "\"?"
    root.askConfirm(message, "Delete", function() {
      root.editingColumnId = ""
      root.commit(Model.removeColumn(root.board, columnId, ""))
    })
  }

  function clearColumn(columnId) {
    var col = Model.column(root.board, columnId)
    if (!col || Model.countIn(root.board, columnId) === 0) return
    root.askConfirm("Remove every task in \"" + col.name + "\"?", "Remove", function() {
      root.commit(Model.clearColumn(root.board, columnId))
    })
  }

  function sortColumn(columnId, mode) {
    root.commit(Model.sortColumn(root.board, columnId, mode))
  }

  function archiveDone() {
    var count = Model.doneCount(root.board)
    if (count === 0) { root.notify("Nothing is finished yet"); return }
    root.askConfirm("Remove " + count + (count === 1 ? " finished task" : " finished tasks")
      + " from the board?", "Remove", function() {
      root.commit(Model.archiveDone(root.board))
    })
  }

  function patchSettings(patch) {
    root.commit(Model.updateSettings(root.board, patch))
  }

  function openExternal(target) {
    var value = String(target || "").trim()
    if (!value) return
    if (value.charAt(0) === "~") value = root.home + value.slice(1)
    // The overlay sits on the Wayland overlay layer with an exclusive
    // keyboard grab, so whatever xdg-open launches would open behind it and
    // be unreachable. Step out of the way first.
    root.close()
    Quickshell.execDetached(["xdg-open", value])
  }

  function revealDataDir() {
    root.close()
    Quickshell.execDetached(["xdg-open", root.dataDir])
  }

  // Images preview in place instead — leaving the board to look at an
  // attachment loses your spot for no reason.
  property var previewImages: []
  property int previewIndex: 0
  readonly property bool previewOpen: previewImages.length > 0

  function previewImage(images, index) {
    if (!images || images.length === 0) return
    root.previewImages = images
    root.previewIndex = Math.max(0, Math.min(images.length - 1, index))
  }

  function previewTask(taskId) {
    var t = Model.task(root.board, String(taskId || ""))
    if (!t || t.images.length === 0) return "no images"
    root.previewImage(t.images, 0)
    return "ok"
  }

  function stepPreview(delta) {
    if (!root.previewOpen) return
    var count = root.previewImages.length
    root.previewIndex = (root.previewIndex + delta + count) % count
  }

  function closePreview() {
    root.previewImages = []
    root.previewIndex = 0
  }

  // ------------------------------------------------------- attachment intake

  // Where a pasted or chosen image lands. Callback is invoked with the
  // resolved path so the task dialog can attach it.
  property var pendingAttach: null

  function attachClipboardImage(taskId) {
    root.pendingAttach = taskId
    clipboardImageProc.command = ["bash", "-c",
      "set -euo pipefail; "
      + "mkdir -p \"$1\"; "
      + "mime=$(wl-paste --list-types 2>/dev/null | grep -m1 '^image/' || true); "
      + "[ -n \"$mime\" ] || { echo 'ERR:no image on the clipboard'; exit 0; }; "
      + "ext=${mime#image/}; case \"$ext\" in jpeg) ext=jpg;; svg+xml) ext=svg;; esac; "
      + "out=\"$1/paste-$(date +%Y%m%d-%H%M%S)-$RANDOM.$ext\"; "
      + "wl-paste --type \"$mime\" > \"$out\"; "
      + "[ -s \"$out\" ] || { rm -f \"$out\"; echo 'ERR:clipboard image was empty'; exit 0; }; "
      + "echo \"OK:$out\"",
      "bash", root.imagesDir]
    clipboardImageProc.running = true
  }

  function browseForImage(taskId) {
    root.pendingAttach = taskId
    root.externalDialogOpen = true
    fileDialogProc.command = ["bash", "-c",
      "zenity --file-selection --title='Attach an image' "
      + "--file-filter='Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.avif' "
      + "--file-filter='All files | *' 2>/dev/null || true"]
    fileDialogProc.running = true
  }

  function finishAttach(path) {
    var taskId = root.pendingAttach
    root.pendingAttach = null
    var clean = String(path || "").trim()
    if (!taskId || !clean) return
    var t = Model.task(root.board, taskId)
    if (!t) return
    var images = t.images.slice()
    if (images.indexOf(clean) !== -1) return
    images.push(clean)
    root.patchTask(taskId, { images: images })
  }

  function notify(message) {
    root.toastText = String(message || "")
    if (root.toastText) toastTimer.restart()
  }

  property string toastText: ""

  // --------------------------------------------------------------- confirm

  property string confirmMessage: ""
  property string confirmAction: "Confirm"
  property var confirmCallback: null
  readonly property bool confirmOpen: confirmMessage !== ""

  function refocus() {
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function askConfirm(message, actionText, callback) {
    root.confirmMessage = message
    root.confirmAction = actionText || "Confirm"
    root.confirmCallback = callback
    confirmDialog.selectedIndex = 1
    root.refocus()
  }

  function resolveConfirm(accepted) {
    var callback = root.confirmCallback
    root.confirmMessage = ""
    root.confirmCallback = null
    if (accepted && typeof callback === "function") callback()
    root.refocus()
  }

  // Anything modal is layered over the board and swallows board-level keys.
  readonly property bool modalOpen: confirmOpen || previewOpen || openTaskId !== ""
    || settingsOpen || editingColumnId !== ""

  // ------------------------------------------------------------------- IO

  Component.onCompleted: ensureDirsProc.running = true

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.imagesDir]
    onExited: boardFile.reload()
  }

  // Only this plugin writes the board, so there is no watch to fight with our
  // own saves; open() re-reads instead, which also picks up hand edits.
  FileView {
    id: boardFile
    path: root.boardPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadBoard(text())
    onLoadFailed: root.loadBoard("")
  }

  Timer {
    id: saveTimer
    interval: 350
    repeat: false
    onTriggered: root.flushSave()
  }

  Timer {
    id: toastTimer
    interval: 2600
    repeat: false
    onTriggered: root.toastText = ""
  }

  Process {
    id: clipboardImageProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim()
        if (line.indexOf("OK:") === 0) root.finishAttach(line.slice(3))
        else if (line.indexOf("ERR:") === 0) { root.pendingAttach = null; root.notify(line.slice(4)) }
        else { root.pendingAttach = null; root.notify("Could not read an image from the clipboard") }
      }
    }
  }

  Process {
    id: fileDialogProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishAttach(text)
    }
    onExited: {
      root.externalDialogOpen = false
      if (root.opened) root.refocus()
    }
  }

  IpcHandler {
    target: "kanban"

    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function add(title: string): string {
      if (!root.loaded) return "not ready"
      var columnId = root.board.columns.length ? root.board.columns[0].id : ""
      if (!columnId) return "no columns"
      var result = Model.addTask(root.board, columnId, { title: title })
      root.commit(result.board)
      root.flushSave()
      return result.id
    }
    function count(): string { return String(Model.openCount(root.board)) }
    function settings(): void { root.open('{"settings":true}') }
  }

  // ------------------------------------------------------------------- UI

  PanelWindow {
    id: panel
    // Hidden, not closed, while a file chooser runs: an overlay-layer surface
    // would otherwise cover the very dialog it asked for.
    visible: root.opened && !root.externalDialogOpen
    // Resolved while closed, so summoning lands on the focused output rather
    // than whichever screen Quickshell happens to list first.
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-kanban"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.externalDialogOpen ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.round(panel.width * root.boardWidthPercent / 100)
      height: Math.round(panel.height * root.boardHeightPercent / 100)

      Behavior on width { NumberAnimation { duration: 90 } }
      Behavior on height { NumberAnimation { duration: 90 } }
      radius: Style.cornerRadius
      color: root.surface
      borderSpec: root.cardBorderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.confirmOpen) {
            if (confirmDialog.handleKey(event)) event.accepted = true
            return
          }
          if (root.previewOpen) {
            if (event.key === Qt.Key_Escape) root.closePreview()
            else if (event.key === Qt.Key_Left) root.stepPreview(-1)
            else if (event.key === Qt.Key_Right) root.stepPreview(1)
            event.accepted = true
            return
          }
          if (root.modalOpen) return

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.filterText = ""
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            searchField.forceActiveFocus()
            event.accepted = true
          } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
            root.createTask("")
            event.accepted = true
          } else if (event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) {
            root.settingsOpen = true
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            // Typing anywhere on the board filters it, the way the launcher
            // behaves — no need to aim at the search box first.
            root.filterText += event.text
            searchField.forceActiveFocus()
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        // ------------------------------------------------------------ header
        Item {
          id: header
          width: parent.width
          height: Math.max(Style.spacing.controlHeight + Style.space(8), headerRight.implicitHeight)

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            Text {
              text: root.settings.boardTitle
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              text: root.loadError
                ? "board.json could not be parsed — nothing will be saved"
                : Model.openCount(root.board) + " open · " + root.board.tasks.length + " total"
              color: root.loadError ? Color.urgent : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            TextField {
              id: searchField
              width: Style.space(260)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "Search tasks…"
              text: root.filterText
              onTextChanged: if (text !== root.filterText) root.filterText = text
              Keys.onEscapePressed: {
                if (root.filterText) root.filterText = ""
                keyCatcher.forceActiveFocus()
              }
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              text: "Task"
              bordered: true
              tooltipText: "Add a task (Ctrl+N)"
              foreground: root.foreground
              onClicked: root.createTask("")
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              text: "Column"
              bordered: true
              tooltipText: "Add a column"
              foreground: root.foreground
              onClicked: root.addColumn()
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: "Board settings (Ctrl+,)"
              foreground: root.foreground
              onClicked: root.settingsOpen = true
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: ""
              tooltipText: "Close (Esc)"
              foreground: root.foreground
              onClicked: root.close()
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.faint
        }

        // ------------------------------------------------------------- lanes
        Flickable {
          id: lanes
          width: parent.width
          height: parent.height - header.height - Style.spacing.panelGap * 2 - Math.max(1, Style.space(1))
          contentWidth: laneRow.width
          contentHeight: height
          clip: true
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds

          Row {
            id: laneRow
            height: lanes.height
            spacing: Style.spacing.md

            Repeater {
              model: root.board.columns

              BoardColumn {
                required property var modelData
                required property int index

                host: root
                columnData: modelData
                columnIndex: index
                height: lanes.height
              }
            }

            // Trailing "add a column" affordance: a board with one column
            // should suggest the next one without a trip to the header.
            Item {
              width: Style.space(52)
              height: lanes.height

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Style.space(2)
                iconText: ""
                tooltipText: "Add a column"
                foreground: root.muted
                onClicked: root.addColumn()
              }
            }
          }
        }
      }

      // ------------------------------------------------------------ overlays

      // Cards reparent here while dragging so they float above every lane
      // instead of being clipped by the one they started in.
      Item {
        id: dragLayer
        anchors.fill: parent
        z: 50
      }

      Text {
        id: toast
        visible: root.toastText !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(24)
        z: 60
        text: root.toastText
        color: Color.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Loader {
        id: taskDialogLoader
        anchors.fill: parent
        z: 100
        active: root.openTaskId !== ""
        sourceComponent: TaskDialog {
          host: root
          taskId: root.openTaskId
          onClosed: {
            root.openTaskId = ""
            root.refocus()
          }
        }
      }

      Loader {
        id: columnDialogLoader
        anchors.fill: parent
        z: 100
        active: root.editingColumnId !== ""
        sourceComponent: ColumnDialog {
          host: root
          columnId: root.editingColumnId
          onClosed: {
            root.editingColumnId = ""
            root.refocus()
          }
        }
      }

      Loader {
        id: settingsLoader
        anchors.fill: parent
        z: 100
        active: root.settingsOpen
        sourceComponent: SettingsDialog {
          host: root
          onClosed: {
            root.settingsOpen = false
            root.refocus()
          }
        }
      }

      Loader {
        anchors.fill: parent
        z: 150
        active: root.previewOpen
        sourceComponent: ImageViewer {
          host: root
          onClosed: {
            root.closePreview()
            root.refocus()
          }
        }
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 200
        opened: root.confirmOpen
        message: root.confirmMessage
        confirmText: root.confirmAction
        background: root.surface
        foreground: root.foreground
        scrim: root.scrim
        selectedBackground: Color.menu.selectedBackground
        selectedText: Color.menu.selectedText
        fontFamily: root.fontFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.resolveConfirm(false)
        onConfirmed: root.resolveConfirm(true)
      }
    }
  }

  // The drag layer lives inside the card; expose it so TaskCard can reparent
  // into it without reaching through five levels of ids.
  readonly property Item dragHost: dragLayer
}
