import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// In-place look at a task's attachments. Opening them in an external viewer
// would mean dismissing the board, so the board shows them itself.
Item {
  id: viewer

  property var host: null

  signal closed()

  readonly property var images: host ? host.previewImages : []
  readonly property int index: host ? host.previewIndex : 0
  readonly property string current: index >= 0 && index < images.length ? String(images[index]) : ""

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.92)

    MouseArea {
      anchors.fill: parent
      onClicked: viewer.closed()
    }
  }

  Image {
    id: preview
    anchors.centerIn: parent
    width: Math.min(sourceSize.width, parent.width - Style.space(120))
    height: Math.min(sourceSize.height, parent.height - Style.space(120))
    source: viewer.current ? Util.fileUrl(viewer.current) : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true

    // Clicks on the image itself must not fall through to the dismiss layer.
    MouseArea { anchors.fill: parent; onClicked: {} }
  }

  Text {
    anchors.centerIn: parent
    visible: preview.status === Image.Error
    text: "Could not load\n" + viewer.current
    horizontalAlignment: Text.AlignHCenter
    color: host.muted
    font.family: host.fontFamily
    font.pixelSize: Style.font.body
  }

  // ------------------------------------------------------------- chrome

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.space(18)
    text: Model.fileName(viewer.current)
      + (viewer.images.length > 1 ? "   " + (viewer.index + 1) + " / " + viewer.images.length : "")
    color: host.muted
    font.family: host.fontFamily
    font.pixelSize: Style.font.caption
  }

  Button {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(18)
    anchors.verticalCenter: parent.verticalCenter
    visible: viewer.images.length > 1
    iconText: ""
    iconSize: Style.font.heading
    tooltipText: "Previous image"
    foreground: host.foreground
    onClicked: host.stepPreview(-1)
  }

  Button {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(18)
    anchors.verticalCenter: parent.verticalCenter
    visible: viewer.images.length > 1
    iconText: ""
    iconSize: Style.font.heading
    tooltipText: "Next image"
    foreground: host.foreground
    onClicked: host.stepPreview(1)
  }

  Row {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(12)
    spacing: Style.spacing.xs

    Button {
      iconText: ""
      bordered: true
      tooltipText: "Open in the default image viewer"
      foreground: host.foreground
      onClicked: host.openExternal(viewer.current)
    }

    Button {
      iconText: ""
      bordered: true
      tooltipText: "Close (Esc)"
      foreground: host.foreground
      onClicked: viewer.closed()
    }
  }
}
