#!/usr/bin/env bash
# shoji-cli end-to-end tests.
#
#   run_e2e.sh /path/to/shoji            run the full e2e suite
#   run_e2e.sh --qml-only /path/to/shoji only check the shell.qml mapping drift
#
# Everything runs against tests/fixtures/mock-qs; no real quickshell needed.

set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLI=""
QML_ONLY=0

if [ "${1:-}" = "--qml-only" ]; then
  QML_ONLY=1
  CLI="${2:-}"
else
  CLI="${1:-}"
fi

SHELL_QML="$HERE/../../shell.qml"
failures=0
pass=0

umask 077
WORK="$(mktemp -d /tmp/shoji-e2e-XXXXXX 2>/dev/null)" || {
  echo "could not create temporary test workspace" >&2
  exit 70
}
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  echo "mktemp did not create a test workspace" >&2
  exit 70
fi
trap 'rm -rf "$WORK"' EXIT

ok() { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { failures=$((failures + 1)); echo "  FAIL $1"; if [ -n "${2:-}" ]; then echo "       got: $2"; fi; }

# expect_exit <expected-code> <description> <command...>
expect_exit() {
  local want="$1" name="$2"
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then ok "$name"; else bad "$name (want exit $want)" "exit $got"; fi
}

# expect_out <pattern> <description> <command...>  (stdout contains pattern)
expect_out() {
  local pattern="$1" name="$2"
  shift 2
  local out
  out="$("$@" 2>/dev/null)"
  if printf '%s' "$out" | grep -qF -- "$pattern"; then ok "$name"
  else bad "$name" "stdout did not contain '$pattern'"; fi
}

# mapping drift check: shell.qml handlers vs the compiled table
check_qml_mapping() {
  echo "== shell.qml mapping drift =="
  if [ ! -f "$SHELL_QML" ]; then bad "shell.qml found at $SHELL_QML"; return; fi
  if ! awk -f "$HERE/qml_ipc.awk" "$SHELL_QML" | sort > "$WORK/qml_handlers.txt"; then
    bad "shell.qml handler extraction failed"
    return
  fi
  if ! "$CLI" debug map | awk -F'\t' '{ print $3 "\t" $4 }' | sort \
       > "$WORK/cli_handlers.txt"; then
    bad "compiled IPC map extraction failed"
    return
  fi
  if diff -u "$WORK/qml_handlers.txt" "$WORK/cli_handlers.txt"; then
    ok "cli table matches shell.qml handlers"
  else
    bad "cli table drifted from shell.qml (diff above)"
  fi
}

if [ "$QML_ONLY" = 1 ]; then
  if [ -z "$CLI" ] || [ ! -x "$CLI" ]; then
    echo "usage: run_e2e.sh --qml-only /path/to/shoji-binary" >&2
    exit 70
  fi
  check_qml_mapping
  echo
  echo "$pass passed, $failures failed"
  exit $([ "$failures" = 0 ] && echo 0 || echo 1)
fi

if [ -z "$CLI" ] || [ ! -x "$CLI" ]; then
  echo "usage: run_e2e.sh /path/to/shoji-binary" >&2
  exit 70
fi

# fixture: fake nix-store shoji config + instance list from the mock
STORE="$WORK/store/aaaaaaaa-shoji"
mkdir -p "$STORE"
printf 'import qs.Commons\nShellRoot {}\n' > "$STORE/shell.qml"

cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml",
   "launch_time": "2026-11-17T08:00:00"},
  {"id": "inst2abcdefgh", "pid": 5001, "shell_id": "p2",
   "config_path": "$WORK/other/shell.qml",
   "launch_time": "2026-11-17T09:00:00"}
]
EOF

chmod +x "$HERE/fixtures/mock-qs"

export SHOJI_QS_BIN="$HERE/fixtures/mock-qs"
export SHOJI_STORE_PATH="$STORE"
export MOCK_LIST_FILE="$WORK/instances.json"
export MOCK_QS_LOG="$WORK/mock-qs.log"

