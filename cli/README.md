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
  precedence and canonicalization, instance matching/ambiguity/exit codes,
  JSON parsing. The resolver runs on injected roots and temp dirs; the
  subprocess interface is injectable, so no NixOS system and no Quickshell
  session are required.
- `make e2e` — end-to-end tests against `tests/fixtures/mock-qs`, a mock
  Quickshell executable (the CLI itself never spawns a shell). Verifies the
  exact argv vectors passed to `qs`, exit-code propagation, status/doctor
  output, store-resolution failures, ambiguity refusal, timeouts, and the
  doctor flow.
- `make check-qml` — re-extracts every `IpcHandler` target/function from
  `shell.qml` (`tests/qml_ipc.awk`) and diffs it against the compiled facade
  table (`shoji debug map`). Fails when either side drifts.

Actual results at implementation time (branch `eup`, commit `aed6ae9`):

```
unit:  232 passed, 0 failed
e2e:    59 passed, 0 failed (includes the mapping-drift check)
```

The suite was also run under AddressSanitizer + UndefinedBehaviorSanitizer:
clean (no leaks of concern, no UB, no heap errors). Runtime integration
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

Discovery always runs Quickshell's own CLI: `qs list -a -j --show-dead`
(with a graceful retry without `--show-dead` on older quickshell). Shoji
never dispatches via a bare `qs -p PATH …`, because quickshell would
**silently pick the oldest instance** of that config when several match.

Selection policy (`shoji_select_instance`):

1. Candidates are **live** instances (`pid > 0`) whose canonical
   `config_path` equals the canonical expected store path (comparison after
   `realpath` on both sides, so symlinked dev checkouts compare correctly;
   instance records whose store path has been garbage-collected still
   compare by their recorded path).
2. Exactly one candidate → selected; dispatch uses the **full instance id**.
3. None → refuse (exit 67). Diagnostics distinguish "no instances at all",
   "dead instances of this config exist" (crashed/replaced shell) and "other
   configs running" — with their paths listed.
4. More than one → refuse as ambiguous (exit 68) unless `--instance-id`
   resolves one candidate by unique prefix (the same rule `qs -i` applies;
   an ambiguous prefix is refused).
5. `--instance-id` without a matching instance → refuse (exit 67).

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
10 s) kills a hung `qs` and reports failure instead of blocking a keybind
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
  behavior is based on reading the Quickshell source (master, 0.3.x line) and
  `qs(1)`, not on running Shoji. The e2e suite validates behavior against a
  mock that mirrors the observed CLI contract (`list -a -j --show-dead`,
  `ipc -i <id> --any-display call/show`, exit codes 0/255).
- **Packaging layout is provisional.** `SHOJI_DEFAULT_STORE` exists, but the
  profile-scan candidate layouts (`share/quickshell/shoji/shell.qml`,
  `etc/xdg/quickshell/shoji/shell.qml`) are a documented guess until Lumina
  decides how Shoji is packaged. The config-link source (4) covers a
  Home Manager `home.file` style install and is likely the primary path in
  practice.
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
