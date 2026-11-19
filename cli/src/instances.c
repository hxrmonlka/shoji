#define _POSIX_C_SOURCE 200809L

#include "instances.h"
#include "json.h"
#include "util.h"

#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

/* `qs list -j` prints the bare log line "No running instances." (or nothing
 * at all) when no instance exists, instead of a JSON array: the empty-list
 * branch of upstream `qs list` runs before the JSON encoder, and the
 * quickshell.bare category prints unadorned text on stdout. Accept both as
 * an empty list rather than a parse failure. */
static int list_output_is_empty_notice(const char *out)
{
        const char *p = out ? out : "";

        static const char notice[] = "No running instances.";
        const char *end;

        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' ||
               *p == '\f' || *p == '\v')
                p++;
        if (*p == '\0')
                return 1;
        if (strncmp(p, notice, sizeof(notice) - 1) != 0)
                return 0;
        end = p + sizeof(notice) - 1;
        while (*end == ' ' || *end == '\t' || *end == '\n' || *end == '\r' ||
               *end == '\f' || *end == '\v')
                end++;
        return *end == '\0';
}

/* quickshell generates instance ids as base36(pid) + base36(launch epoch)
 * (src/launch/launch.cpp launch()), so real ids are non-empty and contain
 * no whitespace. `qs ipc -i` treats an empty selector as absent and
 * silently falls back to config-based selection
 * (src/launch/command.cpp selectInstance), so shoji must never forward
 * one. Accept any non-empty id without whitespace or control characters. */
static int instance_id_valid(const char *id)
{
        const char *p;

        if (!id || !*id)
                return 0;
        for (p = id; *p; p++) {
                if ((unsigned char)*p < 0x21 || (unsigned char)*p == 0x7f)
                        return 0;
        }
        return 1;
}

/* Append one parsed listing row (dead = 1 for dead-diagnostics rows).
 * Returns the appended row, or NULL when `row` is not a JSON object. */
static struct shoji_instance *append_row(struct shoji_instance_list *list,
                                         const struct shj_json *row, int dead)
{
        struct shoji_instance *inst;
        struct shoji_instance *items;
        const struct shj_json *jid, *pid, *sid, *cfg, *lt;

        if (row->type != SHOJI_JSON_OBJECT)
                return NULL;

        items = shj_realloc(list->items,
                            sizeof(struct shoji_instance) * (size_t)(list->count + 1));
        list->items = items;
        inst = &list->items[list->count];

        memset(inst, 0, sizeof(*inst));
        jid = shj_json_get(row, "id");
        pid = shj_json_get(row, "pid");
        sid = shj_json_get(row, "shell_id");
        cfg = shj_json_get(row, "config_path");
        lt = shj_json_get(row, "launch_time");

        inst->id = shj_strdup(shj_json_str(jid, ""));
        inst->shell_id = shj_strdup(shj_json_str(sid, ""));
        inst->config_path = shj_strdup(shj_json_str(cfg, ""));
        inst->launch_time = shj_strdup(shj_json_str(lt, ""));
        /* JSON numbers are doubles. Validate before casting: out-of-range or
         * fractional values cannot safely become a pid_t/long selector. */
        inst->pid = -1;
        if (pid && pid->type == SHOJI_JSON_NUMBER && isfinite(pid->number) &&
            pid->number >= 1.0 && pid->number <= (double)INT_MAX &&
            pid->number == (double)(long)pid->number)
                inst->pid = (long)pid->number;
        inst->id_valid = instance_id_valid(inst->id);
        inst->dead = dead;
        list->count++;
        return inst;
}

/* Parse a whole listing array into rows. `dead` marks rows discovered only
 * through the dead-instance listing. Returns 0 on success, 1 when the
 * output was the bare empty-list notice, -1 on a parse error (errpos set),
 * -2 when the output was not an array. */
static int parse_listing(const char *out, struct shoji_instance_list *list,
                         int dead, size_t *errpos)
{
        struct shj_json *arr;
        struct shj_json *it;

        arr = shj_json_parse(out ? out : "", errpos);
        if (!arr) {
                if (list_output_is_empty_notice(out))
                        return 1; /* empty listing, not a failure */
                return -1;
        }
        if (arr->type != SHOJI_JSON_ARRAY) {
                shj_json_free(arr);
                return -2;
        }
        for (it = arr->items; it; it = it->next) {
                /* The live listing only contains instances that currently
                 * hold their instance lock, so their JSON pid (the
                 * launch-time record, which coincides with the lock holder
                 * for live rows) is usable for dispatch. A nonpositive pid
                 * in a live row would be unusable; treat it as dead. */
                if (!dead) {
                        struct shoji_instance *inst = append_row(list, it, 0);

                        if (inst && inst->pid <= 0)
                                inst->dead = 1;
                } else {
                        append_row(list, it, 1);
                }
        }
        shj_json_free(arr);
        return 0;
}

