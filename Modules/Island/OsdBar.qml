import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: root

    readonly property bool isVolume: ShellState.osdKind === "volume"
    readonly property real top: isVolume ? Audio.maxVolume : 1
    readonly property real level: Math.max(0, Math.min(top, isVolume ? Audio.volume : Brightness.value))
    readonly property bool muted: isVolume && Audio.muted

    Spring {
        id: fill

        target: root.level / root.top
        token: Motion.effectsFast
        epsilon: 0.0005
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 14

        Text {
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
            text: !root.isVolume ? "\uf185" : root.muted ? "\uf026" : root.level > 0.5 ? "\uf028" : "\uf027"
            color: Theme.m3Primary
            font.family: Theme.fontIcon
            font.pixelSize: 17
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 10
            radius: 5
            color: Theme.m3SurfaceContainerHighest

            Rectangle {
                width: Math.min(parent.width, Math.max(parent.height, parent.width * fill.value))
                height: parent.height
                radius: parent.radius
                color: root.muted ? Theme.m3OutlineVariant : Theme.m3Primary
            }
        }

        Text {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.level * 100) + "%"
            color: Theme.m3OnSurface
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
}