echo "== end-to-end (mock quickshell) =="

# basic commands -----------------------------------------------------------
expect_exit 0 "--help exits 0" "$CLI" --help
"$CLI" --help | grep -q "command line interface" && ok "--help prints banner" \
  || bad "--help prints version banner"
expect_exit 0 "--version exits 0" "$CLI" --version
expect_out "shoji-cli" "--version output" "$CLI" --version
expect_exit 64 "unknown command exits 64" "$CLI" explode
expect_exit 64 "unknown facade subcommand exits 64" "$CLI" island explode
expect_exit 64 "awake on without int exits 64" "$CLI" awake on xx

# Launch the shell through Shoji so Quickshell records the immutable store path.
: > "$MOCK_QS_LOG"
expect_exit 0 "run forwards daemonize and no-duplicate" \
  env QS_CONFIG_PATH="$WORK/legacy/shell.qml" QS_CONFIG_NAME=legacy QS_MANIFEST="$WORK/manifest" \
  "$CLI" --store "$STORE" run --daemonize --no-duplicate --verbose
grep -qF -- "run --path $STORE/shell.qml --daemonize --no-duplicate --verbose" "$MOCK_QS_LOG" \
  && ok "run pins the resolved Shoji store path" || bad "run pins the resolved Shoji store path" "$(cat "$MOCK_QS_LOG")"
expect_exit 64 "run rejects Quickshell config overrides" \
  "$CLI" run --path "$WORK/other/shell.qml"
expect_exit 66 "run requires a resolvable Shoji store" \
  "$CLI" --store "$WORK/missing-run-store" run --daemonize

# Quickshell's inherited config selectors conflict with explicit IPC instance selection.
: > "$MOCK_QS_LOG"
expect_exit 0 "IPC ignores inherited Quickshell config selectors" \
  env QS_CONFIG_PATH="$WORK/legacy/shell.qml" QS_CONFIG_NAME=legacy QS_MANIFEST="$WORK/manifest" \
  "$CLI" island toggle
grep -qF -- "call island toggle" "$MOCK_QS_LOG" \
  && ok "IPC runs without config-selection environment" || bad "IPC environment was not sanitized" "$(cat "$MOCK_QS_LOG")"

# dispatch ------------------------------------------------------------------
: > "$MOCK_QS_LOG"
expect_exit 0 "island toggle dispatches" "$CLI" island toggle
grep -qF -- "--pid 4242 call island toggle" "$MOCK_QS_LOG" \
  && ok "dispatch argv vector exact" || bad "dispatch argv vector exact" "$(cat "$MOCK_QS_LOG")"
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
ipc_calls=$(grep -c '^ARGV 3:ipc' "$MOCK_QS_LOG")
[ "$list_calls" = "1" ] && ok "facade dispatch runs exactly one listing" \
  || bad "facade dispatch runs exactly one listing" "$list_calls list invocations"
[ "$ipc_calls" = "1" ] && ok "facade dispatch runs exactly one IPC subprocess" \
  || bad "facade dispatch runs exactly one IPC subprocess" "$ipc_calls ipc invocations"

# upstream evidence (quickshell 0.3.0): --pid selection has no display filter,
# so dispatch reaches instances on other Wayland displays; a qs child with a
# mismatched WAYLAND_DISPLAY must still work through shoji
: > "$MOCK_QS_LOG"
expect_exit 0 "dispatch ignores the CLI display scope" \
  env WAYLAND_DISPLAY=shoji-e2e-other-display "$CLI" island toggle
grep -qF -- "--pid 4242 call island toggle" "$MOCK_QS_LOG" \
  && ok "cross-display dispatch keeps the pid selector" \
  || bad "cross-display dispatch keeps the pid selector" "$(cat "$MOCK_QS_LOG")"