/* Drop rows discovered by the dead-instance listing that also appear (by
 * instance id) among the first `live_count` rows: the live listing always
 * wins. */
static void dedupe_dead_rows(struct shoji_instance_list *list, int live_count)
{
        int i, j;

        for (i = live_count; i < list->count; i++) {
                for (j = 0; j < live_count; j++) {
                        if (list->items[i].id && list->items[j].id &&
                            strcmp(list->items[i].id, list->items[j].id) == 0) {
                                int k;

                                free(list->items[i].id);
                                free(list->items[i].shell_id);
                                free(list->items[i].config_path);
                                free(list->items[i].launch_time);
                                for (k = i; k < list->count - 1; k++)
                                        list->items[k] = list->items[k + 1];
                                list->count--;
                                i--;
                                break;
                        }
                }
        }
}

static void free_instance(struct shoji_instance *inst)
{
        free(inst->id);
        free(inst->shell_id);
        free(inst->config_path);
        free(inst->launch_time);
        memset(inst, 0, sizeof(*inst));
}

static struct shoji_instance *find_instance_id(struct shoji_instance_list *list,
                                                 const char *id)
{
        int i;

        if (!id || !*id)
                return NULL;
        for (i = 0; i < list->count; i++) {
                if (list->items[i].id && strcmp(list->items[i].id, id) == 0)
                        return &list->items[i];
        }
        return NULL;
}

static void copy_instance(struct shoji_instance *dst,
                          const struct shoji_instance *src)
{
        free_instance(dst);
        *dst = *src;
        dst->id = shj_strdup(src->id ? src->id : "");
        dst->shell_id = shj_strdup(src->shell_id ? src->shell_id : "");
        dst->config_path = shj_strdup(src->config_path ? src->config_path : "");
        dst->launch_time = shj_strdup(src->launch_time ? src->launch_time : "");
}

static void remove_rows_from(struct shoji_instance_list *list, int first)
{
        while (list->count > first) {
                list->count--;
                free_instance(&list->items[list->count]);
        }
}

/* A successful fresh live listing is authoritative for selection. Preserve
 * rows that disappeared only as dead diagnostics, and add newly live rows. */
static void reconcile_live_snapshot(struct shoji_instance_list *list,
                                    const struct shoji_instance_list *fresh)
{
        int i;

        for (i = 0; i < list->count; i++) {
                struct shoji_instance *old = &list->items[i];
                const struct shoji_instance *current = NULL;

                for (int j = 0; j < fresh->count; j++) {
                        if (old->id && fresh->items[j].id &&
                            strcmp(old->id, fresh->items[j].id) == 0) {
                                current = &fresh->items[j];
                                break;
                        }
                }
                if (current) {
                        copy_instance(old, current);
                        old->dead = 0;
                } else {
                        old->dead = 1;
                }
        }
        for (i = 0; i < fresh->count; i++) {
                if (!find_instance_id(list, fresh->items[i].id)) {
                        list->items = shj_realloc(list->items,
                                sizeof(*list->items) * (size_t)(list->count + 1));
                        memset(&list->items[list->count], 0, sizeof(*list->items));
                        copy_instance(&list->items[list->count], &fresh->items[i]);
                        list->items[list->count].dead = 0;
                        list->count++;
                }
        }
}

struct shoji_instance_list *shoji_discover_instances(shj_spawn_fn spawn, void *user,
                                                     const char *qs_bin,
                                                     enum shoji_discover_err *err)
{
        const char *argv_live[] = { qs_bin, "list", "-a", "-j", NULL };
        const char *argv_dead[] = { qs_bin, "list", "-a", "-j", "--show-dead", NULL };
        struct shj_proc_result *r;
        struct shoji_instance_list *list;
        int live_count, pr;
        size_t errpos = 0;

        if (err)
                *err = SHOJI_DISCOVER_OK;

