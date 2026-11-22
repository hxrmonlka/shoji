# shoji-cli

A thin C command line interface over Quickshell for the Shoji shell. It parses
and validates commands, resolves which immutable Nix store path belongs to the
active Shoji generation, identifies the running Quickshell instance for that
configuration, and dispatches IPC calls through Quickshell's native CLI
(`qs`). It implements **no second IPC protocol** and **no instance-management
of its own** — Quickshell remains the authority.

- Language: C11, POSIX only, **no external dependencies**.
- Build system: plain Makefile.
- Nothing in this directory touches the QML config at the repository root.

## Build

```sh
cd cli
make            # builds obj/shoji (binary at obj/shoji)
make clean
```

Requirements: any C11 compiler (cc/gcc/clang) and make.

### Packaging hook (Lumina / Alice)

When a derivation packages shoji-cli, bake the exact Shoji store path in so
the resolver can use it as the build-time source:

```nix
stdenv.mkDerivation {
  # ...
  makeFlags = [ "PREFIX=$(out)" ];
  NIX_CFLAGS_COMPILE = [ ''-DSHOJI_DEFAULT_STORE="${shoji}/share/quickshell/shoji"'' ];
}
```

The double quotes belong inside the macro definition: cc-wrapper splits
`NIX_CFLAGS_COMPILE` on whitespace without stripping quotes, so the compiler
sees `-DSHOJI_DEFAULT_STORE="/nix/store/…"` and the path arrives as a proper
C string literal. Without the inner quotes (`-DSHOJI_DEFAULT_STORE=/nix/…`)
the path is parsed as C tokens and compilation fails.

`SHOJI_DEFAULT_STORE` must point at the Shoji configuration directory (or its
`shell.qml`) for the generation the CLI belongs to. Without it, resolution
falls back to the active config link and profile scan (see below).

### Install

```sh
make install PREFIX=/usr/local      # -> $PREFIX/bin/shoji
```

## Test

```sh
make test        # unit tests + end-to-end tests + shell.qml mapping check
```

- `make unit` — C unit tests (`obj/shoji-tests`): argument parsing,
  command-to-IPC mapping, argument validation/normalization, store resolver
  precedence and canonicalization (including `XDG_CONFIG_DIRS`
  tokenization: one, several, empty entries, the directory cap), instance
  discovery failure classes and invocation counts, dead-instance
  classification (stale positive pids), invalid instance-id refusal, the
  mutable-alias identity uncertainty, live-snapshot reconciliation (rows
  that exit between listings, refreshed liveness state), the fast dispatch
  pipeline (exact spawn count and order: one listing then one IPC;
  fallback enrichment reusing the snapshot; terminal discovery failures),
  JSON parsing,
  JSON serialization (canonical sorted-key emission, number rendering,
  string escaping), settings payload helpers (category matching,
  constraint rendering, display values), managed settings command parsing
  (kinds and arity) and the managed settings command behavior end to end on
  an injected spawn interface (list table and `--json` output, category
  filtering, canonical dump/export bytes and determinism, get relay and
  empty-value disambiguation, unknown-key rejection, set success,
  set rejection diagnostics, subprocess counts per failure path),
  embedded NUL rejection in captured output, SIGCHLD re-establishment
  under an ignoring parent, timeout boundary conditions, and
  complete-output JSON validation of every `--json` command. The resolver
  runs on injected roots and temp dirs; the subprocess interface is
  injectable, so no NixOS system and no Quickshell session are required.
- `make e2e` — end-to-end tests against `tests/fixtures/mock-qs`, a mock
  Quick executable (the CLI itself never spawns a shell). Verifies the
  exact argv vectors passed to `qs`, exit-code propagation, discovery
  failure classes (generic failures are not retried; the `--show-dead`
  compatibility probe is contained), dead-instance reporting with positive
  pids, malformed (NUL-containing) listing rejection, dispatch with a
  mismatched display scope, the SIGCHLD-ignored-parent leg (via
  `fixtures/spawn_helper.c exec-ignchld`, built by the target),
  status/doctor output, deterministic store-resolution failures via a
  nonexistent `--store`, ambiguity refusal, timeouts (including descendants that remain in the dedicated process
  group), the doctor flow, and the settings management commands (list,
  list filtering and `--json`, dump bytes and determinism, export bytes,
  get, set with and without rejection, passthrough preservation, arity
  errors, subprocess counts, and the no-runtime-support failure class).