# a parent that ignores SIGCHLD passes SIG_IGN down; the CLI must establish
# its own disposition before spawning quickshell
if [ -n "${SHOJI_SPAWN_HELPER:-}" ] && [ -x "$SHOJI_SPAWN_HELPER" ]; then
  expect_exit 0 "shoji works when the parent ignores SIGCHLD" \
    "$SHOJI_SPAWN_HELPER" exec-ignchld "$CLI" status
else
  ok "SIGCHLD leg skipped (spawn helper not built)"
fi

: > "$MOCK_QS_LOG"
expect_exit 0 "island tab calendar dispatches" "$CLI" island tab calendar
grep -qF -- "call island tab calendar" "$MOCK_QS_LOG" \
  && ok "tab argument passed" || bad "tab argument passed" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "awake on 30 dispatches" "$CLI" awake on 30
grep -qF -- "call awake on 30" "$MOCK_QS_LOG" \
  && ok "int argument passed" || bad "int argument passed" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "media play-pause maps to playPause" "$CLI" media play-pause
grep -qF -- "call media playPause" "$MOCK_QS_LOG" \
  && ok "camelCase mapping applied" || bad "camelCase mapping applied" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "media player-next maps to playerNext" "$CLI" media player-next
grep -qF -- "call media playerNext" "$MOCK_QS_LOG" \
  && ok "player switch mapping applied" || bad "player switch mapping applied" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "notifications dnd off normalizes" "$CLI" notifications dnd off
grep -qF -- "call notifications dnd false" "$MOCK_QS_LOG" \
  && ok "bool normalization applied" || bad "bool normalization applied" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "wallpaper set path dispatches" "$CLI" wallpaper set /nix/store/wall.jpg
grep -qF -- "call wallpaper set /nix/store/wall.jpg" "$MOCK_QS_LOG" \
  && ok "path argument passed" || bad "path argument passed" "$(cat "$MOCK_QS_LOG")"

wall_path="$WORK/wall paper.jpg"
: > "$MOCK_QS_LOG"
expect_exit 0 "wallpaper path containing spaces dispatches" "$CLI" wallpaper set "$wall_path"
grep -qF -- " ${#wall_path}:$wall_path" "$MOCK_QS_LOG" \
  && ok "IPC argument boundary survives spaces" || bad "IPC argument boundary survives spaces" "$(cat "$MOCK_QS_LOG")"

# status and instance commands ----------------------------------------------
expect_exit 0 "status exits 0" "$CLI" status
expect_out "verdict: match" "status verdict match" "$CLI" status
expect_out "$STORE/shell.qml" "status shows expected store path" "$CLI" status
expect_out "inst1abcdefgh" "status lists instance id" "$CLI" status
expect_out "pid 4242" "status prints live instance PID" "$CLI" status
expect_exit 0 "status --json exits 0" "$CLI" status --json
"$CLI" status --json | grep -q '"verdict":"match"' \
  && ok "status --json verdict" || bad "status --json verdict" "$("$CLI" status --json)"
expect_out "inst2abcdefgh" "status lists foreign instance" "$CLI" status
expect_exit 0 "instance list exits 0" "$CLI" instance list
expect_out "inst1abcdefgh" "instance list shows instance" "$CLI" instance list
expect_out "4242" "instance list prints live instance PID" "$CLI" instance list
expect_exit 0 "instance current exits 0" "$CLI" instance current
expect_out "inst1abcdefgh" "instance current selects expected" "$CLI" instance current
expect_exit 0 "instance inspect exits 0" "$CLI" instance inspect
expect_out "ipc accessible: yes" "instance inspect probes ipc" "$CLI" instance inspect

