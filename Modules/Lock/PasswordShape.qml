import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
    id: root

    property color color: Theme.m3Primary
    property int kind: 0
    property real size: 18

    implicitWidth: 20
    implicitHeight: 20

    function polar(fn, n) {
        let d = "";
        for (let i = 0; i < n; i++) {
            const t = i / n * Math.PI * 2;
            const r = fn(t);
            const x = 50 + 46 * r * Math.sin(t);
            const y = 50 - 46 * r * Math.cos(t);
            d += (i === 0 ? "M" : "L") + x.toFixed(2) + " " + y.toFixed(2) + " ";
        }
        return d + "Z";
    }

    function rounded(pts, rad) {
        const P = pts.map(p => [50 + 46 * p[0], 50 + 46 * p[1]]);
        const n = P.length;
        const cut = [];
        for (let i = 0; i < n; i++) {
            const p = P[i];
            const a = P[(i + n - 1) % n];
            const b = P[(i + 1) % n];
            const la = Math.hypot(a[0] - p[0], a[1] - p[1]);
            const lb = Math.hypot(b[0] - p[0], b[1] - p[1]);
            const d = Math.min(rad * 46, la / 2, lb / 2);
            cut.push([[p[0] + (a[0] - p[0]) / la * d, p[1] + (a[1] - p[1]) / la * d], p, [p[0] + (b[0] - p[0]) / lb * d, p[1] + (b[1] - p[1]) / lb * d]]);
        }
        let s = "M" + cut[0][2][0].toFixed(2) + " " + cut[0][2][1].toFixed(2) + " ";
        for (let i = 1; i <= n; i++) {
            const c = cut[i % n];
            s += "L" + c[0][0].toFixed(2) + " " + c[0][1].toFixed(2) + " Q" + c[1][0].toFixed(2) + " " + c[1][1].toFixed(2) + " " + c[2][0].toFixed(2) + " " + c[2][1].toFixed(2) + " ";
        }
        return s + "Z";
    }

    function build(k) {
        switch (k) {
        case 0:
            return polar(t => 0.7 + 0.3 * Math.cos(4 * t), 96);
        case 1:
            return rounded([[0, -0.95], [0.9, 0.6], [0, 0.2], [-0.9, 0.6]], 0.2);
        case 2:
            return "M 28 25 L 72 25 A 25 25 0 0 1 72 75 L 28 75 A 25 25 0 0 1 28 25 Z";
        case 3:
            return polar(t => 0.84 + 0.16 * Math.cos(10 * t), 120);
        case 4:
            return rounded([[0, -0.95], [0.95, 0], [0, 0.95], [-0.95, 0]], 0.18);
        case 5: {
            const pts = [[-0.95, 0.55]];
            for (let i = 0; i <= 14; i++) {
                const a = Math.PI * i / 14;
                pts.push([-Math.cos(a) * 0.95, 0.3 - Math.sin(a) * 0.95]);
            }
            pts.push([0.95, 0.55]);
            return rounded(pts, 0.14);
        }
        default: {
            const pts = [];
            for (let i = 0; i < 5; i++) {
                const a = i / 5 * Math.PI * 2;
                pts.push([0.95 * Math.sin(a), -0.95 * Math.cos(a)]);
            }
            return rounded(pts, 0.28);
        }
        }
    }

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
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.color

                    PathSvg {
                        path: root.build(root.kind)
                    }
                }
            }
        }
    }
}
