pragma Singleton

import QtQuick

QtObject {
    id: root

    property bool armed: false

    readonly property var apps: [
        { id: "mango", key: "themeMango" },
        { id: "kitty", key: "themeKitty" },
        { id: "btop", key: "themeBtop" },
        { id: "equicord", key: "themeEquicord" },
        { id: "gtk", key: "themeGtk" },
        { id: "helium", key: "themeHelium" },
        { id: "spotify", key: "themeSpotify" },
        { id: "zed", key: "themeZed" }
    ]
    readonly property string enabled: apps.filter(a => Settings.get(a.key)).map(a => a.id).join(" ")
    readonly property int radius: Settings.get("themeRadius")
    readonly property string signature: enabled + "|" + radius + "|" + Schemes.signature

    function start() {
        arm.restart();
    }

    onSignatureChanged: {
        if (armed)
            debounce.restart();
    }

    readonly property Timer debounce: Timer {
        interval: 600
        onTriggered: Wallpapers.refresh()
    }

    readonly property Timer arm: Timer {
        interval: 3000
        onTriggered: root.armed = true
    }
}