- `make integration` — real-Quickshell tests (`tests/run_integration.sh`);
  needs a running Wayland session and `qs` (or `$SHOJI_INTEGRATION_QS`),
  otherwise it skips. Launches a real instance, dispatches IPC through
  shoji from a mismatched `WAYLAND_DISPLAY` scope, proves raw `qs ipc -i`
  is display-bound as the negative control, and kills the instance.
- `make check-qml` — builds `obj/shoji` when needed, then re-extracts every
  `IpcHandler` target/function from `shell.qml` (`tests/qml_ipc.awk`) and diffs
  it against the compiled IPC table (`shoji debug map`). Fails when either
  side drifts. The unit test independently compares the compiled table with
  the frozen `frozen_handlers` list in `tests/test_commands.c`.

Baseline validation before the launch-wrapper and environment-isolation changes:

```
GCC:       unit 455 passed; e2e 80 passed; check-qml 1 passed
Clang:     unit 455 passed; e2e 80 passed; check-qml 1 passed
ASan+UBSan: unit 455 passed; e2e 80 passed; check-qml 1 passed
```

The sanitizer build used `-fsanitize=address,undefined`.

Baseline after the CodeRabbit review round (live-snapshot reconciliation,
NUL rejection, SIGCHLD disposition, timeout budget, pid dispatch):

```
GCC:       unit 531 passed; e2e 116 passed; check-qml 1 passed
ASan+UBSan: unit 531 passed; e2e 116 passed; check-qml 1 passed
```

The sanitizer build used `-fsanitize=address,undefined`.

After the Phase II settings management round (GCC 14.2 in CI; the ASan+UBSan
build used `-fsanitize=address,undefined`):

```
GCC:        unit 755 passed; e2e 173 passed; check-qml 1 passed
ASan+UBSan: unit 755 passed; e2e 173 passed; check-qml 1 passed
```

Clang was not exercised for this round (no clang in the test environment);
the earlier rounds stayed warning-free under both compilers and no
compiler-specific constructs were added.

## Command reference

```
shoji [global options] <command> [arguments]
```

Global options:

| Option | Meaning |
| --- | --- |
| `--store PATH` | Resolve Shoji from an explicit path (directory or `shell.qml`); overrides every other source |
| `--instance-id ID` | Operate on the given instance (unique prefix of the id, like `qs -i`) |
| `--qs PATH` | Quickshell executable; default `qs` on `$PATH`, env `SHOJI_QS_BIN` |
| `--json` | Machine-readable output for `status`, `instance list/current/inspect`, and `settings list` |
| `-h/--help`, `-V/--version` | Help / version |

Diagnostics go to **stderr**, command output to **stdout**, so scripting stays
possible.

### General

```sh
shoji --help
shoji --version
shoji status        # expected store path + source, running instances, verdict
shoji doctor        # checks CLI, qs binary, store path, instance, IPC access
```

`status --json` emits `{"cli", "quickshell", "store", "instances", "verdict"}`
with verdicts `match`, `no-match`, `no-instance-dead-only`, `ambiguous`,
`override-mismatch`, `selected-instance-dead`, `unknown-store`,
`discovery-failed`.

Every `--json` output is a single valid JSON value: `instance inspect
--json` adds `"ipc_accessible"` as a JSON boolean (true/false, for both
successful and failed probes) INSIDE the instance object. The unit suite
parses each complete command output (not substrings) against the bundled
JSON parser.

### Launch

```sh
shoji run
shoji run --daemonize --no-duplicate
shoji run --verbose --log-times
shoji run -- --help
```

`run` resolves the same Shoji store configuration used by `status`, then
executes Quickshell with `--path <resolved shell.qml>`. Quickshell launch
options are forwarded unchanged. Configuration selectors (`--path`, `--config`,
and `--manifest`, including their short forms) are reserved by Shoji; use
`--store` to select a different Shoji generation. The `--` separator allows
Quickshell flags that overlap with Shoji's global flags to be forwarded.

