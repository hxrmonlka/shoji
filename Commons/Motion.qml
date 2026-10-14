pragma Singleton

import QtQuick

QtObject {
    readonly property list<real> standard: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
    readonly property list<real> emphasized: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
    readonly property list<real> emphasizedDecelerate: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
    readonly property list<real> emphasizedAccelerate: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]

    readonly property int short3: 150
    readonly property int short4: 200
    readonly property int medium1: 250
    readonly property int medium2: 300
    readonly property int medium4: 400
    readonly property int long2: 500
}