# ipc inspection -------------------------------------------------------------
expect_exit 0 "ipc show exits 0" "$CLI" ipc show
expect_out "target island" "ipc show relays targets" "$CLI" ipc show
: > "$MOCK_QS_LOG"
"$CLI" ipc show >/dev/null 2>&1
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
ipc_calls=$(grep -c '^ARGV 3:ipc' "$MOCK_QS_LOG")
[ "$list_calls" = "1" ] && [ "$ipc_calls" = "1" ] \
  && ok "ipc show runs one listing plus one show" \
  || bad "ipc show runs one listing plus one show" "$(cat "$MOCK_QS_LOG")"
: > "$MOCK_QS_LOG"
expect_exit 0 "ipc call passthrough works" "$CLI" ipc call wallpaper next
grep -qF -- "call wallpaper next" "$MOCK_QS_LOG" \
  && ok "ipc call passthrough argv" || bad "ipc call passthrough argv" "$(cat "$MOCK_QS_LOG")"
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
ipc_calls=$(grep -c '^ARGV 3:ipc' "$MOCK_QS_LOG")
[ "$list_calls" = "1" ] && ok "raw ipc call runs exactly one listing" \
  || bad "raw ipc call runs exactly one listing" "$list_calls list invocations"
[ "$ipc_calls" = "1" ] && ok "raw ipc call runs exactly one IPC subprocess" \
  || bad "raw ipc call runs exactly one IPC subprocess" "$ipc_calls ipc invocations"

env MOCK_QS_SUCCESS_ERR="expected child warning" \
  "$CLI" island toggle > "$WORK/success.stdout" 2> "$WORK/success.stderr" \
  && grep -qF "expected child warning" "$WORK/success.stderr" \
  && ok "successful IPC relays child stderr" \
  || bad "successful IPC relays child stderr" "$(cat "$WORK/success.stderr")"

# instance override ----------------------------------------------------------
: > "$MOCK_QS_LOG"
"$CLI" --instance-id inst2 island toggle >/dev/null 2>"$WORK/warn.txt"
got=$?
if [ "$got" = 0 ]; then ok "override dispatches with warning"; else bad "override dispatches with warning" "exit $got"; fi
grep -q "not the expected configuration" "$WORK/warn.txt" \
  && ok "foreign-config override warns" || bad "foreign-config override warns" "$(cat "$WORK/warn.txt")"
grep -qF -- "--pid 5001 call island toggle" "$MOCK_QS_LOG" \
  && ok "override still dispatches" || bad "override still dispatches" "$(cat "$MOCK_QS_LOG")"

expect_exit 67 "unknown instance id exits 67" "$CLI" --instance-id zzz island toggle

# kill -----------------------------------------------------------------------
: > "$MOCK_QS_LOG"
expect_exit 0 "kill dispatches to the selected instance" "$CLI" kill
grep -qF -- " 4:kill 5:--pid 4:4242" "$MOCK_QS_LOG" \
  && ok "kill argv vector exact" || bad "kill argv vector exact" "$(cat "$MOCK_QS_LOG")"
expect_out "Killed 4242" "kill relays upstream output" "$CLI" kill

expect_exit 67 "kill refuses foreign explicit selection" "$CLI" --instance-id inst2 kill
"$CLI" --instance-id inst2 kill 2>"$WORK/kill-foreign.txt" || true
grep -qF "not the expected" "$WORK/kill-foreign.txt" \
  && grep -qF "qs kill -i" "$WORK/kill-foreign.txt" \
  && ok "foreign kill refusal explains" || bad "foreign kill refusal explains" "$(cat "$WORK/kill-foreign.txt")"

expect_exit 64 "kill rejects extra arguments" "$CLI" kill explode
expect_exit 64 "kill rejects unknown flags" "$CLI" kill --restart
expect_exit 64 "kill --all rejects a pending instance override" "$CLI" --instance-id inst1 kill --all
expect_exit 64 "kill --all rejects a later instance override" "$CLI" kill --all --instance-id inst1
expect_exit 1 "kill propagates quickshell failure" env MOCK_KILL_FAIL=1 "$CLI" kill