For MangoWC autostart, use `shoji run --daemonize --no-duplicate` instead of
launching the mutable Home Manager configuration symlink directly. A shell
already running from that symlink must be restarted once after switching the
autostart command; its recorded launch path cannot be changed in place.

### Instance management

```sh
shoji instance list          # all running quickshell instances, match column
shoji instance list --json
shoji instance current       # the instance shoji would dispatch to
shoji instance inspect       # details + IPC accessibility probe
```

Exposed per instance: instance id, pid (or `(dead)`), `shell_id`, config path,
launch time, and whether it matches the currently expected Shoji
configuration.

### Kill

```sh
shoji kill                       # stop the newest instance of the expected configuration
shoji kill --instance-id <prefix>  # stop exactly that instance
shoji kill --all                 # stop every instance of the expected configuration
```

`kill` stops a running Shoji instance by dispatching `qs kill --pid <pid>`
through the same spawn interface as every other command. Shoji itself never
sends signals; quickshell remains the authority for instance termination.

The target set is the live instances with a valid instance id whose
configuration identity is *established* against the expected store path
(`shoji_instance_matches_config` == 1). Dead rows have no IPC endpoint to
connect to, uncertain-generation rows and rows without a valid id are never
touched.

- Bare `shoji kill`: exactly one target is killed; with several targets the
  most recently launched one is killed (highest pid — `launch_time` has no
  timezone and is not used for ordering); with none, exit 67 plus the usual
  diagnostics (dead / uncertain / invalid-id counts and the other running
  instances).
- `--instance-id <prefix>` resolves by unique prefix, the same rule `qs -i`
  applies; an ambiguous prefix exits 68. The selected instance must provably
  run the expected configuration: a foreign configuration and an
  unestablishable alias identity both exit 67. Kill is destructive, so —
  unlike IPC dispatch, which warns and proceeds on explicit foreign
  selection — `kill` refuses. `qs kill -i <prefix>` remains the manual escape
  hatch for foreign instances.
- `--all` kills every target, one `qs kill --pid <pid>` each; the exit code
  is 0 only when every kill succeeded. Combined with `--instance-id` it is a
  usage error (64).
- The store path must resolve: without it, `kill` exits 66 even with an
  explicit `--instance-id`, because there is no expected configuration to
  verify identity against.
- quickshell's stdout/stderr (`Killed <id>`) are relayed verbatim; its exit
  status drives the exit code (69 spawn failure, 1 timeout or failure, 70
  internal).

A generation switch is `shoji kill` followed by
`shoji run --daemonize --no-duplicate`.

### IPC inspection

```sh
shoji ipc show                       # targets/functions of the selected instance
shoji ipc call <target> <function> [arguments...]   # raw pass-through
```

`ipc call` is the raw dispatcher escape hatch; targets and functions are
validated by the running shell itself (unknown names produce exit code 65).

### Settings management

```sh
shoji settings list [category]     # all settings with metadata; optional
                                   # category filter (id or title, case-
                                   # insensitive), --json supported
shoji settings list --json
shoji settings dump                # complete effective settings as JSON
shoji settings export              # persisted user overrides as JSON
shoji settings get <key>           # one effective value
shoji settings set <key> <value>   # validated by the running shell
shoji settings reset | reload | open | close | toggle   # pass-through
```

`list`, `dump`, `export`, `get` and `set` are managed commands: they call the
matching `settings` IPC functions of the running shell, validate the JSON
payload locally, and format it. The schema itself is never duplicated in C —
`Commons/Settings.qml` remains the single source of truth, and the CLI always
queries the running runtime (never `~/.local/state/shoji/settings.json`), so
pending GUI changes made within the 250 ms save debounce are included.
Nothing reads or writes configuration files, in the Nix store or elsewhere.

`settings list` prints an aligned table with one row per setting:

```
KEY             CATEGORY  TYPE    DEFAULT  CURRENT  CONSTRAINTS        DESCRIPTION
pillHeight      island    int     44       44       32..72 step 1
mergeCircles    features  bool    false    true
searchEngine    features  choice  kagi     kagi     kagi|google        Used by the >w prefix.
```