        /* Authoritative live listing. Upstream `qs list` without
         * --show-dead outputs only instances that currently hold their
         * fcntl instance lock (src/launch/command.cpp listInstances; the
         * classification happens in src/core/paths.cpp collectInstances
         * via QsPaths::checkLock). A failure of THIS command is a real
         * discovery failure and is never retried or masked: a timeout
         * stays a timeout, a failed exec stays a missing executable, an
         * internal subprocess failure stays internal. None of these is a
         * compatibility problem, so no fallback applies. */
        r = spawn(argv_live, user);
        if (!r) {
                if (err)
                        *err = SHOJI_DISCOVER_INTERNAL;
                shj_msg("instance discovery: the subprocess interface failed");
                return NULL;
        }
        if (r->exit == SHJ_PROC_EXIT_SPAWN) {
                shj_msg("cannot execute quickshell (%s): %s", qs_bin, strerror(r->spawn_errno));
                if (err)
                        *err = SHOJI_DISCOVER_NOEXEC;
                shj_proc_result_free(r);
                return NULL;
        }
        if (r->exit == SHJ_PROC_EXIT_TIMEOUT) {
                shj_msg("quickshell instance discovery timed out");
                shj_hint("quickshell did not respond within %ld ms "
                         "(SHOJI_QS_TIMEOUT_MS overrides the timeout)",
                         shj_proc_get_timeout_ms());
                if (err)
                        *err = SHOJI_DISCOVER_TIMEOUT;
                shj_proc_result_free(r);
                return NULL;
        }
        if (r->exit == SHJ_PROC_EXIT_INTERNAL) {
                shj_msg("internal error reading quickshell output: %s",
                        strerror(r->spawn_errno));
                if (err)
                        *err = SHOJI_DISCOVER_INTERNAL;
                shj_proc_result_free(r);
                return NULL;
        }
        if (r->exit < 0) {
                /* Unknown negative class: an internal failure by contract. */
                shj_msg("internal error running quickshell (exit %d)", r->exit);
                if (err)
                        *err = SHOJI_DISCOVER_INTERNAL;
                shj_proc_result_free(r);
                return NULL;
        }
        if (r->exit != 0) {
                /* quickshell ran and failed the listing itself. This is a
                 * generic quickshell failure, not a compatibility failure:
                 * there is no retry and no fallback. */
                shj_msg("quickshell instance discovery failed (qs list -a -j, exit %d)",
                        r->exit);
                if (r->err && *r->err)
                        shj_msg("qs said: %s", r->err);
                if (err)
                        *err = SHOJI_DISCOVER_FAILED;
                shj_proc_result_free(r);
                return NULL;
        }
        if (r->truncated & SHOJI_TRUNC_OUT) {
                shj_msg("quickshell instance listing was truncated; refusing incomplete data");
                if (err)
                        *err = SHOJI_DISCOVER_BADJSON;
                shj_proc_result_free(r);
                return NULL;
        }

        list = shj_alloc(sizeof(*list));
        list->count = 0;
        list->items = shj_alloc(sizeof(struct shoji_instance));
        pr = parse_listing(r->out, list, 0, &errpos);
        shj_proc_result_free(r);
        if (pr == 1) {
                /* The live listing is empty, but the dead-instance probe
                 * still runs: dead diagnostics are its whole purpose. */
                live_count = 0;
        } else if (pr != 0) {
                if (pr == -1) {
                        if (errpos)
                                shj_msg("could not parse `qs list -j` output at byte %zu",
                                        errpos);
                        else
                                shj_msg("could not parse `qs list -j` output");
                } else {
                        shj_msg("`qs list -j` did not return a JSON array");
                }
                if (err)
                        *err = SHOJI_DISCOVER_BADJSON;
                shoji_instance_list_free(list);
                return NULL;
        } else {
                /* Rows reported by the live listing; the dead probe may only
                 * add rows that are NOT already here. */
                live_count = list->count;
        }

