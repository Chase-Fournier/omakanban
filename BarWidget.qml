import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry for the board. Left click opens it, middle click drops straight
// into a new task, right click jumps to the board file's folder.
//
// The widget reads board.json itself rather than asking the overlay: the
// overlay is only mounted once it has been summoned, and the count has to be
// right from the moment the bar paints.
BarWidget {
  id: root
  moduleName: "chase.kanban"

  readonly property string home: Quickshell.env("HOME")
  readonly property string boardPath: home + "/.local/share/omarchy/kanban/board.json"

  readonly property string glyph: setting("icon", "")
  readonly property bool showCount: setting("showCount", true) === true
  readonly property string countColumn: String(setting("countColumn", ""))

  property var board: Model.defaultBoard()
  property bool loaded: false

  readonly property int count: loaded ? Model.countInNamed(board, countColumn) : 0
  readonly property string countText: showCount && count > 0 ? String(count) : ""

  function refresh() {
    boardFile.reload()
  }

  function openBoard(payload) {
    if (!root.bar || !root.bar.shell) return
    root.bar.shell.summon("chase.kanban", payload || "{}")
  }

  function toggleBoard() {
    if (!root.bar || !root.bar.shell) return
    root.bar.shell.toggle("chase.kanban", "{}")
  }

  function tooltip() {
    if (!loaded) return "Kanban"
    var lines = []
    for (var i = 0; i < board.columns.length; i++) {
      var col = board.columns[i]
      lines.push(col.name + ": " + Model.countIn(board, col.id))
    }
    return "Kanban — " + Model.openCount(board) + " open\n" + lines.join("   ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: boardFile
    path: root.boardPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parse(text())
      if (parsed) root.board = parsed
      root.loaded = true
    }
    onLoadFailed: root.loaded = true
    onFileChanged: reload()
  }

  IpcHandler {
    target: "kanban-widget"

    function refresh(): void { root.broadcast("refresh") }
    function count(): string { return String(root.count) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? root.glyph : (root.glyph + (root.countText ? " " + root.countText : ""))
    tooltipText: root.tooltip()
    hasVisualContent: true

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.openBoard('{"newTask":true}')
      else if (b === Qt.RightButton) Quickshell.execDetached(["xdg-open", root.home + "/.local/share/omarchy/kanban"])
      else root.toggleBoard()
    }
  }
}