Columns: key, category id, type (`int`, `bool`, `string`, `scheme`,
`choice`), default value, current effective value, constraints (numeric
ranges with step, choice option values; `-` when unconstrained) and the
description. `settings list <category>` filters rows by category id or
title (case-insensitive); an unknown category exits 64 and lists the valid
ones. `settings list --json` emits the runtime payload as one compact JSON
object (`{"categories": [...], "settings": [...]}`) with the rows filtered
by the category when one is given; the object shape is stable for
scripting.

`settings dump` prints every setting with its effective value (defaults
applied) as pretty-printed JSON with keys sorted by strcmp, one trailing
newline, no other bytes. Running it twice produces identical output. Piping
it through `jq` or comparing generations with `diff` works.

`settings export` prints only the persisted user override map — the same
shape `Commons/Settings.qml` writes to `~/.local/state/shoji/settings.json`
(`JSON.stringify(values, null, 2)` plus newline). The CLI re-serializes with
sorted keys for determinism; the file content written by the shell uses
insertion order, but both are plain JSON objects that `restore()` accepts
unchanged, so export output can be redirected into a state file or synced
by the Alice snapshot scripts. Effective settings (dump) and persisted
overrides (export) stay distinct: keys absent from the export still appear
in the dump with their defaults.

`settings get <key>` relays the effective value (the same output as
`qs ipc call settings get`). When the shell answers with an empty string
the CLI asks the runtime whether the key exists: known keys with an empty
string value (like `aliceDotfiles`) print an empty line and exit 0, unknown
keys are rejected with exit 65.

`settings set <key> <value>` dispatches `settings.set` and interprets the
boolean result quickshell prints: `true` relays and exits 0, `false` is
turned into a diagnostic and exit 65. Validation happens in the running
shell — never in the CLI:

- Unknown keys are rejected (`unknown setting '<key>'`).
- Booleans accept `true/false/1/0/on/off/yes/no` in any casing.
- Choice settings accept only declared option values
  (`invalid value ... expected one of kagi|google`).
- Numeric settings must be finite numbers within the declared `min`/`max`
  (`expected a number in 32..72 step 1`); `Settings.set()` now enforces the
  bounds at set time instead of silently clamping at read time, so invalid
  values are never persisted. Values outside the range that are already in
  an existing settings file keep working — `get()` still clamps them for
  display and use.

A rejected `set` (or an ambiguous empty `get`) costs one extra IPC call: the
CLI reuses the discovery snapshot and calls `settings list` once to tell
"unknown key" apart from "invalid value" without duplicating the schema. The
success path never pays it.

`reset`, `reload`, `open`, `close` and `toggle` remain raw pass-throughs and
relay quickshell's output verbatim.

These commands need the matching shell functions (`settings.list`,
`settings.dump`, `settings.exportOverrides`); pointing a new CLI at an older
Shoji generation fails with the standard "Function not found." classification
(exit 65).

### Facade commands

Friendly commands mapping 1:1 onto the existing `IpcHandler`s in `shell.qml`
(no shell behavior is implemented here):

```sh
shoji island toggle | open | close | tab <name>     # tab: launcher|calendar|monitor|
                                                    # wallpapers|clipboard|color
                                                    # (+media|control when merged)
shoji wallpaper toggle | open | close | set <path> | next | previous | random
shoji media toggle | open | close | play-pause | next | previous | player-next | player-previous
shoji control toggle | open | close
shoji power toggle | open | close
shoji spotlight toggle | open | close
shoji lock activate
shoji screenshot fullscreen | window | region | output <name>
shoji awake toggle | on <minutes> | off
shoji mic toggle | mute | unmute | state
shoji notifications clear | toggle-dnd | dnd <true|false|on|off> | hide-popup
shoji osd volume <steps> | brightness <steps>
shoji clipboard toggle | open | close
shoji monitor toggle | open | close
shoji colorpicker copy | pick | gui | cancel | hex
shoji settings get <key> | set <key> <value> | reset | reload | open | close | toggle
shoji theme scheme <name> | mode <name> | current | list | preview
```

