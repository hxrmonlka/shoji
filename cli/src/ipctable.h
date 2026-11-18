/*
 * shoji-cli -- friendly command facade over Shoji's existing IPC handlers.
 *
 * Every entry below maps a user-facing command to an IpcHandler target and
 * function that already exists in shell.qml (branch eup). The table is the
 * single authority for argument validation; nothing here implements shell
 * behavior. `tests/qml_ipc.awk` re-extracts the handlers from shell.qml and
 * `make test` fails if this table and the QML drift apart.
 *
 * Function names are quickshell camelCase; command names use dashes and are
 * declared explicitly (e.g. `shoji media play-pause` -> media.playPause).
 */
#ifndef SHOJI_IPCTABLE_H
#define SHOJI_IPCTABLE_H

enum shoji_arg_type {
        SHOJI_ARG_NONE = 0,
        SHOJI_ARG_STRING,
        SHOJI_ARG_INT,
        SHOJI_ARG_BOOL,
};

struct shoji_arg_spec {
        enum shoji_arg_type type;
        const char *name;
};

struct shoji_cmd {
        const char *group;      /* user-facing command group */
        const char *name;       /* user-facing subcommand (dash case) */
        const char *target;     /* IpcHandler target (shell.qml) */
        const char *function;   /* IpcHandler function name (camelCase) */
        struct shoji_arg_spec args[2];
        int arg_count;
};

/* Full static table (sorted by group for the help output). */
extern const struct shoji_cmd shoji_ipc_table[];
extern const int shoji_ipc_table_len;

/* Look up a facade command; NULL when unknown. */
const struct shoji_cmd *shoji_ipc_table_find(const char *group, const char *name);

/* True when `group` is a known facade group. */
int shoji_ipc_table_group_exists(const char *group);

/* Validate and normalize one argument string against its spec. Returns a
 * malloc'd string ready to hand to `qs ipc call`, or NULL after printing a
 * diagnostic. */
char *shoji_arg_normalize(const struct shoji_arg_spec *spec, const char *value);

/* Print the table as TSV: group <TAB> name <TAB> target <TAB> function
 * <TAB> argtype:argname[,argtype:argname]. Used by `shoji debug map`. */
void shoji_ipc_table_dump_tsv(void);

#endif /* SHOJI_IPCTABLE_H */
