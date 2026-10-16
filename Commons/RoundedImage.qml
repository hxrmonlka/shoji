import QtQuick
import QtQuick.Effects

Item {
    id: root

    property alias source: img.source
    property alias sourceSize: img.sourceSize
    property alias status: img.status
    property real radius: 12
    property int fillMode: Image.PreserveAspectCrop

    Image {
        id: img

        anchors.fill: parent
        fillMode: root.fillMode
        asynchronous: true
        smooth: true
        visible: false
    }

    Item {
        id: mask

        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: "black"
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
