/*
 * shoji-cli -- entry point.
 *
 * Thin command line interface over Quickshell for the Shoji shell.
 * This file wires parsing, the dispatch pipeline and the reporting commands
 * together; all real behavior lives in the other modules.
 */
#define _POSIX_C_SOURCE 200809L

#include "cli.h"
#include "dispatch.h"
#include "exitcodes.h"
#include "ipctable.h"
#include "proc.h"
#include "report.h"
#include "util.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Ordinary IPC dispatch commands run the fast pipeline: one authoritative
 * live listing before a successful dispatch; diagnostics only on the
 * failure path. run_facade covers every friendly facade command
 * (island/wallpaper/media/...). */
static int run_facade(struct shoji_context *ctx, const struct shoji_options *opts,
                      const struct shoji_cmd *cmd)
{
        struct shoji_pipeline pl;
        char *args[2];
        int code;

        shoji_pipeline_run_fast(ctx, opts, 1, &pl);
        if (pl.exit_code != SHOJI_EXIT_OK) {
                code = pl.exit_code;
                shoji_pipeline_release(&pl);
                return code;
        }

        args[0] = opts->facade_args[0];
        args[1] = opts->facade_args[1];
        code = shoji_dispatch_call(ctx, &pl, cmd->target, cmd->function, args, cmd->arg_count);
        shoji_pipeline_release(&pl);
        return code;
}

static int run_shoji(struct shoji_context *ctx, const struct shoji_options *opts)
{
        char **qs_argv;
        char *qs_exe;
        int argc = opts->run_argc + 3;

        shoji_context_resolve_store(ctx, opts);
        if (!ctx->have_store) {
                shj_msg("could not resolve the Shoji configuration to launch");
                shj_hint("use --store /path/to/shoji, set SHOJI_STORE_PATH, or install "
                         "shoji-cli with its default store path configured");
                return SHOJI_EXIT_NOSTORE;
        }

        qs_exe = shj_find_in_path(ctx->qs_bin, NULL);
        if (!qs_exe) {
                shj_msg("cannot find quickshell executable (%s) on PATH", ctx->qs_bin);
                return SHOJI_EXIT_NOQS;
        }

        qs_argv = shj_alloc(sizeof(char *) * (size_t)(argc + 1));
        qs_argv[0] = qs_exe;
        qs_argv[1] = "--path";
        qs_argv[2] = ctx->store.shell_qml;
        for (int i = 0; i < opts->run_argc; i++)
                qs_argv[i + 3] = opts->run_args[i];
        qs_argv[argc] = NULL;

        if (unsetenv("QS_CONFIG_PATH") != 0 ||
            unsetenv("QS_CONFIG_NAME") != 0 ||
            unsetenv("QS_MANIFEST") != 0) {
                shj_msg("could not clear inherited Quickshell configuration selectors: %s",
                        strerror(errno));
                free(qs_argv);
                free(qs_exe);
                return SHOJI_EXIT_INTERNAL;
        }

        execv(qs_exe, qs_argv);
        {
                int saved_errno = errno;
                shj_msg("cannot execute quickshell (%s): %s", qs_exe,
                        strerror(saved_errno));
                free(qs_argv);
                free(qs_exe);
                return saved_errno == ENOENT || saved_errno == ENOTDIR
                           ? SHOJI_EXIT_NOQS
                           : SHOJI_EXIT_FAILED;
        }
}

/* Validate SHOJI_QS_TIMEOUT_MS before any command that can spawn
 * quickshell. Purely local commands (--help, --version, debug map) never
 * consult the timeout and must work with an invalid value. */
static int apply_timeout_env(void)
{
        const char *timeout_env = getenv("SHOJI_QS_TIMEOUT_MS");
        char *end = NULL;
        long timeout_ms;

        if (!timeout_env || !*timeout_env)
                return SHOJI_EXIT_OK;
        errno = 0;
        timeout_ms = strtol(timeout_env, &end, 10);
        if (errno == ERANGE || end == timeout_env || !end || *end || timeout_ms < 0) {
                shj_msg("SHOJI_QS_TIMEOUT_MS must be a non-negative integer");
                return SHOJI_EXIT_USAGE;
        }
        shj_proc_set_timeout_ms(timeout_ms);
        return SHOJI_EXIT_OK;
}

int main(int argc, char **argv)
{
        struct shoji_options opts;
        struct shoji_context ctx;
        int code;

        code = shoji_parse(argc, argv, &opts);
        if (code != SHOJI_EXIT_OK) {
                shoji_options_free(&opts);
                return code;
        }

        shj_proc_init();

        if (opts.kind != SHOJI_CMD_HELP && opts.kind != SHOJI_CMD_VERSION &&
            opts.kind != SHOJI_CMD_DEBUG_MAP) {
                code = apply_timeout_env();
                if (code != SHOJI_EXIT_OK) {
                        shoji_options_free(&opts);
                        return code;
                }
        }

        shoji_context_init(&ctx, &opts);

        switch (opts.kind) {
        case SHOJI_CMD_HELP:
                shoji_print_help();
                code = SHOJI_EXIT_OK;
                break;

        case SHOJI_CMD_RUN:
                code = run_shoji(&ctx, &opts);
                break;

        case SHOJI_CMD_VERSION:
                shoji_print_version();
                code = SHOJI_EXIT_OK;
                break;

        case SHOJI_CMD_DEBUG_MAP:
                shoji_ipc_table_dump_tsv();
                code = SHOJI_EXIT_OK;
                break;

        case SHOJI_CMD_STATUS:
                code = shoji_cmd_status(&ctx, &opts);
                break;

        case SHOJI_CMD_DOCTOR:
                code = shoji_cmd_doctor(&ctx, &opts);
                break;

        case SHOJI_CMD_KILL:
                code = shoji_cmd_kill(&ctx, &opts);
                break;

        case SHOJI_CMD_INSTANCE_LIST:
                code = shoji_cmd_instance_list(&ctx, &opts);
                break;

        case SHOJI_CMD_INSTANCE_CURRENT:
                code = shoji_cmd_instance_current(&ctx, &opts);
                break;

        case SHOJI_CMD_INSTANCE_INSPECT:
                code = shoji_cmd_instance_inspect(&ctx, &opts);
                break;

        case SHOJI_CMD_IPC_SHOW: {
                struct shoji_pipeline pl;

                shoji_pipeline_run_fast(&ctx, &opts, 1, &pl);
                code = pl.exit_code != SHOJI_EXIT_OK
                           ? pl.exit_code
                           : shoji_dispatch_show(&ctx, &pl);
                shoji_pipeline_release(&pl);
                break;
        }

        case SHOJI_CMD_IPC_CALL: {
                struct shoji_pipeline pl;

                shoji_pipeline_run_fast(&ctx, &opts, 1, &pl);
                code = pl.exit_code != SHOJI_EXIT_OK
                           ? pl.exit_code
                           : shoji_dispatch_call(&ctx, &pl, opts.ipc_target,
                                                 opts.ipc_function, opts.ipc_args,
                                                 opts.ipc_argc);
                shoji_pipeline_release(&pl);
                break;
        }

        case SHOJI_CMD_FACADE:
                code = run_facade(&ctx, &opts, opts.facade);
                break;

        default:
                shoji_print_help();
                code = SHOJI_EXIT_OK;
                break;
        }

        shoji_options_free(&opts);
        shoji_store_free(&ctx.store);
        return code;
}
