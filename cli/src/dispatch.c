#define _POSIX_C_SOURCE 200809L

#include "dispatch.h"
#include "exitcodes.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Dispatch selector: upstream quickshell 0.3.0 resolves `--pid` from the
 * instance lock directory alone (selectInstance pid branch, no display
 * filtering), so it reaches instances on any Wayland display. The id
 * selector (`-i`) is display-scoped and `--any-display` cannot be combined
 * with it (CLI11 group excludes in src/launch/parsecommand.cpp), so ids
 * cannot be used for cross-display dispatch. The pid is the one shoji
 * validated during discovery and selection; qs refuses dead locks itself.
 * Returns the argv selector string in `buf`. */
static const char *pid_selector(char *buf, size_t size, const struct shoji_instance *inst)
{
        snprintf(buf, size, "%ld", inst->pid);
        return buf;
}

void shoji_context_init(struct shoji_context *ctx, const struct shoji_options *opts)
{
        memset(ctx, 0, sizeof(*ctx));
        ctx->spawn = shj_proc_run_qs;
        ctx->spawn_user = NULL;
        if (opts && opts->qs_bin)
                ctx->qs_bin = opts->qs_bin;
        else {
                const char *env = getenv("SHOJI_QS_BIN");

                ctx->qs_bin = env && *env ? env : "qs";
        }
}

void shoji_context_resolve_store(struct shoji_context *ctx,
                                 const struct shoji_options *opts)
{
        struct shoji_resolver_env env;

        memset(&ctx->store, 0, sizeof(ctx->store));
        ctx->have_store = 0;
        shoji_resolver_env_init(&env, opts ? opts->store_override : NULL);
        if (shoji_resolve_store(&env, &ctx->store) == 0)
                ctx->have_store = 1;
}

static void warn_timeout(void)
{
        long ms = shj_proc_get_timeout_ms();

        if (ms > 0)
                shj_hint("quickshell did not respond within %ld ms "
                         "(SHOJI_QS_TIMEOUT_MS overrides the timeout)", ms);
}

static void store_unresolved_hints(void)
{
        shj_hint("resolve the store path with --store /path/to/shoji (directory or shell.qml),");
        shj_hint("set SHOJI_STORE_PATH, or install shoji-cli through the packaging "
                 "derivation so SHOJI_DEFAULT_STORE is baked in.");
}

void shoji_print_instance_line(const struct shoji_instance *inst, const char *mark)
{
        fprintf(stderr, "  %s %-20s pid %-8ld %s%s\n",
               mark ? mark : " ",
               inst->id && *inst->id ? inst->id : "(no valid id)",
               inst->pid,
               inst->dead ? "(dead) " : "",
               inst->config_path ? inst->config_path : "?");
}

static int selection_is_dispatchable(const struct shoji_pipeline *pl)
{
        return pl->sel.status == SHOJI_SELECT_OK && pl->sel.selected &&
               !pl->sel.selected->dead;
}

/* Shared pipeline body. `diagnostic` selects the discovery variant:
 *
 *   diagnostic = 1  full discovery (live listing, additive --show-dead
 *                   probe, fresh live recheck). Used by status, doctor,
 *                   instance list and instance inspect.
 *   diagnostic = 0  fast path: exactly one authoritative live listing, then
 *                   selection. When a target is required and selection still
 *                   cannot establish a dispatchable instance, the SAME
 *                   snapshot is completed in place with the dead-instance
 *                   diagnostics (shoji_discover_instances_enrich) and
 *                   selection runs again on the enriched list -- identical
 *                   to the full path's final state, without ever re-running
 *                   a failed live listing.
 *
 * A failed authoritative live listing is terminal in both modes: the
 * failure classes map straight onto the exit-code contract and no
 * diagnostic retry may mask them. */