        /* Dead-instance diagnostics (compatibility probe). The JSON of a
         * dead row carries the launch-time InstanceInfo::pid, which can stay
         * positive after a crash (src/core/paths.cpp checkLock reads the lock
         * holder separately; listInstances prints instance.instance.pid).
         * Rows absent from the first live snapshot are rechecked against a
         * fresh live listing before they are classified as dead, because a
         * new instance may have started between the two probes.
         *
         * When this probe fails -- most commonly because the running
         * quickshell build does not support --show-dead -- discovery
         * continues without dead diagnostics. The probe is strictly
         * additive: its failure can never mask or alter the live result
         * above, and a generic quickshell failure here does not change the
         * exit-code classification of discovery. */
        r = spawn(argv_dead, user);
        if (!r || r->exit != 0) {
                if (r && r->exit < 0)
                        shj_msg("dead-instance listing skipped (%s)",
                                r->exit == SHJ_PROC_EXIT_TIMEOUT ? "timed out"
                                : r->exit == SHJ_PROC_EXIT_INTERNAL ? "internal error"
                                                                    : "quickshell could not be executed");
                /* exit > 0: quickshell rejected the listing command itself.
                 * A normal rejection of the unsupported --show-dead option
                 * (older quickshell) is the expected compatibility fallback;
                 * any other rejection loses only the optional dead-instance
                 * diagnostics. */
                shj_proc_result_free(r);
                return list;
        }

        if (r->truncated & SHOJI_TRUNC_OUT) {
                shj_msg("dead-instance listing was truncated; diagnostics skipped");
                shj_proc_result_free(r);
                return list;
        }
        pr = parse_listing(r->out, list, 1, &errpos);
        shj_proc_result_free(r);
        if (pr == -1)
                shj_msg("could not parse the dead-instance listing; "
                        "dead-instance diagnostics skipped");
        else if (pr == -2)
                shj_msg("the dead-instance listing was not a JSON array; "
                        "dead-instance diagnostics skipped");
        else if (pr == 0) {
                struct shoji_instance_list fresh;
                struct shj_proc_result *check;
                int have_new_rows;

                dedupe_dead_rows(list, live_count);
                have_new_rows = list->count > live_count;
                if (!have_new_rows)
                        return list;

                check = spawn(argv_live, user);
                if (!check || check->exit != 0 ||
                    (check->truncated & SHOJI_TRUNC_OUT)) {
                        shj_msg("new instance rows could not be verified; "
                                "unconfirmed dead-instance diagnostics skipped");
                        shj_proc_result_free(check);
                        remove_rows_from(list, live_count);
                        return list;
                }

                memset(&fresh, 0, sizeof(fresh));
                fresh.items = shj_alloc(sizeof(*fresh.items));
                pr = parse_listing(check->out, &fresh, 0, &errpos);
                shj_proc_result_free(check);
                if (pr < 0) {
                        shj_msg("could not verify newly discovered instance rows; "
                                "unconfirmed diagnostics skipped");
                        while (fresh.count > 0) {
                                fresh.count--;
                                free_instance(&fresh.items[fresh.count]);
                        }
                        free(fresh.items);
                        remove_rows_from(list, live_count);
                        return list;
                }
                /* pr == 1 is a valid, complete empty live snapshot. */
                reconcile_live_snapshot(list, &fresh);
                while (fresh.count > 0) {
                        fresh.count--;
                        free_instance(&fresh.items[fresh.count]);
                }
                free(fresh.items);
        }
        return list;
}

void shoji_instance_list_free(struct shoji_instance_list *list)
{
        int i;

        if (!list)
                return;
        for (i = 0; i < list->count; i++) {
                free(list->items[i].id);
                free(list->items[i].shell_id);
                free(list->items[i].config_path);
                free(list->items[i].launch_time);
        }
        free(list->items);
        free(list);
}

int shoji_live_count(const struct shoji_instance_list *list)
{
        int i, n = 0;

        for (i = 0; i < list->count; i++)
                if (!list->items[i].dead)
                        n++;
        return n;
}

/* Establish configuration identity only from the recorded launch-time path.
 * The path is not canonicalized by Quickshell at launch, and launch_time has
 * no timezone, so symlink metadata cannot prove which generation was loaded. */
int shoji_instance_matches_config(const struct shoji_instance *inst,
                                  const char *expected_qml)
{
        const char *rec;
        char *expected_real, *rec_real;
        int match = 0;

        if (!inst || !expected_qml || !*expected_qml)
                return 0;
        rec = inst->config_path;
        if (!rec || !*rec)
                return 0;

        /* quickshell records the config path string at launch, but does not
         * provide a launch-time canonical path. An exact string comparison
         * against the canonical expected path is reliable. If the recorded
         * path currently resolves to that config via a mutable alias, the
         * original launch-time target cannot be established; do not infer
         * identity from symlink mtimes or launch_time (which has no timezone).
         * Mark the result uncertain and require explicit --instance-id. */
        expected_real = shj_realpath_safe(expected_qml);
        if (!expected_real)
                expected_real = shj_strdup(expected_qml);
        if (strcmp(rec, expected_real) == 0) {
                free(expected_real);
                return 1;
        }
        rec_real = shj_realpath_safe(rec);
        if (rec_real && strcmp(rec_real, expected_real) == 0)
                match = -1;
        free(rec_real);
        free(expected_real);
        return match;
}

