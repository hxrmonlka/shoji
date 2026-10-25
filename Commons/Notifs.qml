pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

QtObject {
    id: root

    property bool dnd: false
    property var popup: null
    property bool clearing: false
    property var popupInfo: ({ summary: "", body: "", appName: "", icon: "", image: "" })

    readonly property var items: server.trackedNotifications.values.slice(-30).reverse()
    readonly property int count: server.trackedNotifications.values.length

    function received(n) {
        console.log("shoji-notif", n.appName, n.summary, "dnd=" + dnd);
        n.tracked = true;
        if (!Settings.notificationPopups)
            return;
        if (dnd && n.urgency !== NotificationUrgency.Critical)
            return;
        popupInfo = {
            summary: n.summary,
            body: n.body,
            appName: n.appName,
            icon: n.appIcon || n.desktopEntry,
            image: n.image
        };
        popup = n;
        const t = n.urgency === NotificationUrgency.Critical ? 12 : n.expireTimeout > 0 ? Math.max(3, Math.min(10, n.expireTimeout)) : 5;
        popupTimer.interval = t * 1000;
        popupTimer.restart();
    }

    function hidePopup() {
        popupTimer.stop();
        popup = null;
    }

    function dismissPopup() {
        const n = popup;
        hidePopup();
        if (n)
            n.dismiss();
    }

    function clearAnimated() {
        if (count === 0)
            return;
        hidePopup();
        clearing = true;
        clearTimer.interval = Math.min(count, 9) * 45 + 520;
        clearTimer.restart();
    }

    function toggleDnd() {
        dnd = !dnd;
        if (dnd)
            hidePopup();
    }

    function setDnd(on) {
        if (dnd !== on)
            toggleDnd();
    }

    function clear() {
        hidePopup();
        server.trackedNotifications.values.slice().forEach(n => n.dismiss());
    }

    readonly property NotificationServer server: NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        onNotification: n => root.received(n)
        Component.onCompleted: console.log("shoji-notif server up")
    }

    readonly property Timer clearTimer: Timer {
        onTriggered: {
            root.clear();
            root.clearing = false;
        }
    }

    readonly property Timer popupTimer: Timer {
        onTriggered: root.hidePopup()
    }

    readonly property Connections watcher: Connections {
        target: root.popup

        function onClosed(): void {
            root.hidePopup();
        }
    }
}