# store resolution errors ----------------------------------------------------
# Deterministic and host-independent: a nonexistent --store override decides,
# the test never relies on unsetting an environment variable.
expect_exit 66 "missing store override exits 66" \
  "$CLI" --store "$WORK/does-not-exist" island toggle
expect_exit 66 "nonexistent store override exits 66" \
  env SHOJI_STORE_PATH="$WORK/nope" "$CLI" island toggle
expect_exit 66 "kill without a resolvable store exits 66" \
  "$CLI" --store "$WORK/does-not-exist" kill
expect_exit 64 "--store without value exits 64" "$CLI" --store
expect_exit 64 "malformed timeout environment exits 64" \
  env SHOJI_QS_TIMEOUT_MS=abc "$CLI" status

# local commands never spawn quickshell and must not consult the timeout
expect_exit 0 "invalid timeout env still runs --help" \
  env SHOJI_QS_TIMEOUT_MS=abc "$CLI" --help
expect_exit 0 "invalid timeout env still runs --version" \
  env SHOJI_QS_TIMEOUT_MS=abc "$CLI" --version
expect_exit 0 "invalid timeout env still runs debug map" \
  env SHOJI_QS_TIMEOUT_MS=abc "$CLI" debug map
expect_exit 64 "invalid timeout env rejects run" \
  env SHOJI_QS_TIMEOUT_MS=abc "$CLI" --store "$STORE" run

# quickshell unavailable ------------------------------------------------------
expect_exit 69 "missing quickshell exits 69" \
  env SHOJI_QS_BIN="$WORK/definitely-not-qs" "$CLI" island toggle

# ambiguity --------------------------------------------------------------------
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T08:00:00"},
  {"id": "inst9abcdefgh", "pid": 6001, "shell_id": "p9",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T10:00:00"}
]
EOF
expect_exit 68 "ambiguous instances exit 68" "$CLI" island toggle
expect_exit 0 "override resolves ambiguity" "$CLI" --instance-id inst9 island toggle
expect_exit 68 "ambiguous id prefix exits 68" "$CLI" --instance-id inst island toggle
"$CLI" --instance-id inst island toggle > "$WORK/ambig.stdout" 2> "$WORK/ambig.stderr" || true
grep -c "inst[19]abcdefgh" "$WORK/ambig.stderr" > "$WORK/ambig.txt"
grep -q "^2$" "$WORK/ambig.txt" && ok "ambiguous prefix lists both matches" \
  || bad "ambiguous prefix lists both matches" "$(cat "$WORK/ambig.txt")"

: > "$MOCK_QS_LOG"
expect_exit 0 "bare kill picks the newest matching instance" "$CLI" kill
grep -qF -- " 4:kill 5:--pid 4:6001" "$MOCK_QS_LOG" \
  && ok "bare kill selects the highest pid" || bad "bare kill selects the highest pid" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "kill --all kills every matching instance" "$CLI" kill --all
[ "$(grep -c ' 4:kill 5:--pid ' "$MOCK_QS_LOG")" = "2" ] \
  && ok "kill --all dispatches once per instance" || bad "kill --all dispatches once per instance" "$(cat "$MOCK_QS_LOG")"
grep -qF -- "5:--pid 4:4242" "$MOCK_QS_LOG" && grep -qF -- "5:--pid 4:6001" "$MOCK_QS_LOG" \
  && ok "kill --all covers both instances" || bad "kill --all covers both instances" "$(cat "$MOCK_QS_LOG")"

expect_exit 68 "ambiguous id prefix kill exits 68" "$CLI" --instance-id inst kill

# no match --------------------------------------------------------------------
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst2abcdefgh", "pid": 5001, "shell_id": "p2",
   "config_path": "$WORK/other/shell.qml", "launch_time": "2026-11-17T09:00:00"}
]
EOF
expect_exit 67 "no matching instance exits 67" "$CLI" island toggle
expect_exit 67 "bare kill without a match exits 67" "$CLI" kill
expect_exit 67 "kill --all without a match exits 67" "$CLI" kill --all
expect_exit 0 "status still informative without match" "$CLI" status
"$CLI" status | grep -q "verdict: no-match" \
  && ok "status verdict no-match" || bad "status verdict no-match"