static void pipeline_run_mode(struct shoji_context *ctx, const struct shoji_options *opts,
                              int require_instance, struct shoji_pipeline *pl,
                              int diagnostic)
{
        enum shoji_discover_err derr = SHOJI_DISCOVER_OK;

        memset(pl, 0, sizeof(*pl));

        if (!ctx->have_store)
                shoji_context_resolve_store(ctx, opts);

        if (!ctx->have_store) {
                if (opts->instance_id) {
                        shj_msg("warning: could not resolve the expected Shoji store path; "
                                "dispatching to explicit instance '%s' only", opts->instance_id);
                } else if (require_instance) {
                        shj_msg("could not resolve the expected Shoji store path");
                        store_unresolved_hints();
                        pl->exit_code = SHOJI_EXIT_NOSTORE;
                        return;
                }
        }

        pl->have_store = ctx->have_store;
        pl->list = diagnostic
                       ? shoji_discover_instances(ctx->spawn, ctx->spawn_user, ctx->qs_bin, &derr)
                       : shoji_discover_instances_fast(ctx->spawn, ctx->spawn_user, ctx->qs_bin, &derr);
        if (!pl->list) {
                /* Explicit discovery failure classes -> the documented
                 * exit-code contract: timeout is a plain failure (1), a
                 * missing quickshell executable is 69, an internal
                 * subprocess failure is 70, and quickshell's own listing
                 * failures keep the documented generic behavior (1). */
                switch (derr) {
                case SHOJI_DISCOVER_NOEXEC:
                        pl->exit_code = SHOJI_EXIT_NOQS;
                        break;
                case SHOJI_DISCOVER_TIMEOUT:
                case SHOJI_DISCOVER_FAILED:
                case SHOJI_DISCOVER_BADJSON:
                        pl->exit_code = SHOJI_EXIT_FAILED;
                        break;
                case SHOJI_DISCOVER_INTERNAL:
                default:
                        pl->exit_code = SHOJI_EXIT_INTERNAL;
                        break;
                }
                return;
        }

        shoji_select_instance(pl->list,
                              ctx->have_store ? ctx->store.shell_qml : NULL,
                              opts->instance_id, &pl->sel);

        /* Fast-path fallback: selection could not establish a dispatchable
         * target on the authoritative live snapshot. Enrich that snapshot
         * with the dead-instance diagnostics (and, when the dead listing
         * parses, the fresh live recheck the full path would run) and
         * re-select. This costs extra subprocesses only on the failure
         * path, keeps the final listing identical to the full procedure's,
         * and never re-runs the already-successful live listing. */
        if (!diagnostic && require_instance && !selection_is_dispatchable(pl)) {
                shoji_selection_clear(&pl->sel);
                shoji_discover_instances_enrich(pl->list, ctx->spawn, ctx->spawn_user,
                                                ctx->qs_bin);
                shoji_select_instance(pl->list,
                                      ctx->have_store ? ctx->store.shell_qml : NULL,
                                      opts->instance_id, &pl->sel);
        }

        if (pl->sel.status == SHOJI_SELECT_OK) {
                /* Explicit override pointing at a foreign shell: not an error,
                 * but it must never look like a match. */
                if (ctx->have_store) {
                        int m = shoji_instance_matches_config(pl->sel.selected,
                                                              ctx->store.shell_qml);

                        if (m == 0) {
                                shj_msg("warning: instance '%s' runs %s, which is not the "
                                        "expected configuration %s",
                                        pl->sel.selected->id,
                                        pl->sel.selected->config_path ? pl->sel.selected->config_path : "?",
                                        ctx->store.shell_qml);
                                shj_hint("use 'shoji instance list' to compare generations; "
                                         "refuse to continue if this is unexpected");
                        } else if (m < 0) {
                                /* The path currently resolves to the expected config,
                                 * but the original launch-time target is unknowable. */
                                shj_msg("warning: instance '%s' has a recorded configuration path "
                                        "whose launch-time target cannot be established; "
                                        "its loaded generation is uncertain", pl->sel.selected->id);
                        }
                }
                if (pl->sel.selected->dead) {
                        shj_msg("instance '%s' is not running (dead instance lock)",
                                pl->sel.selected->id);
                        pl->exit_code = SHOJI_EXIT_NOINSTANCE;
                }
                return;
        }

        if (pl->sel.status == SHOJI_SELECT_NONE) {
                if (require_instance) {
                        shj_msg("no running quickshell instance matches the expected configuration");
                        if (ctx->have_store)
                                shj_msg("expected configuration: %s", ctx->store.shell_qml);
                        if (pl->sel.dead_match_count > 0)
                                shj_msg("%d dead instance%s of this configuration exist (the shell "
                                        "may have crashed or been replaced)",
                                        pl->sel.dead_match_count,
                                        pl->sel.dead_match_count == 1 ? "" : "s");
                        if (pl->sel.uncertain_matches > 0)
                                shj_msg("%d running instance%s of this configuration %s a "
                                        "recorded path whose launch-time target cannot be "
                                        "established; the loaded generation is uncertain",
                                        pl->sel.uncertain_matches,
                                        pl->sel.uncertain_matches == 1 ? "" : "s",
                                        pl->sel.uncertain_matches == 1 ? "has" : "have");
                        if (pl->sel.invalid_id_matches > 0)
                                shj_msg("%d running instance%s of this configuration ha%s no valid "
                                        "instance id and cannot be selected",
                                        pl->sel.invalid_id_matches,
                                        pl->sel.invalid_id_matches == 1 ? "" : "s",
                                        pl->sel.invalid_id_matches == 1 ? "s" : "ve");
                        if (shoji_live_count(pl->list) > 0) {
                                shj_msg("other running quickshell instances:");
                                for (int i = 0; i < pl->list->count; i++) {
                                        struct shoji_instance *inst = &pl->list->items[i];

                                        if (!inst->dead)
                                                shoji_print_instance_line(inst, NULL);
                                }
                                shj_hint("dispatch to one explicitly with --instance-id <id prefix>");
                        } else {
                                shj_hint("start Shoji, e.g. `qs -p <shoji store path>`");
                        }
                        pl->exit_code = SHOJI_EXIT_NOINSTANCE;
                } else {
                        pl->exit_code = SHOJI_EXIT_OK;
                }
                return;
        }

        if (pl->sel.status == SHOJI_SELECT_AMBIGUOUS) {
                if (require_instance) {
                        shj_msg("multiple running instances match the expected configuration "
                                "or the given instance id prefix");
                        for (int i = 0; i < pl->sel.match_count; i++)
                                shoji_print_instance_line(pl->sel.matches[i], "*");
                        shj_hint("pick one explicitly with --instance-id <id prefix>");
                        pl->exit_code = SHOJI_EXIT_AMBIGUOUS;
                } else {
                        pl->exit_code = SHOJI_EXIT_OK;
                }
                return;
        }

        pl->exit_code = SHOJI_EXIT_FAILED;
}