The settings subcommands `list`, `dump`, `export`, `get` and `set` are
handled by the settings manager described above, not as raw pass-throughs.

Examples:

```sh
shoji island tab calendar
shoji wallpaper set /path/to/image.jpg
shoji media play-pause
shoji awake on 30
shoji notifications dnd off
shoji theme current
shoji settings list features
shoji settings set pillHeight 48
shoji settings dump > effective.json
shoji settings export > settings-overrides.json
shoji --store /nix/store/…-shoji/share/quickshell/shoji status
shoji --instance-id abc123 ipc show
```

Dash-cased command names map to quickshell camelCase functions explicitly in
the static table (`media play-pause` -> `media.playPause`); nothing is
guessed at runtime. Integer arguments are validated client-side; booleans are
normalized to `true`/`false` before dispatch.

`shoji debug map` dumps the table as TSV (`group, name, target, function,
argspecs`) — this is what `make check-qml` compares against `shell.qml`.

## Store resolution (generation-aware)

Shoji's configuration is immutable in the Nix store. The resolver decides
which store path belongs to the active generation. Sources, in documented
precedence order:

1. **`--store PATH`** — explicit override. Accepts a directory or a
   `shell.qml`; anything else is rejected.
2. **`SHOJI_STORE_PATH`** — runtime environment override (testing and custom
   deployments).
3. **`SHOJI_DEFAULT_STORE`** — compile-time reference baked in by the
   packaging derivation (Lumina). This is the "Nix-generated, build-time
   reference to the corresponding Shoji derivation": the derivation for
   shoji-cli literally references the Shoji derivation, so the store path is
   part of the binary. Not set until Lumina packages the CLI.
4. **Active config link** — `$XDG_CONFIG_HOME/quickshell/shoji/shell.qml`
   (then `XDG_CONFIG_DIRS`). This covers Home Manager installs that symlink
   a quickshell config into place; `realpath` resolves the symlink back to
   the store path.
5. **Profile scan** — active system / Home Manager profiles, in order:
   `$HOME/.nix-profile`, `$HOME/.local/state/nix/profiles/profile`,
   `/etc/profiles/per-user/$USER`,
   `/nix/var/nix/profiles/per-user/$USER/profile`,
   `/run/current-system` **(last)**. Inside each root the candidates are
   `share/quickshell/shoji/shell.qml` and `etc/xdg/quickshell/shoji/shell.qml`;
   a bare `share/quickshell/shell.qml` is accepted only when its content
   identifies it as Shoji (contains the `qs.Commons` / `qs.Island` import).
   `SHOJI_PROFILE_ROOTS` (colon-separated) replaces the root list for tests
   and custom setups.

`/run/current-system` is deliberately last: Shoji may be installed through
Home Manager rather than the NixOS system profile.

Properties:

- **No `nix eval`** — resolution is plain filesystem checks; cheap enough to
  run for every IPC command.
- **Canonicalization** — every candidate goes through `realpath(3)`; a
  directory gets `shell.qml` appended; the result must be an existing regular
  file. Invalid/missing paths are reported, never guessed around.
- **Distinguishability** — the resolved *expected* path (plus the source that
  produced it) is always reported separately from the *actual* path a running
  instance recorded at launch. Older generations and development checkouts
  show up as non-matching instances in `status` / `instance list`.

## Instance selection

Discovery always runs Quickshell's own CLI, through two variants:

1. `qs list -a -j` is the **authoritative live listing**. Upstream outputs
   only instances that currently hold their fcntl instance lock
   (`src/launch/command.cpp listInstances`, `src/core/paths.cpp
   collectInstances`) — this listing alone decides what shoji may dispatch
   to. A failure of this command is never retried and never masked: a
   timeout stays a timeout (exit 1), a failed exec stays a missing
   executable (exit 69), an internal subprocess failure stays internal
   (exit 70), and a generic quickshell rejection keeps the documented
   generic failure behavior (exit 1).