# empty instance list (real qs prints a bare log line, not JSON) -----------
printf 'No running instances.\n' > "$WORK/instances.json"
expect_exit 67 "bare empty-list notice exits 67" "$CLI" island toggle
"$CLI" status | grep -q "verdict: no-match" \
  && ok "status verdict no-match on empty notice" || bad "status verdict no-match on empty notice"
: > "$WORK/instances.json"
expect_exit 67 "empty list output exits 67" "$CLI" island toggle

# dead instance reporting -----------------------------------------------------
# Upstream marks a row dead only by its absence from the live listing: the
# --show-dead output of a dead instance still carries its launch-time pid,
# which can stay positive after a crash. Dead rows must never dispatch.
cat > "$WORK/instances.json" <<EOF
No running instances.
EOF
cat > "$WORK/dead.json" <<EOF
[
  {"id": "dead1abcdefgh", "pid": 4711, "shell_id": "p0",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T07:00:00"}
]
EOF
expect_exit 67 "dead-only instance exits 67" \
  env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" island toggle
expect_exit 67 "dead-only positive-pid instance exits 67" \
  env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" --instance-id dead1 island toggle
expect_exit 67 "dead-only bare kill exits 67" \
  env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" kill
env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" status 2>/dev/null | grep -q "verdict: no-instance-dead-only" \
  && ok "status verdict reports dead-only" || bad "status verdict reports dead-only"

cat > "$WORK/dead.json" <<EOF
[
  {"id": "dead2abcdefgh", "pid": 4712, "shell_id": "p0",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T07:30:00"}
]
EOF
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T08:00:00"}
]
EOF
env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" status > "$WORK/mixed-status.txt" 2> "$WORK/mixed-status.err"
grep -q "1 running, 1 dead" "$WORK/mixed-status.txt" \
  && ok "mixed live/dead listing is valid JSON" \
  || bad "mixed live/dead listing is valid JSON" "$(cat "$WORK/mixed-status.txt" "$WORK/mixed-status.err")"
expect_exit 67 "explicit dead instance kill exits 67" \
  env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" --instance-id dead2 kill

# discovery failure classes ---------------------------------------------------
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T08:00:00"}
]
EOF
: > "$MOCK_QS_LOG"
expect_exit 1 "generic list failure exits 1" env MOCK_LIST_FAIL=1 "$CLI" island toggle
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
[ "$list_calls" = "1" ] && ok "generic list failure is not retried" \
  || bad "generic list failure is not retried" "$list_calls list invocations"

# Fast dispatch path: a successful IPC command never consults --show-dead
# (the rejection is irrelevant to it); the diagnostic commands still run the
# full probe for dead-instance reporting.
: > "$MOCK_QS_LOG"
expect_exit 0 "unsupported --show-dead keeps fast dispatch working" \
  env MOCK_DEAD_FAIL=1 "$CLI" island toggle
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
ipc_calls=$(grep -c '^ARGV 3:ipc' "$MOCK_QS_LOG")
[ "$list_calls" = "1" ] && ok "fast dispatch ignores the dead-instance probe" \
  || bad "fast dispatch ignores the dead-instance probe" "$list_calls list invocations"
[ "$ipc_calls" = "1" ] && ok "fast dispatch still dispatches without --show-dead" \
  || bad "fast dispatch still dispatches without --show-dead" "$ipc_calls ipc invocations"

: > "$MOCK_QS_LOG"
expect_exit 0 "status retains the full diagnostic discovery" \
  env MOCK_DEAD_FAIL=1 "$CLI" status >/dev/null
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
[ "$list_calls" = "2" ] && ok "diagnostic path still probes --show-dead" \
  || bad "diagnostic path still probes --show-dead" "$list_calls list invocations"

