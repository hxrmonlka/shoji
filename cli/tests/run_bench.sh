#!/usr/bin/env bash
# Benchmark: shoji-cli IPC dispatch latency, old vs new discovery paths.
#
#   run_bench.sh <shoji-old> <shoji-new> [iterations]
#
# Each iteration runs one full CLI invocation against the bench mock
# quickshell (tests/fixtures/bench-qs), which sleeps QS_BENCH_DELAY_MS per
# subprocess to emulate real quickshell Qt startup cost. The mock log records
# the exact number of quickshell subprocesses per run.

set -u
set -o pipefail

OLD_BIN="${1:?usage: run_bench.sh <old> <new> [iterations]}"
NEW_BIN="${2:?usage: run_bench.sh <old> <new> [iterations]}"
ITERS="${3:-20}"
HERE="$(cd "$(dirname "$0")" && pwd)"

WORK="$(mktemp -d /tmp/shoji-bench-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

STORE="$WORK/store/aaaaaaaa-shoji"
mkdir -p "$STORE"
printf 'import qs.Commons\nShellRoot {}\n' > "$STORE/shell.qml"
printf '[{"id": "inst1abcdefgh", "pid": 4242, "shell_id": "p1", "config_path": "%s/shell.qml", "launch_time": "2026-11-17T08:00:00"}]\n' "$STORE" > "$WORK/instances.json"

export SHOJI_QS_BIN="$HERE/fixtures/bench-qs"
export SHOJI_STORE_PATH="$STORE"
export MOCK_LIST_FILE="$WORK/instances.json"
export MOCK_QS_LOG="$WORK/mock.log"

bench_one() {
  local bin="$1" label="$2"
  local times=()
  : > "$MOCK_QS_LOG"
  for _ in $(seq 1 "$ITERS"); do
    local t0 t1
    t0=$(date +%s%N)
    "$bin" island toggle >/dev/null 2>&1
    t1=$(date +%s%N)
    times+=($(( (t1 - t0) / 1000000 )))
  done
  local spawns
  spawns=$(grep -c '^ARGV' "$MOCK_QS_LOG")
  local lists
  lists=$(grep -c '^ARGV 4:list' "$MOCK_QS_LOG")
  printf '%s\n' "$label" "${times[@]}" "spawns_per_run=$((spawns / ITERS)) lists_per_run=$((lists / ITERS))"
}

bench_one "$OLD_BIN" OLD > "$WORK/old.txt"
bench_one "$NEW_BIN" NEW > "$WORK/new.txt"

for f in "$WORK/old.txt" "$WORK/new.txt"; do
  label=$(head -1 "$f")
  echo "== $label =="
  tail -n +2 "$f" | head -n -1 | sort -n | awk -v iters="$ITERS" '
    { v[NR] = $1; s += $1 }
    END {
      median = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2;
      printf "  runs=%d min=%dms median=%dms mean=%dms max=%dms\n", NR, v[1], median, s / NR, v[NR];
    }'
  tail -1 "$f"
done
