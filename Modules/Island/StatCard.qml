import QtQuick
import qs.Commons

Rectangle {
    id: card

    property string label: ""
    property string detail: ""
    property string value: ""
    property var series: []
    property var series2: []
    property real maxValue: 1
    property bool auto: false

    radius: 18
    color: Theme.m3SurfaceContainerHigh

    Text {
        id: valueText

        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 12
        text: card.value
        color: Theme.m3OnSurface
        font.family: Theme.fontUi
        font.pixelSize: 16
        font.weight: Font.DemiBold
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.right: valueText.left
        anchors.rightMargin: 8
        anchors.verticalCenter: valueText.verticalCenter
        text: card.detail.length > 0 ? card.label + "  " + card.detail : card.label
        elide: Text.ElideRight
        color: Theme.m3OnSurfaceVariant
        font.family: Theme.fontUi
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    Sparkline {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: Math.max(14, parent.height - 44)
        values: card.series
        values2: card.series2
        maxValue: card.maxValue
        auto: card.auto
    }
}