# the exit code of `instance list` survives the pipeline release path
expect_exit 1 "instance list preserves the discovery failure exit code" \
  env MOCK_LIST_FAIL=1 "$CLI" instance list

# a NUL byte inside the listing must not truncate it into valid JSON:
# "[]" followed by garbage is malformed text, not an empty list
: > "$MOCK_QS_LOG"
printf '[]\0trailing-garbage\n' > "$WORK/instances-nul.json"
expect_exit 70 "embedded NUL in the listing is rejected" \
  env MOCK_LIST_FILE="$WORK/instances-nul.json" "$CLI" instance list
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T08:00:00"}
]
EOF

expect_exit 69 "missing quickshell exits 69" \
  env SHOJI_QS_BIN="$WORK/definitely-not-qs" "$CLI" island toggle
expect_exit 1 "hung quickshell times out" env MOCK_QS_SLEEP=5 SHOJI_QS_TIMEOUT_MS=300 \
  "$CLI" island toggle
env MOCK_QS_SLEEP=5 SHOJI_QS_TIMEOUT_MS=300 \
  "$CLI" ipc show > "$WORK/ipc-show-timeout.stdout" 2> "$WORK/ipc-show-timeout.stderr"
show_timeout_exit=$?
if [ "$show_timeout_exit" = 1 ] && grep -qF 'did not answer `ipc show` in time' \
     "$WORK/ipc-show-timeout.stderr" && grep -qF "SHOJI_QS_TIMEOUT_MS" \
     "$WORK/ipc-show-timeout.stderr"; then
  ok "ipc show timeout reports the timeout and configuration hint"
else
  bad "ipc show timeout reports the timeout and configuration hint" \
    "exit $show_timeout_exit: $(cat "$WORK/ipc-show-timeout.stderr")"
fi

# doctor --------------------------------------------------------------------
cp "$WORK/instances.json" "$WORK/instances-dead.json"
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T08:00:00"}
]
EOF
expect_exit 0 "doctor passes on healthy setup" "$CLI" doctor
expect_out "[ok] quickshell executable" "doctor checks qs binary" "$CLI" doctor
expect_out "[ok] IPC accessibility" "doctor checks ipc" "$CLI" doctor
expect_exit 1 "doctor fails without quickshell" \
  env SHOJI_QS_BIN="$WORK/definitely-not-qs" "$CLI" doctor
expect_exit 1 "doctor fails without store" \
  "$CLI" --store "$WORK/does-not-exist" doctor

cat > "$WORK/foreign-only.json" <<EOF
[
  {"id": "inst2abcdefgh", "pid": 5001, "shell_id": "p2",
   "config_path": "$WORK/other/shell.qml", "launch_time": "2026-11-17T09:00:00"}
]
EOF
expect_exit 1 "doctor rejects foreign-only explicit selection" \
  env MOCK_LIST_FILE="$WORK/foreign-only.json" "$CLI" --instance-id inst2 doctor

# timeout -------------------------------------------------------------------
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1",
   "config_path": "$STORE/shell.qml", "launch_time": "2026-11-17T08:00:00"}
]
EOF

# --store precedence over environment ----------------------------------------
STORE2="$WORK/store/bbbbbbbb-shoji"
mkdir -p "$STORE2"
printf 'import qs.Commons\nShellRoot {}\n' > "$STORE2/shell.qml"
expect_out "$STORE2/shell.qml" "--store overrides SHOJI_STORE_PATH" \
  "$CLI" --store "$STORE2" status
expect_exit 67 "store override without running instance exits 67" \
  "$CLI" --store "$STORE2" island toggle

# mapping drift ---------------------------------------------------------------
check_qml_mapping

echo
echo "$pass passed, $failures failed"
exit $([ "$failures" = 0 ] && echo 0 || echo 1)