void shoji_pipeline_run(struct shoji_context *ctx, const struct shoji_options *opts,
                        int require_instance, struct shoji_pipeline *pl)
{
        pipeline_run_mode(ctx, opts, require_instance, pl, 1);
}

/* Pipeline for ordinary IPC dispatch (facade commands, `ipc call`,
 * `ipc show`): one authoritative live listing before a successful dispatch;
 * the dead-instance diagnostics run only when the fast snapshot cannot
 * establish a target. */
void shoji_pipeline_run_fast(struct shoji_context *ctx, const struct shoji_options *opts,
                             int require_instance, struct shoji_pipeline *pl)
{
        pipeline_run_mode(ctx, opts, require_instance, pl, 0);
}

void shoji_pipeline_release(struct shoji_pipeline *pl)
{
        if (!pl)
                return;
        shoji_selection_clear(&pl->sel);
        shoji_instance_list_free(pl->list);
        pl->list = NULL;
}

static int child_stderr_classifies(const char *err, int *code)
{
        const char *patterns_badipc[] = {
                "Target not found.", "Function not found.",
                "Unable to parse argument", "arguments provided",
                NULL,
        };

        for (int i = 0; patterns_badipc[i]; i++) {
                if (strstr(err, patterns_badipc[i])) {
                        *code = SHOJI_EXIT_BADIPC;
                        return 1;
                }
        }
        return 0;
}

