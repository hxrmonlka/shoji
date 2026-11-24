import QtQuick
import qs.Commons

Item {
    id: root

    readonly property int count: Notifs.count
    readonly property bool dnd: Notifs.dnd
    readonly property bool hasCount: count > 0
    property string label: "1"

    implicitWidth: 22
    implicitHeight: 22
    scale: press.value

    function format(n) {
        return n > 9 ? "9+" : String(n);
    }

    onCountChanged: {
        if (count <= 0)
            return;
        label = format(count);
        if (badgePresence.value > 0.5) {
            pop.value = 1.25;
            pop.velocity = 0;
            pop.kick();
        }
    }

    Component.onCompleted: {
        if (count > 0)
            label = format(count);
    }

    Spring {
        id: press

        target: area.pressed ? 0.92 : 1
        token: Motion.spatialFast
        epsilon: 0.001
    }

    Spring {
        id: slash

        target: root.dnd ? 1 : 0
        token: Motion.effectsDefault
        epsilon: 0.002
    }

    Spring {
        id: badgePresence

        target: root.hasCount ? 1 : 0
        token: Motion.spatialFast
        epsilon: 0.002
    }

    Spring {
        id: pop

        target: 1
        value: 1
        token: Motion.impact
        epsilon: 0.001
    }

    ColorSpring {
        id: iconTint

        target: root.dnd ? Theme.m3Tertiary : root.hasCount ? Theme.m3OnSurface : Theme.m3OnSurfaceVariant
    }

    ColorSpring {
        id: badgeTint

        target: root.dnd ? Theme.m3SurfaceContainerHighest : Theme.m3Primary
    }

    ColorSpring {
        id: badgeText

        target: root.dnd ? Theme.m3OnSurfaceVariant : Theme.m3OnPrimary
    }

    Text {
        id: bell

        anchors.centerIn: parent
        text: "\uf0f3"
        color: iconTint.color
        opacity: 1 - Motion.clamp01(slash.value)
        font.family: Theme.fontIcon
        font.pixelSize: 15
    }

    Text {
        anchors.centerIn: parent
        text: "\uf1f6"
        color: iconTint.color
        opacity: Motion.clamp01(slash.value)
        font.family: Theme.fontIcon
        font.pixelSize: 15
    }

    Rectangle {
        id: badge

        readonly property real presence: Motion.clamp01(badgePresence.value)

        x: bell.x + bell.width - 5
        y: 0
        width: Math.max(13, badgeLabel.implicitWidth + 8)
        height: 13
        radius: height / 2
        color: badgeTint.color
        border.width: 1
        border.color: Motion.mix(Qt.rgba(0, 0, 0, 0), Theme.m3OutlineVariant, Motion.clamp01(slash.value))
        opacity: presence
        visible: presence > 0
        scale: (0.6 + 0.4 * presence) * pop.value
        transformOrigin: Item.BottomLeft

        Text {
            id: badgeLabel

            anchors.centerIn: parent
            text: root.label
            color: badgeText.color
            font.family: Theme.fontUi
            font.pixelSize: 9
            font.weight: Font.Bold
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellState.openControl()
    }
}