2. `qs list -a -j --show-dead` is a **strictly additive diagnostics probe**
   for dead instances. Rows it reports that the live listing did not report
   are dead, regardless of their JSON pid, and are never IPC candidates.
   When this probe fails — most commonly because the running quickshell
   build does not support `--show-dead` — discovery continues without dead
   diagnostics; the failure can never mask or alter the live result. When
   the probe succeeds, a fresh live listing always reclassifies and
   confirms its rows.

**Fast dispatch path.** Ordinary IPC commands (`shoji island toggle`,
`shoji wallpaper next`, other facade commands, `shoji ipc call`,
`shoji ipc show`) run the authoritative live listing **exactly once** and
dispatch from that snapshot: a successful IPC needs one listing subprocess
plus one IPC subprocess, nothing else. The dead-instance probe and the
refresh never enter this hot path. When selection cannot establish a
dispatchable target on the snapshot (no match, ambiguity, uncertain
generation, invalid ids), the same snapshot is completed **in place** with
the dead-instance diagnostics and the recheck described above, and
selection runs again — identical to the full procedure's final listing, so
failure reporting (dead instances, uncertain aliases, ambiguous matches)
does not change. The fallback only ever enriches an already-successful
listing; it can never turn a failed live listing into a discovery success.

**Full diagnostic path.** `status`, `doctor`, `instance list` and
`instance inspect` always run the complete procedure (live listing, dead
probe, recheck) because dead-instance diagnostics are part of their
output. `kill` and `instance current` keep it too: kill is destructive and
not latency-critical, and its refusal reporting relies on the dead
diagnostics.

Dead-instance semantics: upstream serializes the launch-time
`InstanceInfo` into the listing JSON, so a dead instance's `pid` field can
stay **positive** after a crash; only the absence from the live listing
(`InstanceLockInfo::pid` from the fcntl lock) marks it dead.

When no instance exists, quickshell prints its bare `No running instances.`
log line instead of JSON; both that line and empty output are accepted as an
empty list. Shoji never dispatches via a bare `qs -p PATH …`, because
quickshell **silently picks the oldest instance** of that config when several
match.

Selection policy (`shoji_select_instance`):

1. Candidates are **live** instances whose configuration identity is
   established against the expected store path and whose instance id is
   valid (see below).
   - **Configuration identity**: the recorded `config_path` is quickshell's
     launch-time record — the absolute path given to `-p`/`-c`, NOT
     symlink-resolved (`locateConfigFile` ends in
     `QFileInfo(path).absoluteFilePath()`), and quickshell exposes no
     launch-time canonical path. A recorded path that exactly equals the
     canonical expected path is a certain match. If the recorded path differs
     but currently resolves to the expected path through a symlink or other
     alias, the original launch-time target cannot be established: it is
     **uncertain** and the row is never auto-selected. Shoji deliberately does
     not infer the launch-time target from symlink mtimes or `launch_time`;
     the latter has no timezone, so timestamp comparisons are not reliable.
   - **Instance ids**: `qs ipc -i` treats an empty selector as absent and
     silently falls back to config-based selection
     (`selectInstance`), so rows with absent, empty or otherwise invalid ids
     (non-empty, no whitespace/control characters) are never selected and
     never dispatched; shoji reports them for diagnostics instead.
2. Exactly one candidate → selected; dispatch uses the **instance pid**.
3. None → refuse (exit 67). Diagnostics distinguish "no instances at all",
   "dead instances of this config exist", "live rows of uncertain
   generation" and "rows without a valid id" — with their paths listed.
4. More than one → refuse as ambiguous (exit 68) unless `--instance-id`
   resolves one candidate by unique prefix (the same rule `qs -i` applies;
   an ambiguous prefix is refused).
5. `--instance-id` without a matching instance → refuse (exit 67).

In practice this means: after a generation switch, an instance of the OLD
generation is never silently dispatched to by the NEW CLI — it either does
not match, or is reported as uncertain and requires an explicit
`--instance-id <id prefix>`.

Dispatch runs `qs ipc --pid <pid> call <target> <function>
[arguments…]` — an argument vector via fork+execve, never a shell. The pid
selects the exact instance shoji validated, and it keeps discovery and
dispatch in compatible display scopes:

