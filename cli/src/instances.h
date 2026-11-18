/*
 * shoji-cli -- quickshell instance discovery and selection.
 *
 * Discovery always goes through quickshell's own CLI (`qs list -a -j
 * [--show-dead]`); this file only parses its JSON and implements the
 * matching policy. The CLI never dispatches based on a bare `qs -p PATH`
 * invocation, because quickshell silently picks the oldest instance of a
 * config when several match -- shoji instead selects an instance itself and
 * dispatches with the full, unique instance id.
 *
 * Selection policy (shoji_select_instance):
 *   - candidates are live instances (pid > 0) whose canonical config_path
 *     equals the canonical expected store path (when expected != NULL;
 *     otherwise only --instance-id resolution applies);
 *   - exactly one candidate  -> selected;
 *   - none                   -> SHOJI_SELECT_NONE (dead instances reported
 *                               separately for diagnostics);
 *   - more than one          -> SHOJI_SELECT_AMBIGUOUS unless --instance-id
 *                               resolves one candidate (prefix match on the
 *                               instance id, same rule quickshell uses);
 *   - --instance-id that matches no known instance -> SHOJI_SELECT_NONE.
 */
#ifndef SHOJI_INSTANCES_H
#define SHOJI_INSTANCES_H

#include "proc.h"

struct shoji_instance {
	char *id;           /* quickshell instance id (unique) */
	long pid;           /* -1 for dead instances */
	char *shell_id;
	char *config_path;  /* recorded at launch; may be gone (GC) */
	char *launch_time;  /* Qt ISO date string */
	int dead;           /* 1 when the lock file belongs to a dead instance */
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
};

/* Run `qs list -a -j --show-dead` (falls back to a probe without
 * --show-dead on older quickshell) via the injected spawn function. */
struct shoji_instance_list *shoji_discover_instances(shj_spawn_fn spawn, void *user,
                                                     const char *qs_bin, int *err);

void shoji_instance_list_free(struct shoji_instance_list *list);

/* Count of live instances in the list. */
int shoji_live_count(const struct shoji_instance_list *list);

/* Canonicalized config path of an instance (malloc'd); falls back to the
 * recorded path when it no longer resolves (e.g. garbage-collected). */
char *shoji_instance_canonical_config(const struct shoji_instance *inst);

/* Selection policy; see header comment. expected_qml may be NULL.
 * `out` borrows pointers into `list`; both must outlive it. */
enum shoji_select_status shoji_select_instance(const struct shoji_instance_list *list,
                                               const char *expected_qml,
                                               const char *instance_id_override,
                                               struct shoji_selection *out);

void shoji_selection_clear(struct shoji_selection *sel);

#endif /* SHOJI_INSTANCES_H */
