import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
    id: root

    property color color: Theme.m3Primary
    property int kind: 0
    property real size: 18
    readonly property string outline: MaterialShapes.build(kind)

    implicitWidth: 20
    implicitHeight: 20

    Item {
        id: holder

        anchors.centerIn: parent
        width: root.size
        height: root.size
        scale: 0.4
        opacity: 0

        NumberAnimation on scale {
            from: 0.4
            to: 1
            duration: 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1]
        }

        NumberAnimation on opacity {
            from: 0
            to: 1
            duration: 90
        }

        Item {
            width: 100
            height: 100
            scale: root.size / 100
            transformOrigin: Item.TopLeft

            Shape {
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 4
                layer.smooth: true
                layer.mipmap: true

                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.color

                    PathSvg {
                        path: root.outline
                    }
                }
            }
        }
    }
}
