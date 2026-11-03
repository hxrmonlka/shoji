# shoji greeter

Entry file: `greeter.qml` (run with `qs -p greeter.qml`).

Authentication goes through greetd (`Quickshell.Services.Greetd`). greetd runs PAM with `/etc/pam.d/greetd`. The greeter never talks to PAM.

## Test on a spare VT

1. Install greetd and make the `greeter` user able to read this repository.
2. Create `/var/cache/shoji-greeter` owned by `greeter`.
3. Copy `config.toml` to a test path and edit the paths.
4. Run `sudo greetd -c /path/to/test-config.toml --vt 3` (do not replace the main login yet).

Sessions are read from `wayland-sessions` in `XDG_DATA_DIRS` and `/run/current-system/sw/share`.
The last user and session are saved in `SHOJI_GREETER_STATE`.
