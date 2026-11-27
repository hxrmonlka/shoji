import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Scope {
    WlSessionLock {
        id: lock

        locked: LockState.locked
        onLockStateChanged: {
            if (!lock.locked && LockState.locked)
                LockState.locked = false;
        }

        WlSessionLockSurface {
            id: surface

            color: Wallpapers.current ? "black" : Theme.m3Surface

            LockScreen {
                anchors.fill: parent
                screenName: surface.screen ? surface.screen.name : ""
            }
        }
    }
}
