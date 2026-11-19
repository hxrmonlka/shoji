#define _POSIX_C_SOURCE 200809L

#include "instances.h"
#include "json.h"
#include "util.h"

#include <limits.h>
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

        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')
                p++;
        if (*p == '\0')
                return 1;
        return strncmp(p, "No running instances.", 21) == 0;
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
        inst->pid = (pid && pid->type == SHOJI_JSON_NUMBER) ? (long)pid->number : -1;
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

        /* Dead-instance diagnostics (compatibility probe). Upstream marks a
         * row dead ONLY by its absence from the live list: the JSON of a
         * dead row carries the launch-time InstanceInfo::pid, which can
         * stay positive after a crash (src/core/paths.cpp checkLock reads
         * the lock holder separately; listInstances prints
         * instance.instance.pid). Rows found here that the live listing
         * did not report are therefore dead regardless of their pid and
         * never become IPC candidates.
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

        pr = parse_listing(r->out, list, 1, &errpos);
        shj_proc_result_free(r);
        if (pr == -1)
                shj_msg("could not parse the dead-instance listing; "
                        "dead-instance diagnostics skipped");
        else if (pr == -2)
                shj_msg("the dead-instance listing was not a JSON array; "
                        "dead-instance diagnostics skipped");
        else if (pr == 0)
                dedupe_dead_rows(list, live_count);
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

/* Parse quickshell's launch_time ("YYYY-MM-DDTHH:MM:SS"): Qt::ISODate of a
 * local-time QDateTime (src/core/common.cpp Common::LAUNCH_TIME is
 * QDateTime::currentDateTime()), so mktime() in the local zone yields a
 * value comparable with st_mtime. Strictly rejects trailing content (no
 * offset or fractional seconds are accepted): an unparseable launch time
 * degrades matching to "uncertain" instead of widening the match window.
 * Returns 0 on success. */
static int parse_launch_time(const char *s, long *epoch)
{
        int y, mo, d, h, mi, sec, npos = 0;
        char sep;
        struct tm tm;

        if (!s || sscanf(s, "%4d-%2d-%2d%c%2d:%2d:%2d%n",
                         &y, &mo, &d, &sep, &h, &mi, &sec, &npos) != 7)
                return -1;
        if (s[npos] != '\0')
                return -1;
        if ((sep != 'T' && sep != 't' && sep != ' ') || mo < 1 || mo > 12 || d < 1 ||
            d > 31 || h < 0 || h > 23 || mi < 0 || mi > 59 || sec < 0 || sec > 61)
                return -1;
        memset(&tm, 0, sizeof(tm));
        tm.tm_year = y - 1900;
        tm.tm_mon = mo - 1;
        tm.tm_mday = d;
        tm.tm_hour = h;
        tm.tm_min = mi;
        tm.tm_sec = sec;
        tm.tm_isdst = -1;
        *epoch = (long)mktime(&tm);
        if (*epoch < 0)
                return -1;
        return 0;
}

/* Walk every component of path and report the newest modification time
 * among the SYMLINK components (a mutable alias chain, e.g. a Home-Manager
 * generation link). Returns 1 when at least one component is a symlink,
 * 0 when the path has none (or cannot be inspected). */
static int alias_witness(const char *path, long *newest)
{
        char buf[PATH_MAX];
        struct stat st;
        const char *p = path;
        size_t len = 0;
        int found = 0;

        if (!path || !*path || strlen(path) >= sizeof(buf))
                return 0;
        if (path[0] == '/')
                buf[len++] = '/';
        for (;;) {
                const char *q;
                size_t clen;

                while (*p == '/')
                        p++;
                if (!*p)
                        break;
                q = strchr(p, '/');
                clen = q ? (size_t)(q - p) : strlen(p);
                if (len > 0 && buf[len - 1] != '/')
                        buf[len++] = '/';
                memcpy(buf + len, p, clen);
                len += clen;
                buf[len] = '\0';
                if (lstat(buf, &st) == 0 && S_ISLNK(st.st_mode)) {
                        if (!found || st.st_mtime > (time_t)*newest)
                                *newest = (long)st.st_mtime;
                        found = 1;
                }
                if (!q)
                        break;
                p = q;
        }
        return found;
}

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

        /* Configuration identity policy.
         *
         * Upstream evidence (quickshell master, 0.3.x line): the per-
         * instance lock file stores InstanceInfo serialized at launch
         * (src/core/paths.cpp QsPaths::createLock), and
         * InstanceInfo::configPath is the path quickshell launched with
         * after locateConfigFile/locateNamedConfig -- QFileInfo(path).
         * absoluteFilePath(), i.e. absolute but NOT symlink-resolved.
         * `qs list -j` prints exactly that recorded string
         * (src/launch/command.cpp listInstances). quickshell exposes no
         * launch-time canonical path (shell_id is an MD5 of the same
         * recorded string; launch_time is the wall-clock launch second).
         *
         * Therefore the recorded path is trustworthy launch-time identity
         * ONLY as a string. Re-resolving it with realpath() at selection
         * time would read a mutable alias's CURRENT target (a Home-Manager
         * or Nix generation symlink retargeted to generation B), making an
         * instance that still runs generation A look like B.
         *
         * 1. recorded path == canonical expected path: the instance was
         *    launched with exactly this path; the match is certain.
         * 2. recorded path currently RESOLVES to the expected path through
         *    a symlink chain: the chain's newest symlink mtime is the
         *    retarget witness. If every alias component was last
         *    retargeted strictly BEFORE the instance's launch time, the
         *    chain has not moved since launch, so its current target IS
         *    the configuration loaded at launch: match. Otherwise (alias
         *    retargeted at or after launch, second-granularity ties, or an
         *    unparseable launch time): the loaded generation is uncertain
         *    (-1): no automatic match, explicit --instance-id required.
         * 3. anything else: no match. A garbage-collected recorded path
         *    only ever matches by its recorded string (case 1). */
        expected_real = shj_realpath_safe(expected_qml);
        if (!expected_real) {
                /* The expected path does not resolve (missing store, foreign
                 * config, test data): fall back to the given spelling. Only
                 * an exact string match can come out of this, never a
                 * re-resolved alias. */
                expected_real = shj_strdup(expected_qml);
        }
        if (strcmp(rec, expected_real) == 0) {
                free(expected_real);
                return 1;
        }
        rec_real = shj_realpath_safe(rec);
        if (rec_real && strcmp(rec_real, expected_real) == 0) {
                long witness = 0, launched = 0;

                if (!alias_witness(rec, &witness)) {
                        match = 1; /* spelling difference without an alias: stable identity */
                } else if (parse_launch_time(inst->launch_time, &launched) == 0 &&
                           witness < launched) {
                        match = 1;
                } else {
                        match = -1;
                }
        }
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
                                /* Mutable alias retargeted after launch: the
                                 * loaded generation is uncertain, so the row
                                 * is never an automatic candidate. */
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

        if (instance_id_override && *instance_id_override) {
                /* Explicit override: prefix-match against every known
                 * instance with a usable id (same rule quickshell applies
                 * for -i; an empty selector would be skipped by quickshell
                 * and must never be forwarded). The matched instances are
                 * published through matches[] so the caller can list them
                 * when the prefix is ambiguous. */
                int id_matches = 0;
                struct shoji_instance *pick = NULL;

                for (i = 0; i < list->count; i++) {
                        if (!list->items[i].id_valid)
                                continue;
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