int shoji_dispatch_call(struct shoji_context *ctx, const struct shoji_pipeline *pl,
                        const char *target, const char *function,
                        char *const args[], int argc)
{
        const struct shoji_instance *inst = pl->sel.selected;
        const char **argv;
        struct shj_proc_result *r;
        char pidbuf[32];
        int code;

        if (!inst || inst->dead)
                return SHOJI_EXIT_NOINSTANCE;
        /* Defense in depth: selection refuses rows without a usable id, but
         * dispatch itself must guarantee that no IPC ever runs with an
         * empty instance id -- quickshell would skip the selector and fall
         * back to config-based selection. */
        if (!inst->id_valid) {
                shj_msg("internal error: refusing to dispatch: instance has no valid id");
                return SHOJI_EXIT_INTERNAL;
        }
        if (inst->pid <= 0) {
                shj_msg("internal error: refusing to dispatch: instance has no usable pid");
                return SHOJI_EXIT_INTERNAL;
        }

        /* qs ipc --pid <pid> call <target> <function> [args...] */
        argv = shj_alloc(sizeof(char *) * (size_t)(argc + 9));
        {
                int i = 0;

                argv[i++] = ctx->qs_bin;
                argv[i++] = "ipc";
                argv[i++] = "--pid";
                argv[i++] = pid_selector(pidbuf, sizeof(pidbuf), inst);
                argv[i++] = "call";
                argv[i++] = target;
                argv[i++] = function;
                for (int a = 0; a < argc; a++)
                        argv[i++] = args[a];
                argv[i] = NULL;
        }

        r = ctx->spawn(argv, ctx->spawn_user);
        free(argv);

        if (!r)
                return SHOJI_EXIT_INTERNAL;
        if (r->exit == -1) {
                shj_msg("cannot execute quickshell (%s): %s", ctx->qs_bin,
                        strerror(r->spawn_errno));
                shj_hint("install quickshell or point --qs / SHOJI_QS_BIN at it");
                shj_proc_result_free(r);
                return SHOJI_EXIT_NOQS;
        }
        if (r->exit == -2) {
                shj_msg("quickshell did not answer the IPC call in time");
                warn_timeout();
                shj_proc_result_free(r);
                return SHOJI_EXIT_FAILED;
        }
        if (r->exit == -3) {
                shj_msg("internal error reading quickshell output: %s",
                        strerror(r->spawn_errno));
                shj_proc_result_free(r);
                return SHOJI_EXIT_INTERNAL;
        }
        if (r->truncated)
                shj_msg("quickshell output hit the 4 MiB per-stream capture cap and was truncated");

        if (r->out && *r->out)
                fputs(r->out, stdout);
        code = r->exit;
        if (r->err && *r->err)
                fputs(r->err, stderr);
        if (code != 0) {
                {
                        int classified = 0;

                        if (child_stderr_classifies(r->err ? r->err : "", &classified)) {
                                code = classified;
                                shj_hint("run 'shoji ipc show' to list valid targets and functions");
                        } else {
                                code = SHOJI_EXIT_FAILED;
                                shj_msg("quickshell exited with status %d", r->exit);
                        }
                }
        }
        shj_proc_result_free(r);
        return code;
}

int shoji_dispatch_show(struct shoji_context *ctx, const struct shoji_pipeline *pl)
{
        const struct shoji_instance *inst = pl->sel.selected;
        const char *argv[] = { ctx->qs_bin, "ipc", "--pid", NULL, "show", NULL };
        struct shj_proc_result *r;
        char pidbuf[32];
        int code;

        if (!inst || inst->dead)
                return SHOJI_EXIT_NOINSTANCE;
        if (!inst->id_valid) {
                shj_msg("internal error: refusing to dispatch: instance has no valid id");
                return SHOJI_EXIT_INTERNAL;
        }
        if (inst->pid <= 0) {
                shj_msg("internal error: refusing to dispatch: instance has no usable pid");
                return SHOJI_EXIT_INTERNAL;
        }

        argv[3] = pid_selector(pidbuf, sizeof(pidbuf), inst);
        r = ctx->spawn(argv, ctx->spawn_user);
        if (!r)
                return SHOJI_EXIT_INTERNAL;
        if (r->exit == -1) {
                shj_msg("cannot execute quickshell (%s): %s", ctx->qs_bin,
                        strerror(r->spawn_errno));
                shj_proc_result_free(r);
                return SHOJI_EXIT_NOQS;
        }
        if (r->exit == -2) {
                shj_msg("quickshell did not answer `ipc show` in time");
                warn_timeout();
                shj_proc_result_free(r);
                return SHOJI_EXIT_FAILED;
        }
        if (r->exit == -3) {
                shj_msg("internal error reading quickshell output: %s",
                        strerror(r->spawn_errno));
                shj_proc_result_free(r);
                return SHOJI_EXIT_INTERNAL;
        }
        if (r->truncated)
                shj_msg("quickshell output hit the 4 MiB per-stream capture cap and was truncated");

        if (r->out && *r->out)
                fputs(r->out, stdout);
        code = r->exit;
        if (r->err && *r->err)
                fputs(r->err, stderr);
        if (code != 0)
                code = SHOJI_EXIT_FAILED;
        shj_proc_result_free(r);
        return code;
}

