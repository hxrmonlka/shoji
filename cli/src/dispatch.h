/*
 * shoji-cli -- dispatch pipeline: resolve store, discover instances,
 * select safely, then hand the call to quickshell's native CLI.
 */
#ifndef SHOJI_DISPATCH_H
#define SHOJI_DISPATCH_H

#include "cli.h"
#include "instances.h"
#include "proc.h"
#include "resolver.h"

struct shoji_context {
        const char *qs_bin;
        shj_spawn_fn spawn;
        void *spawn_user;
        struct shoji_store store;
        int have_store;
};

/* Shared result of resolve + discover + select. */
struct shoji_pipeline {
        struct shoji_instance_list *list;
        struct shoji_selection sel;
        int have_store;
        /* 0 when a live instance was selected and dispatch may proceed;
         * otherwise a shoji exit code. */
        int exit_code;
};

/* Resolve the qs binary name and prepare the spawn function. */
void shoji_context_init(struct shoji_context *ctx, const struct shoji_options *opts);

/* Resolve the store path only (used by status/doctor; never fatal). */
void shoji_context_resolve_store(struct shoji_context *ctx,
                                 const struct shoji_options *opts);

/* Full pipeline for dispatching commands. When `require_instance` is set the
 * function refuses (exit 67/68) unless exactly one instance is selected.
 * Diagnostics are printed to stderr. */
void shoji_pipeline_run(struct shoji_context *ctx, const struct shoji_options *opts,
                        int require_instance, struct shoji_pipeline *pl);

/* Fast pipeline for ordinary IPC dispatch: exactly one authoritative live
 * listing before a successful dispatch (no --show-dead probe, no refresh).
 * When `require_instance` is set and selection cannot establish a target on
 * that snapshot, the same snapshot is completed in place with the
 * dead-instance diagnostics and selection re-runs -- the failure reporting
 * is identical to the full pipeline's, and a failed live listing is never
 * retried. */
void shoji_pipeline_run_fast(struct shoji_context *ctx, const struct shoji_options *opts,
                             int require_instance, struct shoji_pipeline *pl);

/* Select only (no dispatch); useful for instance/status commands. */
void shoji_pipeline_release(struct shoji_pipeline *pl);

/* Dispatch one IPC call to the selected instance; returns a shoji exit
 * code. Child stdout/stderr are relayed to the corresponding streams. */
int shoji_dispatch_call(struct shoji_context *ctx, const struct shoji_pipeline *pl,
                        const char *target, const char *function,
                        char *const args[], int argc);

/* Same dispatch, but *out captures quickshell's stdout (malloc'd, one
 * trailing newline stripped) instead of relaying it. */
int shoji_dispatch_call_capture(struct shoji_context *ctx, const struct shoji_pipeline *pl,
                                const char *target, const char *function,
                                char *const args[], int argc, char **out);

/* Dispatch `qs ipc show` for the selected instance; returns exit code. */
int shoji_dispatch_show(struct shoji_context *ctx, const struct shoji_pipeline *pl);

/* Kill the pipeline's selected instance via `qs kill -i <full-id>`. */
int shoji_dispatch_kill(struct shoji_context *ctx, const struct shoji_pipeline *pl);

/* Kill one explicit instance via `qs kill -i <full-id>`. */
int shoji_dispatch_kill_instance(struct shoji_context *ctx,
                                 const struct shoji_instance *inst);

/* One diagnostic line describing an instance (stderr). */
void shoji_print_instance_line(const struct shoji_instance *inst, const char *mark);

/* Probe IPC accessibility without side effects; 0 = reachable. */
int shoji_ipc_probe(struct shoji_context *ctx, const struct shoji_instance *inst);

/* Quickshell version string ("Quickshell x.y.z") or NULL; malloc'd. */
char *shoji_qs_version(struct shoji_context *ctx);

#endif /* SHOJI_DISPATCH_H */
