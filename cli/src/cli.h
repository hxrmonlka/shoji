/* shoji-cli -- command line parsing. */
#ifndef SHOJI_CLI_H
#define SHOJI_CLI_H

#include "ipctable.h"

enum shoji_cmd_kind {
        SHOJI_CMD_NONE,
        SHOJI_CMD_HELP,
        SHOJI_CMD_VERSION,
        SHOJI_CMD_RUN,
        SHOJI_CMD_STATUS,
        SHOJI_CMD_DOCTOR,
        SHOJI_CMD_KILL,
        SHOJI_CMD_INSTANCE_LIST,
        SHOJI_CMD_INSTANCE_CURRENT,
        SHOJI_CMD_INSTANCE_INSPECT,
        SHOJI_CMD_IPC_SHOW,
        SHOJI_CMD_IPC_CALL,
        SHOJI_CMD_FACADE,
        SHOJI_CMD_DEBUG_MAP,
        SHOJI_CMD_SETTINGS_LIST,
        SHOJI_CMD_SETTINGS_DUMP,
        SHOJI_CMD_SETTINGS_EXPORT,
        SHOJI_CMD_SETTINGS_GET,
        SHOJI_CMD_SETTINGS_SET,
};

struct shoji_options {
        enum shoji_cmd_kind kind;
        const struct shoji_cmd *facade;   /* resolved table entry (FACADE) */

        char *store_override;             /* --store */
        char *qs_bin;                     /* --qs (or env/default) */
        char *instance_id;                /* --instance-id */
        int json;                         /* --json */
        int kill_all;                     /* kill --all */

        int run_argc;
        char **run_args;

        char *ipc_target;                 /* ipc call */
        char *ipc_function;
        int ipc_argc;
        char **ipc_args;                  /* malloc'd strings */

        char *facade_args[2];             /* normalized facade or settings arguments */
};

/* Parse argv (argv[0] excluded); returns 0 and fills *opts on success, or a
 * shoji exit code (SHOJI_EXIT_USAGE) after printing a diagnostic. Safe to
 * call from tests: it never exits the process. */
int shoji_parse(int argc, char **argv, struct shoji_options *opts);

void shoji_options_free(struct shoji_options *opts);

/* Help and version text (stdout). */
void shoji_print_help(void);
void shoji_print_version(void);

#endif /* SHOJI_CLI_H */
