pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

QtObject {
    id: root

    readonly property bool laptopModeEnabled: Settings.laptopMode
    readonly property bool settingsLoaded: Settings.loaded

    readonly property var batteryDevice: {
        const disp = UPower.displayDevice;
        if (disp && disp.ready && disp.isPresent && disp.isLaptopBattery)
            return disp;
        const devs = UPower.devices ? UPower.devices.values : [];
        return devs.find(d => d && d.ready && d.isPresent && d.isLaptopBattery) ?? null;
    }
    readonly property bool batteryAvailable: batteryDevice !== null
    readonly property int batteryPercentage: batteryAvailable ? Math.max(0, Math.min(100, Math.round(batteryDevice.percentage * 100))) : 0
    readonly property bool batteryCharging: batteryAvailable && (batteryDevice.state === UPowerDeviceState.Charging || batteryDevice.state === UPowerDeviceState.PendingCharge)
    readonly property bool batteryLow: batteryAvailable && !batteryCharging && batteryPercentage <= 15

    readonly property string batteryIcon: {
        if (!batteryAvailable)
            return "\uf240";
        if (batteryCharging)
            return "\uf0e7";
        if (batteryPercentage >= 88)
            return "\uf240";
        if (batteryPercentage >= 63)
            return "\uf241";
        if (batteryPercentage >= 38)
            return "\uf242";
        if (batteryPercentage >= 13)
            return "\uf243";
        return "\uf244";
    }

    readonly property bool hasPerformanceProfile: PowerProfiles.hasPerformanceProfile
    readonly property int profile: PowerProfiles.profile

    readonly property var profileOptions: {
        const list = [
            {
                name: "Battery Saver",
                profile: PowerProfile.PowerSaver,
                icon: "\uf06c"
            },
            {
                name: "Balanced",
                profile: PowerProfile.Balanced,
                icon: "\uf24e"
            }
        ];
        if (hasPerformanceProfile)
            list.unshift({
                name: "Performance",
                profile: PowerProfile.Performance,
                icon: "\uf135"
            });
        return list;
    }

    readonly property string profileLabel: {
        switch (profile) {
        case PowerProfile.PowerSaver:
            return "Battery Saver";
        case PowerProfile.Performance:
            return "Performance";
        default:
            return "Balanced";
        }
    }

    readonly property string profileIcon: {
        switch (profile) {
        case PowerProfile.PowerSaver:
            return "\uf06c";
        case PowerProfile.Performance:
            return "\uf135";
        default:
            return "\uf24e";
        }
    }

    function setProfile(nextProfile: int): void {
        if (nextProfile === PowerProfile.Performance && !hasPerformanceProfile)
            return;
        PowerProfiles.profile = nextProfile;
    }

    function toggleLaptopMode(): void {
        Settings.set("laptopMode", !laptopModeEnabled);
    }

    function syncLaptopMode(): void {
        if (!settingsLoaded)
            return;
        if (!laptopModeEnabled && hasPerformanceProfile && PowerProfiles.profile !== PowerProfile.Performance)
            PowerProfiles.profile = PowerProfile.Performance;
    }

    onLaptopModeEnabledChanged: syncLaptopMode()
    onHasPerformanceProfileChanged: syncLaptopMode()
    onSettingsLoadedChanged: syncLaptopMode()
    Component.onCompleted: syncLaptopMode()
}
