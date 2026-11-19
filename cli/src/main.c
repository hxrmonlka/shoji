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
#include "report.h"
#include "util.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>

static int run_facade(struct shoji_context *ctx, const struct shoji_options *opts,
                      const struct shoji_cmd *cmd)
{
        struct shoji_pipeline pl;
        char *args[2];
        int code;

        shoji_pipeline_run(ctx, opts, 1, &pl);
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

int main(int argc, char **argv)
{
        struct shoji_options opts;
        struct shoji_context ctx;
        const char *timeout_env;
        int code;

        code = shoji_parse(argc, argv, &opts);
        if (code != SHOJI_EXIT_OK) {
                shoji_options_free(&opts);
                return code;
        }
        timeout_env = getenv("SHOJI_QS_TIMEOUT_MS");
        if (timeout_env && *timeout_env) {
                char *end = NULL;
                long timeout_ms;

                errno = 0;
                timeout_ms = strtol(timeout_env, &end, 10);
                if (errno == ERANGE || end == timeout_env || !end || *end || timeout_ms < 0) {
                        shj_msg("SHOJI_QS_TIMEOUT_MS must be a non-negative integer");
                        shoji_options_free(&opts);
                        return SHOJI_EXIT_USAGE;
                }
                shj_proc_set_timeout_ms(timeout_ms);
        }

        shoji_context_init(&ctx, &opts);

        switch (opts.kind) {
        case SHOJI_CMD_HELP:
                shoji_print_help();
                code = SHOJI_EXIT_OK;
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

                shoji_pipeline_run(&ctx, &opts, 1, &pl);
                code = pl.exit_code != SHOJI_EXIT_OK
                           ? pl.exit_code
                           : shoji_dispatch_show(&ctx, &pl);
                shoji_pipeline_release(&pl);
                break;
        }

        case SHOJI_CMD_IPC_CALL: {
                struct shoji_pipeline pl;

                shoji_pipeline_run(&ctx, &opts, 1, &pl);
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