enum shoji_select_status shoji_select_instance(const struct shoji_instance_list *list,
                                               const char *expected_qml,
                                               const char *instance_id_override,
                                               struct shoji_selection *out)
{
        int i;
        int live_matches = 0;
        char *expected_real = NULL;

        memset(out, 0, sizeof(*out));
        if (!list)
                return SHOJI_SELECT_ERROR;

        out->matches = shj_alloc(sizeof(*out->matches) * (size_t)(list->count ? list->count : 1));
        out->dead_matches = shj_alloc(sizeof(*out->dead_matches) * (size_t)(list->count ? list->count : 1));

        if (expected_qml)
                expected_real = shj_realpath_safe(expected_qml);

        for (i = 0; i < list->count; i++) {
                struct shoji_instance *inst = &list->items[i];
                int match = 0;

                if (expected_qml) {
                        match = shoji_instance_matches_config(inst, expected_real ? expected_real : expected_qml);
                        if (match < 0) {
                                /* Only live rows represent a running shell.
                                 * Dead aliases are diagnostic records, not
                                 * uncertain running instances. */
                                if (!inst->dead)
                                        out->uncertain_matches++;
                                match = 0;
                        }
                }

                if (!match)
                        continue;
                if (inst->dead)
                        out->dead_matches[out->dead_match_count++] = inst;
                else if (inst->id_valid)
                        out->matches[out->match_count++] = inst;
                else
                        out->invalid_id_matches++;
        }
        free(expected_real);

        if (instance_id_override) {
                /* An explicitly supplied empty selector is never equivalent
                 * to omission: qs treats -i "" as absent and can fall back to
                 * config-based dispatch. */
                int id_matches = 0;
                int dead_id_matches = 0;
                struct shoji_instance *pick = NULL;

                if (!*instance_id_override) {
                        out->match_count = 0;
                        out->dead_match_count = 0;
                        out->selected = NULL;
                        out->status = SHOJI_SELECT_NONE;
                        return SHOJI_SELECT_NONE;
                }
                /* Resolve against live rows first. Dead rows are retained for
                 * diagnostics only and cannot make a live prefix ambiguous. */
                for (i = 0; i < list->count; i++) {
                        struct shoji_instance *inst = &list->items[i];

                        if (!inst->id_valid || inst->dead ||
                            strncmp(inst->id, instance_id_override,
                                    strlen(instance_id_override)) != 0)
                                continue;
                        out->matches[id_matches++] = inst;
                        pick = inst;
                }
                if (id_matches == 0) {
                        out->dead_match_count = 0;
                        for (i = 0; i < list->count; i++) {
                                struct shoji_instance *inst = &list->items[i];

                                if (inst->id_valid && inst->dead &&
                                    strncmp(inst->id, instance_id_override,
                                            strlen(instance_id_override)) == 0)
                                        out->dead_matches[dead_id_matches++] = inst;
                        }
                        out->dead_match_count = dead_id_matches;
                        out->match_count = 0;
                        out->status = SHOJI_SELECT_NONE;
                        return SHOJI_SELECT_NONE;
                }
                if (id_matches > 1) {
                        out->match_count = id_matches;
                        out->status = SHOJI_SELECT_AMBIGUOUS;
                        return SHOJI_SELECT_AMBIGUOUS;
                }
                /* The override wins regardless of the config path match; the
                 * caller surfaces whether it actually matched the expected
                 * config so nothing is dispatched silently to a foreign shell. */
                out->selected = pick;
                out->status = SHOJI_SELECT_OK;
                return SHOJI_SELECT_OK;
        }

        live_matches = out->match_count;
        if (live_matches == 1) {
                out->selected = out->matches[0];
                out->status = SHOJI_SELECT_OK;
        } else if (live_matches == 0) {
                out->status = SHOJI_SELECT_NONE;
        } else {
                out->status = SHOJI_SELECT_AMBIGUOUS;
        }
        return out->status;
}

void shoji_selection_clear(struct shoji_selection *sel)
{
        if (!sel)
                return;
        free(sel->matches);
        free(sel->dead_matches);
        memset(sel, 0, sizeof(*sel));
}
