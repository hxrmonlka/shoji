/*
 * shoji-cli -- quickshell instance discovery and selection.
 *
 * Discovery always goes through quickshell's own CLI. `qs list -a -j` is
 * the authoritative live listing: upstream outputs only instances that
 * currently hold their fcntl instance lock unless --show-dead is given.
 * `qs list -a -j --show-dead` is a strictly additive compatibility probe
 * used for dead-instance diagnostics only. The CLI never dispatches based
 * on a bare `qs -p PATH` invocation, because quickshell silently picks the
 * oldest instance of a config when several match -- shoji instead selects
 * an instance itself and dispatches with the full, unique instance id.
 *
 * Selection policy (shoji_select_instance):
 *   - candidates are live instances whose configuration identity is
 *     established as the expected store path (see
 *     shoji_instance_matches_config; expected_qml may be NULL, in which
 *     case only --instance-id resolution applies) AND whose instance id is
 *     valid (rows without a usable id are never dispatched);
 *   - exactly one candidate  -> selected;
 *   - none                   -> SHOJI_SELECT_NONE (dead instances, and
 *                               live-but-unestablishable rows, reported
 *                               separately for diagnostics);
 *   - more than one          -> SHOJI_SELECT_AMBIGUOUS unless --instance-id
 *                               resolves one candidate (prefix match on the
 *                               instance id, same rule quickshell uses);
 *   - --instance-id that matches no known instance -> SHOJI_SELECT_NONE.
 */
#ifndef SHOJI_INSTANCES_H
#define SHOJI_INSTANCES_H

#include "proc.h"

/* Failure classes of shoji_discover_instances (*err). They map onto the
 * CLI exit-code contract in dispatch.c; the classes are explicit instead
 * of overloading arbitrary negative integers. */
enum shoji_discover_err {
        SHOJI_DISCOVER_OK = 0,
        SHOJI_DISCOVER_INTERNAL, /* spawn interface or stream/wait failure  */
        SHOJI_DISCOVER_NOEXEC,   /* the quickshell executable could not run */
        SHOJI_DISCOVER_TIMEOUT,  /* a discovery subprocess hit the timeout  */
        SHOJI_DISCOVER_FAILED,   /* quickshell exited nonzero on a listing  */
        SHOJI_DISCOVER_BADJSON,  /* the live listing was not parseable JSON */
};

struct shoji_instance {
        char *id;           /* quickshell instance id (unique) */
        int id_valid;       /* 0 for absent/empty/invalid ids; such rows are
                             * never IPC candidates (qs skips an empty -i
                             * selector and would delegate to config-based
                             * selection) */
        long pid;           /* launch-time pid from the listing; -1 for
                             * dead rows discovered without a lock holder */
        char *shell_id;
        char *config_path;  /* recorded at launch; may be gone (GC) */
        char *launch_time;  /* Qt ISO date string */
        int dead;           /* 1 when the instance holds no instance lock */
};

struct shoji_instance_list {
        struct shoji_instance *items;
        int count;
};

enum shoji_select_status {
        SHOJI_SELECT_OK,
        SHOJI_SELECT_NONE,
        SHOJI_SELECT_AMBIGUOUS,
        SHOJI_SELECT_ERROR, /* discovery failed */
};

struct shoji_selection {
        enum shoji_select_status status;
        struct shoji_instance *selected;  /* borrowed from the list */
        /* live instances matching the expected config (borrowed pointers) */
        struct shoji_instance **matches;
        int match_count;
        /* dead instances matching the expected config (borrowed pointers) */
        struct shoji_instance **dead_matches;
        int dead_match_count;
        /* live rows whose recorded path resolves to the expected config,
         * but whose launch-time configuration target cannot be established */
        int uncertain_matches;
        /* live rows of the expected config without a valid instance id */
        int invalid_id_matches;
};

/* Run `qs list -a -j` (the authoritative live listing) plus the additive
 * `qs list -a -j --show-dead` diagnostics probe via the injected spawn
 * function. On failure returns NULL with *err set. */
struct shoji_instance_list *shoji_discover_instances(shj_spawn_fn spawn, void *user,
                                                     const char *qs_bin,
                                                     enum shoji_discover_err *err);

void shoji_instance_list_free(struct shoji_instance_list *list);

/* Count of live instances in the list. */
int shoji_live_count(const struct shoji_instance_list *list);

/* Configuration-identity match against the expected store path.
 *   1  the instance provably loaded expected_qml's configuration;
 *   0  it did not (or identity cannot apply);
 *  -1  uncertain: the recorded launch-time path currently resolves to
 *      expected_qml, but the configuration target at launch cannot be
 *      established. This does not prove that the alias was retargeted.
 *      Uncertain rows are never auto-selected; they require an explicit
 *      --instance-id.
 *
 * The recorded config_path is quickshell's launch-time record (absolute,
 * NOT symlink-resolved: src/launch/command.cpp locateConfigFile ends in
 * QFileInfo(path).absoluteFilePath(); the lock file stores that string,
 * and `qs list -j` prints it). Re-resolving it here would read a mutable
 * alias's CURRENT target, not the configuration loaded at launch.
 * See instances.c for the full policy and the upstream evidence. */
int shoji_instance_matches_config(const struct shoji_instance *inst,
                                  const char *expected_qml);

/* Selection policy; see header comment. expected_qml may be NULL.
 * `out` borrows pointers into `list`; both must outlive it. */
enum shoji_select_status shoji_select_instance(const struct shoji_instance_list *list,
                                               const char *expected_qml,
                                               const char *instance_id_override,
                                               struct shoji_selection *out);

void shoji_selection_clear(struct shoji_selection *sel);

#endif /* SHOJI_INSTANCES_H */
