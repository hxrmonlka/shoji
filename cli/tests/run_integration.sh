#!/usr/bin/env bash
# shoji-cli integration tests against a real quickshell.
#
#   run_integration.sh /path/to/shoji
#
# Requires a running Wayland session and `qs` on PATH (or
# $SHOJI_INTEGRATION_QS). Everything else is skipped with a clear message,
# so `make integration` is inert on machines without a quickshell session.
#
# Coverage:
#   1. discovery and dispatch against a real instance
#   2. dispatch with a CLI display scope that differs from the instance's
#      (the cross-display regression: upstream id-based selection would
#      fail here; the --pid selector does not)
#   3. the negative control proving raw `qs ipc -i` really is display-bound
#   4. kill
#
# Everything runs in a temporary config directory; the instance is
# terminated at the end.

set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI="${1:-}"

if [ -z "$CLI" ] || [ ! -x "$CLI" ]; then
  echo "usage: run_integration.sh /path/to/shoji-binary" >&2
  exit 70
fi

QS="${SHOJI_INTEGRATION_QS:-qs}"
if ! command -v "$QS" >/dev/null 2>&1; then
  echo "SKIP: no quickshell executable on PATH (set SHOJI_INTEGRATION_QS)"
  exit 0
fi
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  echo "SKIP: no Wayland/X11 session detected"
  exit 0
fi

failures=0
pass=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { failures=$((failures + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && echo "       got: $2"; }
expect_exit() {
  local want="$1" name="$2"
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then ok "$name"; else bad "$name (want exit $want)" "exit $got"; fi
}

unset QS_CONFIG_PATH QS_CONFIG_NAME QS_MANIFEST || true

WORK="$(mktemp -d /tmp/shoji-integration-XXXXXX 2>/dev/null)" || exit 70
trap 'cleanup' EXIT

INSTANCE_PID=""
cleanup() {
  if [ -n "$INSTANCE_PID" ] && kill -0 "$INSTANCE_PID" 2>/dev/null; then
    kill -9 "$INSTANCE_PID" 2>/dev/null || true
    wait "$INSTANCE_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}

echo "== real quickshell integration =="

FIXTURE="$WORK/integration-shell"
mkdir -p "$FIXTURE"
cat > "$FIXTURE/shell.qml" <<'EOF'
import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "island"

        function ping(): string {
            return "pong";
        }
    }
}
EOF

launch_instance() {
  "$QS" -p "$FIXTURE" >/dev/null 2>&1 &
  INSTANCE_PID=$!
}

wait_for_instance() {
  local i
  for i in $(seq 1 50); do
    if "$QS" list -a -j 2>/dev/null | grep -q "\"config_path\": \"$FIXTURE/shell.qml\""; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_until_gone() {
  local i
  for i in $(seq 1 50); do
    if ! "$QS" list -a -j 2>/dev/null | grep -q "\"config_path\": \"$FIXTURE/shell.qml\""; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

launch_instance
if ! wait_for_instance; then
  bad "real instance started" "qs list -a -j never reported the fixture config"
  exit 1
fi
ok "real instance started"

# 1. discovery through shoji
expect_out "$FIXTURE/shell.qml" "shoji discovers the real instance" \
  "$CLI" --qs "$QS" --store "$FIXTURE" instance list

# 2. dispatch through shoji on the current display
expect_out "pong" "shoji dispatches ipc to the real instance" \
  "$CLI" --qs "$QS" --store "$FIXTURE" ipc call island ping

# 3. cross-display: the CLI's qs child runs with a display scope that does
#    not match the instance. upstream selectInstance only filters in the
#    id/config paths, so --pid dispatch must still reach the instance.
expect_out "pong" "dispatch reaches the instance from another display scope" \
  env WAYLAND_DISPLAY=shoji-integration-absent DISPLAY= \
  "$CLI" --qs "$QS" --store "$FIXTURE" ipc call island ping

# 4. negative control: raw id-based selection is display-bound, which is
#    why shoji dispatches by pid
RAW_ID="$("$QS" list -a -j 2>/dev/null | sed -n 's/.*"id": "\([^"]*\)".*/\1/p' | head -1)"
if [ -n "$RAW_ID" ]; then
  if env WAYLAND_DISPLAY=shoji-integration-absent DISPLAY= \
      "$QS" ipc -i "$RAW_ID" call island ping >/dev/null 2>&1; then
    bad "raw qs ipc -i is display-bound (upstream contract changed?)"
  else
    ok "raw qs ipc -i fails from another display scope (negative control)"
  fi
else
  ok "negative control skipped (no instance id reported)"
fi

# 5. kill
expect_exit 0 "shoji kill stops the real instance" \
  "$CLI" --qs "$QS" --store "$FIXTURE" kill
if wait_until_gone; then
  ok "instance is gone after kill"
else
  bad "instance is gone after kill"
fi
INSTANCE_PID=""

echo
echo "$pass passed, $failures failed"
exit $([ "$failures" = 0 ] && echo 0 || echo 1)