int shoji_dispatch_kill_instance(struct shoji_context *ctx,
                                 const struct shoji_instance *inst)
{
        const char *argv[] = { ctx->qs_bin, "kill", "--pid", NULL, NULL };
        struct shj_proc_result *r;
        char pidbuf[32];
        int code;

        if (!inst || inst->dead)
                return SHOJI_EXIT_NOINSTANCE;
        if (!inst->id_valid) {
                shj_msg("internal error: refusing to dispatch: instance has no valid id");
                return SHOJI_EXIT_INTERNAL;
        }
        if (inst->pid <= 0) {
                shj_msg("internal error: refusing to dispatch: instance has no usable pid");
                return SHOJI_EXIT_INTERNAL;
        }

        argv[3] = pid_selector(pidbuf, sizeof(pidbuf), inst);
        r = ctx->spawn(argv, ctx->spawn_user);
        if (!r)
                return SHOJI_EXIT_INTERNAL;
        if (r->exit == -1) {
                shj_msg("cannot execute quickshell (%s): %s", ctx->qs_bin,
                        strerror(r->spawn_errno));
                shj_hint("install quickshell or point --qs / SHOJI_QS_BIN at it");
                shj_proc_result_free(r);
                return SHOJI_EXIT_NOQS;
        }
        if (r->exit == -2) {
                shj_msg("quickshell did not answer the kill request in time");
                warn_timeout();
                shj_proc_result_free(r);
                return SHOJI_EXIT_FAILED;
        }
        if (r->exit == -3) {
                shj_msg("internal error reading quickshell output: %s",
                        strerror(r->spawn_errno));
                shj_proc_result_free(r);
                return SHOJI_EXIT_INTERNAL;
        }
        if (r->truncated)
                shj_msg("quickshell output hit the 4 MiB per-stream capture cap and was truncated");

        if (r->out && *r->out)
                fputs(r->out, stdout);
        code = r->exit;
        if (r->err && *r->err)
                fputs(r->err, stderr);
        if (code != 0) {
                code = SHOJI_EXIT_FAILED;
                shj_msg("quickshell exited with status %d", r->exit);
        }
        shj_proc_result_free(r);
        return code;
}

int shoji_dispatch_kill(struct shoji_context *ctx, const struct shoji_pipeline *pl)
{
        const struct shoji_instance *inst = pl->sel.selected;

        if (!inst || inst->dead)
                return SHOJI_EXIT_NOINSTANCE;
        if (!inst->id_valid) {
                shj_msg("internal error: refusing to dispatch: instance has no valid id");
                return SHOJI_EXIT_INTERNAL;
        }
        return shoji_dispatch_kill_instance(ctx, inst);
}

int shoji_ipc_probe(struct shoji_context *ctx, const struct shoji_instance *inst)
{
        const char *argv[] = { ctx->qs_bin, "ipc", "--pid", NULL, "show", NULL };
        struct shj_proc_result *r;
        char pidbuf[32];
        int ok;

        if (!inst || inst->dead || !inst->id_valid || inst->pid <= 0)
                return -1;

        argv[3] = pid_selector(pidbuf, sizeof(pidbuf), inst);
        r = ctx->spawn(argv, ctx->spawn_user);
        if (!r)
                return -1;
        ok = (r->exit == 0) ? 0 : -1;
        shj_proc_result_free(r);
        return ok;
}

char *shoji_qs_version(struct shoji_context *ctx)
{
        const char *argv[] = { ctx->qs_bin, "--version", NULL };
        struct shj_proc_result *r;
        char *version = NULL;
        char *nl;

        r = ctx->spawn(argv, ctx->spawn_user);
        if (!r)
                return NULL;
        if (r->exit == 0 && r->out && *r->out) {
                version = shj_strdup(r->out);
                nl = strchr(version, '\n');
                if (nl)
                        *nl = '\0';
        }
        shj_proc_result_free(r);
        return version;
}
