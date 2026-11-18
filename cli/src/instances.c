#define _POSIX_C_SOURCE 200809L

#include "instances.h"
#include "json.h"
#include "util.h"

#include <stdlib.h>
#include <string.h>

/* `qs list -j` prints the bare log line "No running instances." (or nothing
 * at all) when no instance exists, instead of a JSON array: the empty-list
 * branch of upstream `qs list` runs before the JSON encoder, and the
 * quickshell.bare category prints unadorned text on stdout. Accept both as
 * an empty list rather than a parse failure. */
static int list_output_is_empty_notice(const char *out)
{
        const char *p = out ? out : "";

        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
                p++;
        if (*p == '\0')
                return 1;
        return strncmp(p, "No running instances.", 21) == 0;
}

static struct shoji_instance_list *empty_list(void)
{
        struct shoji_instance_list *list = shj_alloc(sizeof(*list));

        list->count = 0;
        list->items = shj_alloc(sizeof(struct shoji_instance));
        return list;
}

struct shoji_instance_list *shoji_discover_instances(shj_spawn_fn spawn, void *user,
                                                     const char *qs_bin, int *err)
{
        const char *argv_full[] = { qs_bin, "list", "-a", "-j", "--show-dead", NULL };
        const char *argv_plain[] = { qs_bin, "list", "-a", "-j", NULL };
        struct shj_proc_result *r;
        struct shoji_instance_list *list;
        struct shj_json *arr;
        size_t errpos = 0;
        int i;

        if (err)
                *err = 0;

        r = spawn(argv_full, user);
        if (!r) {
                if (err)
                        *err = -1;
                return NULL;
        }
        if (r->exit == -1) {
                /* Could not start quickshell at all. */
                if (err)
                        *err = -2;
                shj_msg("cannot execute quickshell (%s): %s", qs_bin, strerror(r->spawn_errno));
                shj_proc_result_free(r);
                return NULL;
        }
        if (r->exit != 0) {
                /* Older quickshell versions lack --show-dead; retry without it. */
                shj_proc_result_free(r);
                r = spawn(argv_plain, user);
                if (!r || r->exit != 0) {
                        if (r && r->exit >= 0) {
                                shj_msg("quickshell instance discovery failed (qs list -a -j, exit %d)",
                                        r->exit);
                                if (r->err && *r->err)
                                        shj_msg("qs said: %s", r->err);
                                if (err)
                                        *err = -3;
                        } else if (err) {
                                *err = -2;
                        }
                        shj_proc_result_free(r);
                        return NULL;
                }
        }

        arr = shj_json_parse(r->out ? r->out : "", &errpos);
        if (!arr) {
                if (list_output_is_empty_notice(r->out)) {
                        shj_proc_result_free(r);
                        return empty_list();
                }
                if (errpos)
                        shj_msg("could not parse `qs list -j` output at byte %zu", errpos);
                else
                        shj_msg("could not parse `qs list -j` output");
                shj_proc_result_free(r);
                if (err)
                        *err = -4;
                return NULL;
        }
        if (arr->type != SHOJI_JSON_ARRAY) {
                shj_msg("`qs list -j` did not return a JSON array");
                shj_json_free(arr);
                shj_proc_result_free(r);
                if (err)
                        *err = -4;
                return NULL;
        }

        list = shj_alloc(sizeof(*list));
        list->count = 0;
        for (struct shj_json *it = arr->items; it; it = it->next)
                list->count++;
        list->items = shj_alloc(sizeof(struct shoji_instance) * (size_t)(list->count ? list->count : 1));

        i = 0;
        for (struct shj_json *it = arr->items; it; it = it->next, i++) {
                struct shoji_instance *inst = &list->items[i];
                struct shj_json *jid = shj_json_get(it, "id");
                struct shj_json *pid = shj_json_get(it, "pid");
                struct shj_json *sid = shj_json_get(it, "shell_id");
                struct shj_json *cfg = shj_json_get(it, "config_path");
                struct shj_json *lt = shj_json_get(it, "launch_time");

                memset(inst, 0, sizeof(*inst));
                inst->id = shj_strdup(shj_json_str(jid, ""));
                inst->shell_id = shj_strdup(shj_json_str(sid, ""));
                inst->config_path = shj_strdup(shj_json_str(cfg, ""));
                inst->launch_time = shj_strdup(shj_json_str(lt, ""));
                inst->pid = (pid && pid->type == SHOJI_JSON_NUMBER) ? (long)pid->number : -1;
                /* Upstream quickshell derives the pid from the fcntl write
                 * lock on the instance lock file: a live instance reports the
                 * lock holder's pid, a dead one reports -1
                 * (src/core/paths.cpp, QsPaths::checkLock). No liveness probe
                 * is needed or more accurate than that. */
                inst->dead = inst->pid <= 0;
        }

        shj_json_free(arr);
        shj_proc_result_free(r);
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

char *shoji_instance_canonical_config(const struct shoji_instance *inst)
{
        char *real = inst->config_path ? shj_realpath_safe(inst->config_path) : NULL;

        if (real)
                return real;
        return shj_strdup(inst->config_path ? inst->config_path : "");
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
                int path_match = 0;

                if (expected_qml) {
                        char *inst_real = shoji_instance_canonical_config(inst);

                        path_match = strcmp(inst_real, expected_real ? expected_real : expected_qml) == 0;
                        free(inst_real);
                }

                if (!inst->dead && path_match)
                        out->matches[out->match_count++] = inst;
                if (inst->dead && path_match)
                        out->dead_matches[out->dead_match_count++] = inst;
        }
        free(expected_real);

        if (instance_id_override && *instance_id_override) {
                /* Explicit override: prefix-match against every known instance
                 * (same rule quickshell applies for -i). The matched instances
                 * are published through matches[] so the caller can list them
                 * when the prefix is ambiguous. */
                int id_matches = 0;
                struct shoji_instance *pick = NULL;

                for (i = 0; i < list->count; i++) {
                        if (strncmp(list->items[i].id, instance_id_override,
                                    strlen(instance_id_override)) == 0) {
                                out->matches[id_matches++] = &list->items[i];
                                pick = &list->items[i];
                        }
                }
                if (id_matches == 0) {
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