- Discovery (`qs list -a -j`) is cross-display: upstream collects instances
  for every Wayland display when `-a` is given.
- Upstream 0.3.0 filters by display ONLY in the id- and config-based
  selection paths of `selectInstance` (`src/launch/command.cpp`): an
  instance on another display lands in the mismatched set and `qs ipc -i
  <id>` fails with "No running instances on the current display". The pid
  branch opens `by-pid/<pid>` directly with no display filter, and the IPC
  socket itself (`QsPaths::ipcPath`) is derived from the instance id
  recorded in that lock, so `--pid` reaches the instance on any display.
- `--any-display` is NOT a dispatch option: the config-selection group it
  belongs to excludes the instance-selection group (`-i`, `--pid`) in
  `src/launch/parsecommand.cpp`, so real `qs` rejects the combination.
- Identity stays shoji-side: selection, generation matching, dead refusal
  and ambiguity handling run against the listing before any pid is handed
  to quickshell, and qs re-checks the lock (dead pid → clean failure).

`tests/run_integration.sh` exercises dispatch from a mismatched
`WAYLAND_DISPLAY` against a real instance and asserts raw `qs ipc -i` fails
in the same setup (negative control). When an explicit `--instance-id`
points at a foreign configuration, shoji warns loudly on stderr and still
dispatches (the user asked for that instance), but it never looks like a
match in any output.

Subprocess results are preserved: quickshell's stdout/stderr are relayed
verbatim, its exit status drives the exit code, and stderr is additionally
classified (`Target not found.` / `Function not found.` / argument parse
errors → exit 65). A configurable timeout (`SHOJI_QS_TIMEOUT_MS`, default
10 s) sends SIGKILL to the dedicated subprocess process group and reports
failure instead of blocking a keybind. Descendants that deliberately leave
that process group (for example, by starting a new session) are not covered.
forever.

`SHOJI_QS_TIMEOUT_MS` is validated only by commands that can spawn
quickshell; `--help`, `--version` and `debug map` stay usable with an
invalid value, every other command (including `run`) exits 64. The timeout
covers the whole subprocess lifecycle (handshake, drain, reap): waits are
bounded by the remaining budget, an exit inside the deadline is a success
even when the polling wake-up lands past the boundary, and an exit past it
stays a timeout. The CLI also re-establishes SIGCHLD to SIG_DFL before
spawning, so a parent that ignored SIGCHLD cannot break reaping.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | success |
| 1 | quickshell process failure / generic error / timeout |
| 64 | invalid command or argument (usage) |
| 65 | invalid IPC target, function or argument |
| 66 | Shoji store path unresolved, missing or invalid |
| 67 | no matching running instance |
| 68 | multiple matching instances (ambiguous) |
| 69 | quickshell not installed or unavailable |
| 70 | internal error |

Keep this table stable — MangoWM keybind integrations depend on it.

## Layout

```
cli/
  Makefile
  src/
    main.c        entry point; wires parse -> dispatch/report
    cli.c/.h      argument parsing, help text
    ipctable.c/.h static facade table (target/function/argspec per command)
    resolver.c/.h generation-aware store resolution
    instances.c/.h discovery (`qs list -a -j` fast path + diagnostic
                   probes), matching, selection policy
    dispatch.c/.h pipeline (fast + diagnostic) + `qs ipc` subprocess dispatch
    settings.c/.h settings management (list/dump/export/get/set over the
                   settings IPC functions; JSON validation and formatting)
    proc.c/.h     fork/execvp capture, timeout, injectable spawn interface
    json.c/.h     minimal JSON parser and writer for `qs list -j` and the
                   settings payloads
    util.c/.h     alloc, string buffers, paths, diagnostics
    report.c/.h   status, doctor, instance commands
    exitcodes.h   exit-code table
  tests/
    test_*.c      unit suites (no external framework)
    run_e2e.sh    end-to-end suite vs mock quickshell
    run_integration.sh  real-quickshell suite (skips without a session)
    qml_ipc.awk   shell.qml handler extractor for the drift check
    fixtures/     mock-qs, spawn-helper
```

## Assumptions and unresolved issues

