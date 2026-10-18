import QtQuick
import Quickshell
import qs.Commons

PopupWindow {
    id: root

    property var target: null
    property var handle: null
    property string title: ""

    signal done

    anchor.item: root.target
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    anchor.adjustment: PopupAdjustment.Slide
    anchor.margins.top: 6
    grabFocus: true
    color: "transparent"
    implicitWidth: 264
    implicitHeight: 428
    mask: Region {
        item: card
    }

    onVisibleChanged: {
        if (!visible)
            done();
    }

    Rectangle {
        id: card

        x: 6
        y: 6
        width: parent.width - 12
        height: Math.min(menu.implicitHeight, 400) + 16
        radius: 20
        color: Theme.m3SurfaceContainer
        border.width: 1
        border.color: Theme.m3OutlineVariant

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: menu.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            TrayMenu {
                id: menu

                width: parent.width
                handle: root.handle
                title: root.title
                onDone: root.done()
            }
        }
    }
}
