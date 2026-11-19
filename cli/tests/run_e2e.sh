#!/usr/bin/env bash
# shoji-cli end-to-end tests.
#
#   run_e2e.sh /path/to/shoji            run the full e2e suite
#   run_e2e.sh --qml-only /path/to/shoji only check the shell.qml mapping drift
#
# Everything runs against tests/fixtures/mock-qs; no real quickshell needed.

set -u

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
  awk -f "$HERE/qml_ipc.awk" "$SHELL_QML" | sort > "$HERE/.qml_handlers.txt"
  "$CLI" debug map | awk -F'\t' '{ print $3 "\t" $4 }' | sort \
      > "$HERE/.cli_handlers.txt" || true
  if diff -u "$HERE/.qml_handlers.txt" "$HERE/.cli_handlers.txt"; then
    ok "cli table matches shell.qml handlers"
  else
    bad "cli table drifted from shell.qml (diff above)"
  fi
  rm -f "$HERE/.qml_handlers.txt" "$HERE/.cli_handlers.txt"
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

WORK="$(mktemp -d /tmp/shoji-e2e-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

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

# dispatch ------------------------------------------------------------------
: > "$MOCK_QS_LOG"
expect_exit 0 "island toggle dispatches" "$CLI" island toggle
grep -qF -- "-i inst1abcdefgh --any-display call island toggle" "$MOCK_QS_LOG" \
  && ok "dispatch argv vector exact" || bad "dispatch argv vector exact" "$(cat "$MOCK_QS_LOG")"

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
expect_exit 0 "notifications dnd off normalizes" "$CLI" notifications dnd off
grep -qF -- "call notifications dnd false" "$MOCK_QS_LOG" \
  && ok "bool normalization applied" || bad "bool normalization applied" "$(cat "$MOCK_QS_LOG")"

: > "$MOCK_QS_LOG"
expect_exit 0 "wallpaper set path dispatches" "$CLI" wallpaper set /nix/store/wall.jpg
grep -qF -- "call wallpaper set /nix/store/wall.jpg" "$MOCK_QS_LOG" \
  && ok "path argument passed" || bad "path argument passed" "$(cat "$MOCK_QS_LOG")"

# status and instance commands ----------------------------------------------
expect_exit 0 "status exits 0" "$CLI" status
expect_out "verdict: match" "status verdict match" "$CLI" status
expect_out "$STORE/shell.qml" "status shows expected store path" "$CLI" status
expect_out "inst1abcdefgh" "status lists instance id" "$CLI" status
expect_exit 0 "status --json exits 0" "$CLI" status --json
"$CLI" status --json | grep -q '"verdict":"match"' \
  && ok "status --json verdict" || bad "status --json verdict" "$("$CLI" status --json)"
expect_out "inst2abcdefgh" "status lists foreign instance" "$CLI" status
expect_exit 0 "instance list exits 0" "$CLI" instance list
expect_out "inst1abcdefgh" "instance list shows instance" "$CLI" instance list
expect_exit 0 "instance current exits 0" "$CLI" instance current
expect_out "inst1abcdefgh" "instance current selects expected" "$CLI" instance current
expect_exit 0 "instance inspect exits 0" "$CLI" instance inspect
expect_out "ipc accessible: yes" "instance inspect probes ipc" "$CLI" instance inspect

# ipc inspection -------------------------------------------------------------
expect_exit 0 "ipc show exits 0" "$CLI" ipc show
expect_out "target island" "ipc show relays targets" "$CLI" ipc show
: > "$MOCK_QS_LOG"
expect_exit 0 "ipc call passthrough works" "$CLI" ipc call wallpaper next
grep -qF -- "call wallpaper next" "$MOCK_QS_LOG" \
  && ok "ipc call passthrough argv" || bad "ipc call passthrough argv" "$(cat "$MOCK_QS_LOG")"

# instance override ----------------------------------------------------------
: > "$MOCK_QS_LOG"
"$CLI" --instance-id inst2 island toggle >/dev/null 2>"$WORK/warn.txt"
got=$?
if [ "$got" = 0 ]; then ok "override dispatches with warning"; else bad "override dispatches with warning" "exit $got"; fi
grep -q "not the expected configuration" "$WORK/warn.txt" \
  && ok "foreign-config override warns" || bad "foreign-config override warns" "$(cat "$WORK/warn.txt")"
grep -qF -- "call island toggle" "$MOCK_QS_LOG" \
  && ok "override still dispatches" || bad "override still dispatches" "$(cat "$MOCK_QS_LOG")"

expect_exit 67 "unknown instance id exits 67" "$CLI" --instance-id zzz island toggle

# store resolution errors ----------------------------------------------------
# Deterministic and host-independent: a nonexistent --store override decides,
# the test never relies on unsetting an environment variable.
expect_exit 66 "missing store override exits 66" \
  "$CLI" --store "$WORK/does-not-exist" island toggle
expect_exit 66 "nonexistent store override exits 66" \
  env SHOJI_STORE_PATH="$WORK/nope" "$CLI" island toggle
expect_exit 64 "--store without value exits 64" "$CLI" --store

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
"$CLI" --instance-id inst island toggle 2>/dev/null | grep -c "inst[19]abcdefgh" > "$WORK/ambig.txt"
grep -q "^2$" "$WORK/ambig.txt" && ok "ambiguous prefix lists both matches" \
  || bad "ambiguous prefix lists both matches" "$(cat "$WORK/ambig.txt")"

# no match --------------------------------------------------------------------
cat > "$WORK/instances.json" <<EOF
[
  {"id": "inst2abcdefgh", "pid": 5001, "shell_id": "p2",
   "config_path": "$WORK/other/shell.qml", "launch_time": "2026-11-17T09:00:00"}
]
EOF
expect_exit 67 "no matching instance exits 67" "$CLI" island toggle
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
env MOCK_DEAD_LIST_FILE="$WORK/dead.json" "$CLI" status 2>/dev/null | grep -q "verdict: no-instance-dead-only" \
  && ok "status verdict reports dead-only" || bad "status verdict reports dead-only"

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

: > "$MOCK_QS_LOG"
expect_exit 0 "unsupported --show-dead falls back" \
  env MOCK_DEAD_FAIL=1 "$CLI" island toggle
list_calls=$(grep -c '^list ' "$MOCK_QS_LOG")
[ "$list_calls" = "2" ] && ok "compatibility probe ran after rejection" \
  || bad "compatibility probe ran after rejection" "$list_calls list invocations"

expect_exit 69 "missing quickshell exits 69" \
  env SHOJI_QS_BIN="$WORK/definitely-not-qs" "$CLI" island toggle
expect_exit 1 "hung quickshell times out" env MOCK_QS_SLEEP=5 SHOJI_QS_TIMEOUT_MS=300 \
  "$CLI" island toggle

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