- **Runtime integration is partially scripted.** Every claim above about
  real `qs` behavior is based on reading the Quickshell source (v0.3.0,
  checked against 0.3.2: `src/launch/command.cpp`, `src/launch/launch.cpp`,
  `src/launch/parsecommand.cpp`, `src/core/paths.cpp`,
  `src/core/instanceinfo.cpp`) and `qs(1)`. The e2e suite validates
  behavior against a mock that mirrors the observed CLI contract (`list -a
  -j [--show-dead]`, `ipc --pid <pid> call/show`, `kill --pid <pid>`, exit
  codes 0/255); `make integration` runs the same flow against a real qs
  when a Wayland session is available and was not executed as part of the
  last automated pass.
- **Launch-time identity is intentionally conservative**: the lock file
  stores the launch-time `InstanceInfo` (`config_path` = the path as given,
  absolute but not symlink-resolved; `launch_time` = local-time ISO string
  of second precision). Shoji does not use `launch_time` or symlink mtimes to
  reconstruct the original target. A recorded path that currently resolves
  through an alias to the expected configuration remains uncertain and
  requires explicit `--instance-id`, even if the alias may never have moved.
- **Packaging layout is provisional.** `SHOJI_DEFAULT_STORE` exists, but the
  profile-scan candidate layouts (`share/quickshell/shoji/shell.qml`,
  `etc/xdg/quickshell/shoji/shell.qml`) are a documented guess until Lumina
  decides how Shoji is packaged. The config-link source (4) covers a
  Home Manager `home.file` style install and is likely the primary path in
  practice; instances whose recorded launch path uses that mutable link are
  conservatively treated as uncertain and require explicit `--instance-id`
  (see selection policy).
- `qs ipc call` return values are relayed and (for the settings commands)
  interpreted per the verified upstream contract: quickshell 0.3.0 and
  0.3.2 print the stringified return value of non-void functions plus a
  newline to stdout and exit 0 (`bool` -> `true`/`false`, `string` -> the
  text), void functions print nothing, and failures exit 255 after writing
  `Target not found.` / `Function not found.` / argument-parse errors to
  stderr (`src/launch/command.cpp`, `src/io/ipccomm.cpp`,
  `src/io/ipc.cpp`). `shoji settings set` treats a captured `false` as a
  rejected value, and anything else as a broken runtime contract (exit 1).
- `qs list -j` does not include the display connection, so shoji matches
  across displays and cannot name an instance's display in diagnostics.
  Multi-instance ambiguity is handled by refusal + `--instance-id`.
- `qs ipc show` output is relayed verbatim; parsing it into richer forms is
  Phase II territory.
- `island tab` names are passed through; the QML side silently ignores
  unknown tab ids. Valid ids: `launcher calendar monitor wallpapers clipboard
  color` (+ `media control` when `mergeCircles` is on).
- `qs` exit statuses other than 0/255 are all treated as generic failures
  (exit 1) after stderr classification.
- Subprocess lifecycle: descriptors are initialized to -1 and every cleanup
  path closes only owned descriptors; capture descriptors are kept above the
  standard descriptor numbers; an exec handshake that never resolves
  releases the parent's capture ends before returning. Timeout cleanup sends
  SIGKILL to the dedicated process group, then reaps the direct child with a
  bounded 1 s grace instead of an unconditional blocking wait. Setup failures
  are returned to the caller, and the child reports dup2/execvp failures
  with a complete, retried errno payload that the parent cannot mistake for
  a successful exec.

## Deliberately deferred to Phase II

- Event monitoring / `qs ipc wait|listen` exposure.
- Settings synchronization into dotfiles (only inspection, export and the
  existing `settings` pass-through are exposed; the Alice snapshot scripts
  own the sync direction).
- Theme generation / matugen integration (only the existing `theme` IPC
  pass-through is exposed).
- Screenshot management (list/inspect captures; only the trigger commands
  exist).
- Keybind generation and MangoWM integration files.
- Greeter (`greeter.qml`) support and multi-config awareness.
- Nix packaging of shoji-cli itself (Lumina's job; the hook is ready).
- Richer `ipc show` parsing, completion scripts, man page.
