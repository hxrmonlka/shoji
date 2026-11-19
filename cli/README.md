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
make            # builds build/shoji (binary at build/shoji)
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

- `make unit` — C unit tests (`build/shoji-tests`): argument parsing,
  command-to-IPC mapping, argument validation/normalization, store resolver
  precedence and canonicalization (including `XDG_CONFIG_DIRS`
  tokenization: one, several, empty entries, the directory cap), instance
  discovery failure classes and invocation counts, dead-instance
  classification (stale positive pids), invalid instance-id refusal, the
  mutable-alias identity uncertainty, JSON parsing, and complete-output
  JSON validation of every `--json` command. The resolver runs on injected
  roots and temp dirs; the subprocess interface is injectable, so no NixOS
  system and no Quickshell session are required.
- `make e2e` — end-to-end tests against `tests/fixtures/mock-qs`, a mock
  Quick executable (the CLI itself never spawns a shell). Verifies the
  exact argv vectors passed to `qs`, exit-code propagation, discovery
  failure classes (generic failures are not retried; the `--show-dead`
  compatibility probe is contained), dead-instance reporting with positive
  pids, status/doctor output, deterministic store-resolution failures via a
  nonexistent `--store`, ambiguity refusal, timeouts (including wrapper
  descendants), and the doctor flow.
- `make check-qml` — builds `obj/shoji` when needed, then re-extracts every
  `IpcHandler` target/function from `shell.qml` (`tests/qml_ipc.awk`) and diffs
  it against the compiled IPC table (`shoji debug map`). Fails when either
  side drifts. The unit test independently compares the compiled table with
  the frozen `frozen_handlers` list in `tests/test_commands.c`.

Latest validation for this patch (branch snapshot `feat/cli`):

```
GCC:    unit 424 passed; e2e 71 passed; check-qml 1 passed
Clang:  unit 424 passed; e2e 71 passed; check-qml 1 passed
ASan + UBSan: unit 424 passed; e2e 71 passed; check-qml 1 passed
```

The sanitizer build used `-fsanitize=address,undefined`. Runtime integration
against a real `qs` has NOT been tested in this phase — see "Assumptions".

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
| `--json` | Machine-readable output for `status` and `instance list/current/inspect` |
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

### IPC inspection

```sh
shoji ipc show                       # targets/functions of the selected instance
shoji ipc call <target> <function> [arguments...]   # raw pass-through
```

`ipc call` is the raw dispatcher escape hatch; targets and functions are
validated by the running shell itself (unknown names produce exit code 65).

### Facade commands

Friendly commands mapping 1:1 onto the existing `IpcHandler`s in `shell.qml`
(no shell behavior is implemented here):

```sh
shoji island toggle | open | close | tab <name>     # tab: launcher|calendar|monitor|
                                                    # wallpapers|clipboard|color
                                                    # (+media|control when merged)
shoji wallpaper toggle | open | close | set <path> | next | previous | random
shoji media toggle | open | close | play-pause | next | previous
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

Examples:

```sh
shoji island tab calendar
shoji wallpaper set /path/to/image.jpg
shoji media play-pause
shoji awake on 30
shoji notifications dnd off
shoji theme current
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

Discovery always runs Quickshell's own CLI, in two steps:

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
   diagnostics; the failure can never mask or alter the live result.

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
2. Exactly one candidate → selected; dispatch uses the **full instance id**.
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

Dispatch runs `qs ipc -i <full-id> --any-display call <target> <function>
[arguments…]` — an argument vector via fork+execvp, never a shell. The full
id makes the call unambiguous; `--any-display` makes it robust in contexts
without `WAYLAND_DISPLAY` (systemd units, ssh sessions) and is safe because
the full id already pins the instance. When an explicit `--instance-id`
points at a foreign configuration, shoji warns loudly on stderr and still
dispatches (the user asked for that instance), but it never looks like a
match in any output.

Subprocess results are preserved: quickshell's stdout/stderr are relayed
verbatim, its exit status drives the exit code, and stderr is additionally
classified (`Target not found.` / `Function not found.` / argument parse
errors → exit 65). A configurable timeout (`SHOJI_QS_TIMEOUT_MS`, default
10 s) kills the dedicated subprocess process group (including descendants
started by a `--qs` wrapper) and reports failure instead of blocking a keybind
forever.

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
    instances.c/.h discovery (`qs list -a -j`), matching, selection policy
    dispatch.c/.h pipeline + `qs ipc` subprocess dispatch
    proc.c/.h     fork/execvp capture, timeout, injectable spawn interface
    json.c/.h     minimal JSON parser for `qs list -j`
    util.c/.h     alloc, string buffers, paths, diagnostics
    report.c/.h   status, doctor, instance commands
    exitcodes.h   exit-code table
  tests/
    test_*.c      unit suites (no external framework)
    run_e2e.sh    end-to-end suite vs mock quickshell
    qml_ipc.awk   shell.qml handler extractor for the drift check
    fixtures/     mock-qs
```

## Assumptions and unresolved issues

- **Runtime integration is untested.** Every claim above about real `qs`
  behavior is based on reading the Quickshell source (master, 0.3.x line:
  `src/launch/command.cpp`, `src/launch/launch.cpp`, `src/launch/parsecommand.cpp`,
  `src/core/paths.cpp`, `src/core/instanceinfo.cpp`) and `qs(1)`, not on
  running Shoji. The e2e suite validates behavior against a mock that
  mirrors the observed CLI contract (`list -a -j [--show-dead]`,
  `ipc -i <id> --any-display call/show`, exit codes 0/255).
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
- Settings synchronization and a real settings manager (only the existing
  `settings` IPC pass-through is exposed).
- Theme generation / matugen integration (only the existing `theme` IPC
  pass-through is exposed).
- Screenshot management (list/inspect captures; only the trigger commands
  exist).
- Keybind generation and MangoWM integration files.
- Greeter (`greeter.qml`) support and multi-config awareness.
- Nix packaging of shoji-cli itself (Lumina's job; the hook is ready).
- Richer `ipc show` parsing, completion scripts, man page.
