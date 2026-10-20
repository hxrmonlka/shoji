import QtQuick
import qs.Commons

Canvas {
    id: root

    property var values: []
    property var values2: []
    property real maxValue: 1
    property bool auto: false
    property int points: 45
    property color lineColor: Theme.m3Primary
    property color line2Color: Theme.m3OnSurfaceVariant

    readonly property real ceiling: {
        if (!auto)
            return maxValue;
        let m = maxValue;
        for (const v of values)
            m = Math.max(m, v);
        for (const v of values2)
            m = Math.max(m, v);
        return m;
    }

    function rgba(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")";
    }

    function trace(ctx, data) {
        const step = width / (points - 1);
        const pts = data.map((v, i) => ({
            x: width - (data.length - 1 - i) * step,
            y: height - 2 - Math.min(1, Math.max(0, v / ceiling)) * (height - 4)
        }));
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) {
            const mx = (pts[i - 1].x + pts[i].x) / 2;
            const my = (pts[i - 1].y + pts[i].y) / 2;
            ctx.quadraticCurveTo(pts[i - 1].x, pts[i - 1].y, mx, my);
        }
        ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
        return pts;
    }

    function stroke(ctx, data, color, fill) {
        if (data.length < 2)
            return;
        ctx.beginPath();
        const pts = trace(ctx, data);
        ctx.lineWidth = 2;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.strokeStyle = rgba(color, 1);
        ctx.stroke();
        if (!fill)
            return;
        ctx.beginPath();
        trace(ctx, data);
        ctx.lineTo(pts[pts.length - 1].x, height);
        ctx.lineTo(pts[0].x, height);
        ctx.closePath();
        const grad = ctx.createLinearGradient(0, 0, 0, height);
        grad.addColorStop(0, rgba(color, 0.32));
        grad.addColorStop(1, rgba(color, 0));
        ctx.fillStyle = grad;
        ctx.fill();
    }

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onLineColorChanged: requestPaint()
    onLine2ColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        stroke(ctx, values2, line2Color, false);
        stroke(ctx, values, lineColor, true);
    }
}
