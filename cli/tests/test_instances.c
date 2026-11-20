/* shoji-cli tests -- instance discovery, selection policy and dispatch argv.
 *
 * Uses a fake spawn function that records the argv vector shoji builds and
 * returns canned `qs list -j` output; no real quickshell is involved.
 * Discovery behavior is scripted per invocation so failure classes,
 * compatibility fallbacks and invocation counts are checked directly, and
 * the live and dead listings can be fed separately.
 */
#include "testmain.h"
#include "dispatch.h"
#include "instances.h"
#include "exitcodes.h"
#include "json.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "report.h"

static char g_tmp[256];
/* g_expected holds g_tmp plus "/store/aaaaaaaa-shoji/shell.qml", sized so
 * the suffix provably fits GCC's -Wformat-truncation analysis. */
static char g_expected[512];

/* rotate 8 static buffers for building small paths in tests */
static const char *cat2(const char *a, const char *b)
{
        static char bufs[8][1024];
        static int i = 0;
        char *p = bufs[i++ % 8];

        snprintf(p, 1024, "%s%s", a, b);
        return p;
}

/* write a small file, checking every step; returns 0 on success */
static int write_file(const char *path, const char *text)
{
        FILE *f = fopen(path, "w");
        int w, c;

        if (!f)
                return -1;
        w = fputs(text, f);
        c = fclose(f);
        return (w == EOF || c != 0) ? -1 : 0;
}

/* canned quickshell behavior ------------------------------------------- */

static char g_recorded[4096];
static char g_json_live[2048];
static char g_json_dead[2048];
static char g_json_recheck[2048];
static const char *g_list_json;   /* authoritative live listing output */
static const char *g_dead_json;   /* --show-dead output; NULL = same as live */
static const char *g_recheck_json; /* optional fresh live output; NULL = live output */
static int g_list_arg_errors;
static unsigned g_list_truncated;
static int g_ipc_calls;
static int g_ipc_argc;
static char g_ipc_argv[16][256];
static int g_call_exit = 0;
static const char *g_call_err = "";
static const char *g_call_out = "";
/* Scripted `list` behavior: each discovery invocation consumes the next
 * entry. >= 0 is a quickshell exit code (0 with the canned listing,
 * nonzero a rejection); negative values are shj_proc failure classes. */
static int g_list_script[8];
static int g_list_script_len;
static int g_list_calls;

static void set_list(const char *fmt, ...)
{
        va_list ap;

        va_start(ap, fmt);
        vsnprintf(g_json_live, sizeof(g_json_live), fmt, ap);
        va_end(ap);
        g_list_json = g_json_live;
}

static void set_dead_list(const char *fmt, ...)
{
        va_list ap;

        va_start(ap, fmt);
        vsnprintf(g_json_dead, sizeof(g_json_dead), fmt, ap);
        va_end(ap);
        g_dead_json = g_json_dead;
}

static void clear_dead_list(void)
{
        g_dead_json = NULL;
}

static void set_recheck_list(const char *fmt, ...)
{
        va_list ap;

        va_start(ap, fmt);
        vsnprintf(g_json_recheck, sizeof(g_json_recheck), fmt, ap);
        va_end(ap);
        g_recheck_json = g_json_recheck;
}

static void clear_recheck_list(void)
{
        g_recheck_json = NULL;
}

static int argv_matches(const char *const argv[], const char *const expected[])
{
        int i;

        for (i = 0; argv[i] && expected[i]; i++)
                if (strcmp(argv[i], expected[i]) != 0)
                        return 0;
        return argv[i] == NULL && expected[i] == NULL;
}

static void set_script(const int *steps, int n)
{
        memcpy(g_list_script, steps, sizeof(int) * (size_t)n);
        g_list_script_len = n;
        g_list_calls = 0;
}

static struct shj_proc_result *fake_spawn(const char *const argv[], void *user)
{
        struct shj_proc_result *r = calloc(1, sizeof(*r));
        struct shj_sbuf b;

        (void)user;
        shj_sbuf_init(&b);
        for (int i = 0; argv[i]; i++) {
                if (i)
                        shj_sbuf_addch(&b, ' ');
                shj_sbuf_add(&b, argv[i]);
        }
        snprintf(g_recorded, sizeof(g_recorded), "%s", b.s);
        shj_sbuf_free(&b);

        r->spawn_errno = 0;
        if (argv[1] && strcmp(argv[1], "list") == 0) {
                const char *expected_live[] = { "mockqs", "list", "-a", "-j", NULL };
                const char *expected_dead[] = {
                        "mockqs", "list", "-a", "-j", "--show-dead", NULL
                };
                int phase = g_list_calls;
                int cls = g_list_calls < g_list_script_len
                              ? g_list_script[g_list_calls]
                              : 0;
                const char *response;

                /* Every discovery starts with a live query, then the optional
                 * --show-dead probe; a third live query is only the race check.
                 * Validate the complete vector before selecting canned output. */
                if ((phase == 1 && !argv_matches(argv, expected_dead)) ||
                    (phase != 1 && !argv_matches(argv, expected_live))) {
                        g_list_arg_errors++;
                        r->exit = 99;
                        r->out = shj_strdup("");
                        r->err = shj_strdup("unexpected qs list argv\n");
                        g_list_calls++;
                        return r;
                }
                g_list_calls++;
                if (phase == 1)
                        response = g_dead_json ? g_dead_json : g_list_json;
                else if (phase == 2 && g_recheck_json) {
                        response = g_recheck_json;
                        g_recheck_json = NULL;
                } else
                        response = g_list_json;
                r->truncated = g_list_truncated;
                if (cls >= 0) {
                        r->exit = cls;
                        r->out = shj_strdup(cls == 0 ? (response ? response : "") : "");
                        r->err = shj_strdup(cls == 0 ? "" : "qs rejected the command\n");
                        return r;
                }
                r->exit = cls;
                r->spawn_errno = cls == SHJ_PROC_EXIT_SPAWN
                                     ? ENOENT
                                     : (cls == SHJ_PROC_EXIT_TIMEOUT ? ETIMEDOUT : EIO);
                r->out = shj_strdup("");
                r->err = shj_strdup("");
                return r;
        }
        if (argv[1] && (strcmp(argv[1], "ipc") == 0 || strcmp(argv[1], "kill") == 0)) {
                int i;

                g_ipc_calls++;
                g_ipc_argc = 0;
                for (i = 0; i < 16 && argv[i]; i++) {
                        snprintf(g_ipc_argv[i], sizeof(g_ipc_argv[i]), "%s", argv[i]);
                        g_ipc_argc++;
                }
                r->exit = g_call_exit;
                r->out = shj_strdup(g_call_out);
                r->err = shj_strdup(g_call_err);
                return r;
        }
        if (argv[1] && strcmp(argv[1], "--version") == 0) {
                r->exit = 0;
                r->out = shj_strdup("Quickshell 0.3.2\n");
                r->err = shj_strdup("");
                return r;
        }
        r->exit = -1;
        r->spawn_errno = 127;
        r->out = shj_strdup("");
        r->err = shj_strdup("");
        return r;
}

/* Fixture: a fake store path, a second generation, and a mutable alias
 * symlink used for the retargeting regression. Every step is checked; a
 * failed setup aborts the suite cleanly instead of testing against
 * half-built fixtures. */
static int make_fixture(void)
{
        const char *tpl = "/tmp/shoji-inst-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));
        char *store;

        if (!dir)
                return -1;
        snprintf(g_tmp, sizeof(g_tmp), "%s", dir);
        free(dir);
        snprintf(g_expected, sizeof(g_expected), "%s/store/aaaaaaaa-shoji/shell.qml", g_tmp);

        if (mkdir(cat2(g_tmp, "/store"), 0755) != 0)
                return -1;
        store = shj_strcat(2, g_tmp, "/store");
        if (mkdir(cat2(store, "/aaaaaaaa-shoji"), 0755) != 0) {
                free(store);
                return -1;
        }
        free(store);
        if (write_file(g_expected, "import qs.Commons\nShellRoot {}\n") != 0)
                return -1;

        if (mkdir(cat2(g_tmp, "/gen-b"), 0755) != 0)
                return -1;
        if (write_file(cat2(g_tmp, "/gen-b/shell.qml"), "import qs.Commons\nShellRoot {}\n") != 0)
                return -1;
        if (symlink(cat2(g_tmp, "/store/aaaaaaaa-shoji"), cat2(g_tmp, "/alias")) != 0)
                return -1;
        return 0;
}

static void remove_fixture(void)
{
        /* Unlink the generated shell.qml files BEFORE removing their
         * containing directories, and check every step so a failed cleanup
         * is visible instead of silently leaving /tmp litter. */
        CHECK(unlink(g_expected) == 0, "fixture cleanup: shell.qml unlinked");
        CHECK(unlink(cat2(g_tmp, "/gen-b/shell.qml")) == 0,
              "fixture cleanup: gen-b shell.qml unlinked");
        CHECK(unlink(cat2(g_tmp, "/alias")) == 0, "fixture cleanup: alias unlinked");
        CHECK(rmdir(cat2(g_tmp, "/store/aaaaaaaa-shoji")) == 0,
              "fixture cleanup: store dir removed");
        CHECK(rmdir(cat2(g_tmp, "/store")) == 0, "fixture cleanup: store removed");
        CHECK(rmdir(cat2(g_tmp, "/gen-b")) == 0, "fixture cleanup: gen-b removed");
        CHECK(rmdir(g_tmp) == 0, "fixture cleanup: tmp removed");
}

static struct shoji_instance_list *discover_err(enum shoji_discover_err *err)
{
        g_list_calls = 0;
        return shoji_discover_instances(fake_spawn, NULL, "mockqs", err);
}

static struct shoji_instance_list *discover(void)
{
        enum shoji_discover_err err = SHOJI_DISCOVER_OK;
        struct shoji_instance_list *l = discover_err(&err);

        CHECK_INT_EQ(err, SHOJI_DISCOVER_OK, "discovery reports no error");
        return l;
}

/* Fresh context that only knows the mock spawn; the store fields are set
 * by each test (shell_qml must point at a static buffer; the ctx is
 * dropped by memset, never shoji_store_free'd). */
static void setup_bare_ctx(struct shoji_context *ctx, struct shoji_options *opts)
{
        memset(opts, 0, sizeof(*opts));
        memset(ctx, 0, sizeof(*ctx));
        ctx->qs_bin = "mockqs";
        ctx->spawn = fake_spawn;
        ctx->spawn_user = NULL;
}

/* Run a command function with stdout redirected into a file and return
 * the captured bytes (static buffer). Used to parse complete JSON output. */
static char g_capture[16384];

static char *capture_stdout(void (*fn)(void *), void *arg, const char *tmpfile)
{
        int saved, fd;
        FILE *f;
        size_t n;

        fflush(stdout);
        saved = dup(STDOUT_FILENO);
        fd = open(tmpfile, O_RDWR | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) {
                test_fail("capture: temp file opened");
                return NULL;
        }
        test_ok("capture: temp file opened");
        /* Flush the harness's own buffered output BEFORE redirecting, or it
         * would land inside the captured command output. */
        fflush(stdout);
        dup2(fd, STDOUT_FILENO);
        close(fd);
        fn(arg);
        fflush(stdout);
        dup2(saved, STDOUT_FILENO);
        close(saved);

        f = fopen(tmpfile, "r");
        CHECK(f != NULL, "capture: output readable");
        if (!f)
                return NULL;
        n = fread(g_capture, 1, sizeof(g_capture) - 1, f);
        fclose(f);
        g_capture[n] = '\0';
        unlink(tmpfile);
        return g_capture;
}

/* ---------------------------------------------------------------- */

/* the fixture store directory; a static buffer so run_status_json can pass
 * it as a borrowed --store override */
static char g_store_dir[512];

static void run_status_json(void *arg)
{
        struct shoji_context *ctx = arg;
        struct shoji_options opts;

        memset(&opts, 0, sizeof(opts));
        opts.json = 1;
        /* status re-resolves the store on its own; point it at the fixture
         * so the test stays independent of the host environment */
        opts.store_override = g_store_dir;
        shoji_cmd_status(ctx, &opts);
}

static void run_ilist_json(void *arg)
{
        struct shoji_context *ctx = arg;
        struct shoji_options opts;

        memset(&opts, 0, sizeof(opts));
        opts.json = 1;
        ctx->have_store = 1; /* status may have re-resolved (and cleared) it */
        shoji_cmd_instance_list(ctx, &opts);
}

static void run_icurrent_json(void *arg)
{
        struct shoji_context *ctx = arg;
        struct shoji_options opts;

        memset(&opts, 0, sizeof(opts));
        opts.json = 1;
        ctx->have_store = 1;
        shoji_cmd_instance_current(ctx, &opts);
}

static void run_iinspect_json(void *arg)
{
        struct shoji_context *ctx = arg;
        struct shoji_options opts;

        memset(&opts, 0, sizeof(opts));
        opts.json = 1;
        ctx->have_store = 1;
        shoji_cmd_instance_inspect(ctx, &opts);
}

static int check_json_field(const struct shj_json *obj, const char *key,
                             enum shj_json_type type, const char *name)
{
        const struct shj_json *v = obj ? shj_json_get(obj, key) : NULL;
        int valid = v && v->type == type;

        CHECK(valid, name);
        return valid;
}

void test_instances(void)
{
        struct shoji_instance_list *list;
        struct shoji_selection sel;
        struct shoji_context ctx;
        struct shoji_options opts;
        struct shoji_pipeline pl;
        enum shoji_discover_err err;
        char *out;
        /* script arrays are sized like the script buffer so set_script()'s
         * copy is provably in bounds */
        const int probe_ok[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
        const int probe_dead_reject[8] = { 0, 1 };
        const int probe_dead_timeout[8] = { 0, SHJ_PROC_EXIT_TIMEOUT };
        const int probe_dead_internal[8] = { 0, SHJ_PROC_EXIT_INTERNAL };
        const int probe_dead_spawn[8] = { 0, SHJ_PROC_EXIT_SPAWN };
        const int probe_timeout[8] = { SHJ_PROC_EXIT_TIMEOUT };
        const int probe_internal[8] = { SHJ_PROC_EXIT_INTERNAL };
        const int probe_spawn[8] = { SHJ_PROC_EXIT_SPAWN };
        const int probe_generic[8] = { 2 };

        test_section("instance discovery and selection");
        g_list_arg_errors = 0;
        if (make_fixture() != 0) {
                test_fail("fixture setup failed; skipping instance tests");
                return;
        }

        /* canned `qs list -a -j` output (live probe); the dead probe gets
         * the same rows until a test scripts otherwise */
        set_list("["
            "{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
            "\"config_path\":\"%s\","
            "\"launch_time\":\"2026-11-17T08:00:00\"},"
            "{\"id\":\"bbb222yyy\",\"pid\":5001,\"shell_id\":\"s2\","
            "\"config_path\":\"/some/other/shell.qml\","
            "\"launch_time\":\"2026-11-17T09:00:00\"},"
            "{\"id\":\"ccc333zzz\",\"pid\":-1,\"shell_id\":\"s3\","
            "\"config_path\":\"%s\","
            "\"launch_time\":\"2026-11-17T07:00:00\"}"
            "]", g_expected, g_expected);
        clear_dead_list();
        set_script(probe_ok, 1);

        list = discover();
        CHECK_INT_EQ(list->count, 3, "three instances parsed");
        CHECK_INT_EQ(shoji_live_count(list), 2, "two live instances");
        CHECK_STR_EQ(list->items[0].id, "aaa111xxx", "id parsed");
        CHECK_INT_EQ(list->items[0].pid, 4242, "pid parsed");
        CHECK_STR_EQ(list->items[0].launch_time, "2026-11-17T08:00:00", "launch time parsed");
        CHECK_INT_EQ(list->items[0].id_valid, 1, "valid id accepted");
        CHECK_INT_EQ(list->items[2].dead, 1, "dead instance flagged");

        /* matching works through a canonical recorded path: the record
         * itself is the launch-time identity (string equality with the
         * expected canonical path) */
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel), SHOJI_SELECT_OK,
                     "expected config matches");
        CHECK_INT_EQ(sel.match_count, 1, "one live match");
        CHECK_INT_EQ(sel.dead_match_count, 1, "one dead match");
        CHECK_INT_EQ(sel.uncertain_matches, 0, "no uncertain rows");
        CHECK_STR_EQ(sel.selected->id, "aaa111xxx", "correct instance selected");
        shoji_selection_clear(&sel);
        shoji_instance_list_free(list);

        /* real quickshell prints a bare log line (or nothing at all) instead
         * of a JSON array when no instance exists */
        set_list("No running instances.");
        list = discover();
        CHECK_INT_EQ(list->count, 0, "bare empty-list notice accepted");
        shoji_instance_list_free(list);

        set_list("");
        list = discover();
        CHECK_INT_EQ(list->count, 0, "empty list output accepted");
        shoji_instance_list_free(list);

        set_list("No running instances.\npartial output");
        list = discover_err(&err);
        CHECK(!list && err == SHOJI_DISCOVER_BADJSON,
              "empty-list notice with trailing output is rejected");

        set_list("  No running instances.\n  ");
        list = discover();
        CHECK_INT_EQ(list->count, 0, "complete empty-list notice permits surrounding whitespace");
        shoji_instance_list_free(list);

        /* Truncated stdout is never mistaken for a complete empty listing;
         * stderr truncation alone does not invalidate the JSON payload. */
        set_list("[]");
        set_script(probe_ok, 1);
        g_list_truncated = SHOJI_TRUNC_OUT;
        list = discover_err(&err);
        CHECK(!list && err == SHOJI_DISCOVER_BADJSON,
              "truncated authoritative stdout is rejected");
        g_list_truncated = SHOJI_TRUNC_ERR;
        set_script(probe_ok, 1);
        list = discover_err(&err);
        CHECK(list && err == SHOJI_DISCOVER_OK,
              "stderr-only truncation does not invalidate listing");
        shoji_instance_list_free(list);
        g_list_truncated = 0;

        /* no match */
        g_list_json = "[{\"id\":\"bbb222yyy\",\"pid\":7,\"shell_id\":\"s2\","
                      "\"config_path\":\"/some/other/shell.qml\","
                      "\"launch_time\":\"2026-11-17T09:00:00\"}]";
        list = discover();
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel), SHOJI_SELECT_NONE,
                     "foreign config does not match");
        CHECK_INT_EQ(sel.match_count, 0, "no matches");
        shoji_selection_clear(&sel);
        shoji_instance_list_free(list);

        set_list("[{\"id\":\"hugepid\",\"pid\":1e30,\"shell_id\":\"s\","
                 "\"config_path\":\"%s\",\"launch_time\":\"t\"}]", g_expected);
        set_script(probe_ok, 1);
        list = discover();
        CHECK_INT_EQ(list->items[0].pid, -1, "out-of-range PID is rejected before conversion");
        CHECK_INT_EQ(list->items[0].dead, 1, "unusable PID cannot become a live IPC candidate");
        shoji_instance_list_free(list);

        /* ambiguous: two live instances recording the identical (existing
         * only as a string) config path; the identical recorded string is
         * the only launch-time evidence available */
        g_list_json = "["
            "{\"id\":\"abcd111\",\"pid\":11,\"shell_id\":\"s\","
            "\"config_path\":\"/some/other/shell.qml\",\"launch_time\":\"t\"},"
            "{\"id\":\"abcd222\",\"pid\":12,\"shell_id\":\"s\","
            "\"config_path\":\"/some/other/shell.qml\",\"launch_time\":\"t2\"}"
            "]";
        list = discover();
        CHECK_INT_EQ(shoji_select_instance(list, "/some/other/shell.qml", NULL, &sel),
                     SHOJI_SELECT_AMBIGUOUS, "two live matches are ambiguous");
        CHECK_INT_EQ(sel.match_count, 2, "both matches reported");
        shoji_selection_clear(&sel);

        /* prefix override resolves one instance */
        CHECK_INT_EQ(shoji_select_instance(list, "/some/other/shell.qml", "abcd1", &sel),
                     SHOJI_SELECT_OK, "unique prefix override selects");
        CHECK_STR_EQ(sel.selected->id, "abcd111", "prefix picked the right instance");
        shoji_selection_clear(&sel);

        list->items[1].dead = 1;
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, "abcd", &sel),
                     SHOJI_SELECT_OK,
                     "dead prefix row does not make a single live prefix ambiguous");
        CHECK_STR_EQ(sel.selected->id, "abcd111", "live prefix wins over dead row");
        shoji_selection_clear(&sel);
        list->items[1].dead = 0;

        /* Empty override must not fall through to auto-selection when a
         * real expected-config candidate exists. */
        shoji_instance_list_free(list);
        set_list("[{\"id\":\"expected77\",\"pid\":77,\"shell_id\":\"s\","
                 "\"config_path\":\"%s\",\"launch_time\":\"t\"}]", g_expected);
        clear_dead_list();
        set_script(probe_ok, 1);
        list = discover();
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel),
                     SHOJI_SELECT_OK, "omitted instance-id auto-selects expected match");
        shoji_selection_clear(&sel);
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, "", &sel),
                     SHOJI_SELECT_NONE, "empty explicit instance-id is refused");
        CHECK(sel.selected == NULL, "empty explicit instance-id selects nothing");
        shoji_selection_clear(&sel);
        shoji_instance_list_free(list);

        set_list("["
            "{\"id\":\"abcd111\",\"pid\":11,\"shell_id\":\"s\","
            "\"config_path\":\"/some/other/shell.qml\",\"launch_time\":\"t\"},"
            "{\"id\":\"abcd222\",\"pid\":12,\"shell_id\":\"s\","
            "\"config_path\":\"/some/other/shell.qml\",\"launch_time\":\"t2\"}] ");
        set_script(probe_ok, 1);
        list = discover();

        /* ambiguous prefix override: both matches must be published so the
         * caller can list them instead of reading uninitialized entries */
        CHECK_INT_EQ(shoji_select_instance(list, "/some/other/shell.qml", "abcd", &sel),
                     SHOJI_SELECT_AMBIGUOUS, "ambiguous prefix override refused");
        CHECK_INT_EQ(sel.match_count, 2, "ambiguous prefix lists both matches");
        CHECK_STR_EQ(sel.matches[0]->id, "abcd111", "ambiguous match 1 published");
        CHECK_STR_EQ(sel.matches[1]->id, "abcd222", "ambiguous match 2 published");
        shoji_selection_clear(&sel);

        /* unknown prefix override */
        CHECK_INT_EQ(shoji_select_instance(list, "/some/other/shell.qml", "zzz", &sel),
                     SHOJI_SELECT_NONE, "unknown prefix selects nothing");
        shoji_selection_clear(&sel);
        shoji_instance_list_free(list);

        /* dead-only match (pid -1 in the live listing) */
        g_list_json = "[{\"id\":\"ccc333zzz\",\"pid\":-1,\"shell_id\":\"s3\","
                      "\"config_path\":\"/some/other/shell.qml\","
                      "\"launch_time\":\"2026-11-17T07:00:00\"}]";
        list = discover();
        CHECK_INT_EQ(shoji_select_instance(list, "/some/other/shell.qml", NULL, &sel),
                     SHOJI_SELECT_NONE, "dead-only match refuses selection");
        CHECK_INT_EQ(sel.dead_match_count, 1, "dead match reported for diagnostics");
        shoji_selection_clear(&sel);
        shoji_instance_list_free(list);

        /* ------------------------------------------------------------------ */
        /* discovery failure classes: every failure keeps its class, is        */
        /* never retried, and maps onto the exit-code contract.                */
        /* ------------------------------------------------------------------ */

        /* first probe timeout: stays a timeout, exactly one invocation */
        set_script(probe_timeout, 1);
        list = discover_err(&err);
        CHECK(!list, "timeout: discovery fails");
        CHECK_INT_EQ(err, SHOJI_DISCOVER_TIMEOUT, "timeout: class preserved");
        CHECK_INT_EQ(g_list_calls, 1, "timeout: no compatibility retry");
        setup_bare_ctx(&ctx, &opts);
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        set_script(probe_timeout, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_FAILED, "timeout maps to exit 1");
        memset(&ctx, 0, sizeof(ctx));

        /* first probe internal failure: stays internal, one invocation */
        set_script(probe_internal, 1);
        list = discover_err(&err);
        CHECK(!list, "internal: discovery fails");
        CHECK_INT_EQ(err, SHOJI_DISCOVER_INTERNAL, "internal: class preserved");
        CHECK_INT_EQ(g_list_calls, 1, "internal: no compatibility retry");
        setup_bare_ctx(&ctx, &opts);
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        set_script(probe_internal, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_INTERNAL, "internal failure maps to exit 70");
        memset(&ctx, 0, sizeof(ctx));

        /* first probe missing executable: stays missing-executable */
        set_script(probe_spawn, 1);
        list = discover_err(&err);
        CHECK(!list, "missing executable: discovery fails");
        CHECK_INT_EQ(err, SHOJI_DISCOVER_NOEXEC, "missing executable: class preserved");
        CHECK_INT_EQ(g_list_calls, 1, "missing executable: no compatibility retry");
        setup_bare_ctx(&ctx, &opts);
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        set_script(probe_spawn, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOQS, "missing executable maps to exit 69");
        memset(&ctx, 0, sizeof(ctx));

        /* a generic quickshell failure must not trigger any fallback and
         * keeps the documented generic failure behavior */
        set_script(probe_generic, 1);
        list = discover_err(&err);
        CHECK(!list, "generic rejection: discovery fails");
        CHECK_INT_EQ(err, SHOJI_DISCOVER_FAILED, "generic rejection: class preserved");
        CHECK_INT_EQ(g_list_calls, 1, "generic rejection: no retry");

        /* unsupported --show-dead rejection: the compatibility probe keeps
         * discovery alive with exactly two invocations */
        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"}]", g_expected);
        clear_dead_list();
        set_script(probe_dead_reject, 2);
        list = discover_err(&err);
        CHECK_INT_EQ(err, SHOJI_DISCOVER_OK, "rejection: discovery succeeds");
        CHECK_INT_EQ(g_list_calls, 2, "rejection: compatibility probe ran");
        CHECK(list && list->count == 1, "rejection: live listing parsed");
        shoji_instance_list_free(list);

        /* the dead probe failing in every other way loses only the
         * dead-instance diagnostics, never the live result */
        set_script(probe_dead_timeout, 2);
        list = discover_err(&err);
        CHECK_INT_EQ(err, SHOJI_DISCOVER_OK, "dead probe timeout contained");
        CHECK_INT_EQ(g_list_calls, 2, "dead probe timeout: two invocations");
        CHECK(list && list->count == 1, "dead probe timeout: live rows intact");
        shoji_instance_list_free(list);

        set_script(probe_dead_internal, 2);
        list = discover_err(&err);
        CHECK_INT_EQ(err, SHOJI_DISCOVER_OK, "dead probe internal failure contained");
        shoji_instance_list_free(list);

        set_script(probe_dead_spawn, 2);
        list = discover_err(&err);
        CHECK_INT_EQ(err, SHOJI_DISCOVER_OK, "dead probe spawn failure contained");
        shoji_instance_list_free(list);

        /* A row that appears only in --show-dead may have started after the
         * first live snapshot. A fresh live query must confirm it before it
         * becomes a dispatch candidate (or a dead diagnostic). */
        set_list("No running instances.");
        set_dead_list("[{\"id\":\"newlive77\",\"pid\":77,\"shell_id\":\"s7\","
                      "\"config_path\":\"%s\",\"launch_time\":\"t\"}]", g_expected);
        set_recheck_list("[{\"id\":\"newlive77\",\"pid\":77,\"shell_id\":\"s7\","
                         "\"config_path\":\"%s\",\"launch_time\":\"t\"}]", g_expected);
        set_script(probe_ok, 3);
        list = discover();
        CHECK_INT_EQ(g_list_calls, 3, "new second-probe row triggers fresh live verification");
        CHECK_INT_EQ(list->count, 1, "fresh live row retained exactly once");
        CHECK_INT_EQ(list->items[0].dead, 0, "freshly confirmed row is live");
        CHECK_INT_EQ(shoji_live_count(list), 1, "freshly confirmed row counted as running");
        shoji_instance_list_free(list);
        clear_dead_list();
        clear_recheck_list();

        /* A successful full live recheck supersedes the earlier snapshot.
         * If A stops and B starts between probes, A must become diagnostic
         * only, even when B belongs to another configuration. */
        set_list("[{\"id\":\"oldmatchA\",\"pid\":11,\"shell_id\":\"sA\","
                 "\"config_path\":\"%s\",\"launch_time\":\"tA\"}]", g_expected);
        set_dead_list("["
                      "{\"id\":\"oldmatchA\",\"pid\":11,\"shell_id\":\"sA\","
                      "\"config_path\":\"%s\",\"launch_time\":\"tA\"},"
                      "{\"id\":\"newforeignB\",\"pid\":22,\"shell_id\":\"sB\","
                      "\"config_path\":\"/other/shell.qml\",\"launch_time\":\"tB\"}]", g_expected);
        set_recheck_list("[{\"id\":\"newforeignB\",\"pid\":22,\"shell_id\":\"sB\","
                         "\"config_path\":\"/other/shell.qml\",\"launch_time\":\"tB\"}]");
        set_script(probe_ok, 3);
        list = discover();
        CHECK_INT_EQ(shoji_live_count(list), 1,
                     "fresh live snapshot is the complete selectable set");
        CHECK_INT_EQ(list->count, 2, "stopped row remains only for diagnostics");
        CHECK_INT_EQ(list->items[0].dead, 1, "row absent from recheck becomes dead");
        CHECK_INT_EQ(list->items[1].dead, 0, "new live row remains selectable");
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel),
                     SHOJI_SELECT_NONE,
                     "stale earlier match cannot be selected after live recheck");
        shoji_selection_clear(&sel);
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, "newforeign", &sel),
                     SHOJI_SELECT_OK,
                     "explicit prefix can select the fresh foreign live row");
        CHECK_STR_EQ(sel.selected->id, "newforeignB",
                     "fresh explicit selection identifies the new live instance");
        shoji_selection_clear(&sel);
        shoji_instance_list_free(list);
        clear_dead_list();
        clear_recheck_list();

        /* ------------------------------------------------------------------ */
        /* dead-instance classification: the dead probe's rows carry stale     */
        /* launch-time pids that can be positive; only their absence from the  */
        /* live listing marks them dead.                                       */
        /* ------------------------------------------------------------------ */

        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"}]", g_expected);
        set_dead_list("["
            "{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
            "\"config_path\":\"%s\",\"launch_time\":\"2026-11-17T08:00:00\"},"
            "{\"id\":\"stale999zz\",\"pid\":4711,\"shell_id\":\"s9\","
            "\"config_path\":\"%s\",\"launch_time\":\"2026-11-17T06:00:00\"}"
            "]", g_expected, g_expected);
        set_script(probe_ok, 2);
        list = discover();
        CHECK_INT_EQ(list->count, 2, "stale: dead probe adds its rows");
        CHECK_INT_EQ(list->items[1].dead, 1, "stale: duplicate live row dropped");
        shoji_instance_list_free(list);

        /* A stale instance with a POSITIVE JSON pid, absent from the live
         * listing, must be dead and never selected or dispatched. */
        set_list("No running instances.");
        set_dead_list("[{\"id\":\"stale999zz\",\"pid\":4711,\"shell_id\":\"s9\","
                      "\"config_path\":\"%s\","
                      "\"launch_time\":\"2026-11-17T06:00:00\"}]", g_expected);
        set_script(probe_ok, 2);
        list = discover();
        CHECK_INT_EQ(list->count, 1, "stale-only: dead probe row parsed");
        CHECK_INT_EQ(list->items[0].dead, 1, "stale row marked dead despite positive pid");
        CHECK_INT_EQ(list->items[0].pid, 4711, "stale row keeps its pid for diagnostics");
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel),
                     SHOJI_SELECT_NONE, "stale instance is not selectable");
        CHECK_INT_EQ(sel.dead_match_count, 1, "stale instance reported for diagnostics");
        CHECK_INT_EQ(sel.match_count, 0, "stale instance is not a candidate");
        shoji_selection_clear(&sel);
        setup_bare_ctx(&ctx, &opts);
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        set_script(probe_ok, 2);
        g_recorded[0] = '\0';
        g_ipc_calls = 0;
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOINSTANCE, "stale-only: pipeline refuses");
        CHECK_INT_EQ(g_ipc_calls, 0, "stale-only: IPC call counter remains zero");
        shoji_pipeline_release(&pl);
        memset(&ctx, 0, sizeof(ctx));
        shoji_instance_list_free(list);
        clear_dead_list();

        /* ------------------------------------------------------------------ */
        /* instance identity: absent/empty ids never reach IPC.                */
        /* ------------------------------------------------------------------ */

        set_list("[{\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\",\"launch_time\":\"2026-11-17T08:00:00\"}]",
                 g_expected);
        set_script(probe_ok, 1);
        list = discover();
        CHECK_INT_EQ(list->count, 1, "missing id: row parsed");
        CHECK_INT_EQ(list->items[0].id_valid, 0, "missing id rejected");
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel), SHOJI_SELECT_NONE,
                     "missing id: nothing selectable");
        CHECK_INT_EQ(sel.invalid_id_matches, 1, "missing id reported");
        CHECK_INT_EQ(sel.match_count, 0, "missing id: no candidate");
        shoji_selection_clear(&sel);
        setup_bare_ctx(&ctx, &opts);
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        set_script(probe_ok, 1);
        g_recorded[0] = '\0';
        g_ipc_calls = 0;
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOINSTANCE, "missing id: pipeline refuses");
        CHECK_INT_EQ(g_ipc_calls, 0, "missing id: IPC call counter remains zero");
        shoji_pipeline_release(&pl);
        memset(&ctx, 0, sizeof(ctx));
        shoji_instance_list_free(list);

        set_list("[{\"id\":\"\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\",\"launch_time\":\"2026-11-17T08:00:00\"}]",
                 g_expected);
        set_script(probe_ok, 1);
        list = discover();
        CHECK_INT_EQ(list->items[0].id_valid, 0, "empty id rejected");
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel), SHOJI_SELECT_NONE,
                     "empty id: nothing selectable");
        CHECK_INT_EQ(sel.invalid_id_matches, 1, "empty id reported");
        shoji_selection_clear(&sel);
        setup_bare_ctx(&ctx, &opts);
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        set_script(probe_ok, 1);
        g_recorded[0] = '\0';
        g_ipc_calls = 0;
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOINSTANCE, "empty id: pipeline refuses");
        CHECK_INT_EQ(g_ipc_calls, 0, "empty id: IPC call counter remains zero");
        shoji_pipeline_release(&pl);
        memset(&ctx, 0, sizeof(ctx));
        shoji_instance_list_free(list);

        set_list("[{\"id\":\"  \",\"pid\":1,\"shell_id\":\"s\","
                 "\"config_path\":\"%s\",\"launch_time\":\"t\"}]",
                 g_expected);
        set_script(probe_ok, 1);
        list = discover();
        CHECK_INT_EQ(list->items[0].id_valid, 0, "whitespace id rejected");
        shoji_instance_list_free(list);

        /* ------------------------------------------------------------------ */
        /* mutable symlink identity must remain uncertain                     */
        /* ------------------------------------------------------------------ */

        {
                const char *alias = cat2(g_tmp, "/alias");
                const char *alias_qml = cat2(g_tmp, "/alias/shell.qml");
                char *real_b = shj_realpath_safe(cat2(g_tmp, "/gen-b/shell.qml"));

                CHECK(real_b != NULL, "alias: generation B resolves");
                CHECK(unlink(alias) == 0, "alias: fixture symlink removed");
                CHECK(symlink(cat2(g_tmp, "/gen-b"), alias) == 0,
                      "alias: retargeted to generation B");

                set_list("[{\"id\":\"ro1aa\",\"pid\":900,\"shell_id\":\"g\","
                         "\"config_path\":\"%s\",\"launch_time\":\"2026-11-17T08:00:00\"}]",
                         alias_qml);
                clear_dead_list();
                set_script(probe_ok, 2);
                list = discover();

                CHECK_INT_EQ(shoji_select_instance(list, real_b, NULL, &sel),
                             SHOJI_SELECT_NONE,
                             "alias: resolved target is not treated as certain identity");
                CHECK_INT_EQ(sel.match_count, 0, "alias: uncertain row is not a match");
                CHECK_INT_EQ(sel.uncertain_matches, 1,
                             "alias: uncertainty is reported without timestamp inference");
                shoji_selection_clear(&sel);
                list->items[0].dead = 1;
                CHECK_INT_EQ(shoji_select_instance(list, real_b, NULL, &sel),
                             SHOJI_SELECT_NONE,
                             "dead alias row does not create a running-instance result");
                CHECK_INT_EQ(sel.uncertain_matches, 0,
                             "dead alias row is excluded from uncertain running count");
                shoji_selection_clear(&sel);
                shoji_instance_list_free(list);
                free(real_b);
        }
        clear_dead_list();

        /* ------------------------------------------------------------------ */
        /* dispatch pipeline + argv vector correctness                         */
        /* ------------------------------------------------------------------ */

        memset(&opts, 0, sizeof(opts));
        memset(&ctx, 0, sizeof(ctx));
        ctx.qs_bin = "mockqs";
        ctx.spawn = fake_spawn;
        ctx.spawn_user = NULL;
        ctx.have_store = 1;
        ctx.store.shell_qml = g_expected;
        ctx.store.dir = shj_strdup(g_tmp);
        ctx.store.source_name = "explicit";
        ctx.store.source_detail = NULL;

        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"}]", g_expected);
        set_script(probe_ok, 1);

        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_OK, "pipeline selects instance");
        CHECK(pl.sel.selected && strcmp(pl.sel.selected->id, "aaa111xxx") == 0,
              "pipeline selected expected instance");

        g_call_exit = 0;
        g_call_out = "";
        g_call_err = "";
        {
                char *args[1];

                args[0] = (char *)"calendar item";
                g_ipc_calls = 0;
                CHECK_INT_EQ(shoji_dispatch_call(&ctx, &pl, "island", "tab", args, 1),
                             SHOJI_EXIT_OK, "dispatch succeeds on qs exit 0");
        }
        CHECK_STR_EQ(g_recorded,
                     "mockqs ipc -i aaa111xxx call island tab calendar item",
                     "dispatch diagnostic rendering retains the argv content");
        CHECK_INT_EQ(g_ipc_calls, 1, "dispatch invokes IPC exactly once");
        CHECK_INT_EQ(g_ipc_argc, 8, "dispatch passes the expected argument count");
        CHECK_STR_EQ(g_ipc_argv[0], "mockqs", "IPC argv[0] is quickshell");
        CHECK_STR_EQ(g_ipc_argv[1], "ipc", "IPC argv[1] is command");
        CHECK_STR_EQ(g_ipc_argv[2], "-i", "IPC argv[2] is selector flag");
        CHECK_STR_EQ(g_ipc_argv[3], "aaa111xxx", "IPC selector is one argument");
        CHECK_STR_EQ(g_ipc_argv[4], "call", "IPC argv[4] is call subcommand");
        CHECK_STR_EQ(g_ipc_argv[5], "island", "IPC target remains one argument");
        CHECK_STR_EQ(g_ipc_argv[6], "tab", "IPC function remains one argument");
        CHECK_STR_EQ(g_ipc_argv[7], "calendar item",
                     "IPC argument containing spaces remains one argument");
        shoji_pipeline_release(&pl);

        /* qs reports an unknown target -> mapped to exit 65 */
        set_script(probe_ok, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        g_call_exit = 255;
        g_call_err = "Target not found.\n";
        CHECK_INT_EQ(shoji_dispatch_call(&ctx, &pl, "bogus", "fn", NULL, 0),
                     SHOJI_EXIT_BADIPC, "target-not-found maps to 65");
        shoji_pipeline_release(&pl);

        /* generic qs failure -> exit 1 */
        set_script(probe_ok, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        g_call_exit = 255;
        g_call_err = "something else failed\n";
        CHECK_INT_EQ(shoji_dispatch_call(&ctx, &pl, "island", "toggle", NULL, 0),
                     SHOJI_EXIT_FAILED, "generic qs failure maps to 1");
        shoji_pipeline_release(&pl);

        /* no matching instance -> 67, no dispatch happens */
        set_list("[{\"id\":\"bbb222yyy\",\"pid\":7,\"shell_id\":\"s2\","
                 "\"config_path\":\"/some/other/shell.qml\","
                 "\"launch_time\":\"2026-11-17T09:00:00\"}]");
        g_recorded[0] = '\0';
        g_ipc_calls = 0;
        set_script(probe_ok, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOINSTANCE,
                     "no match refuses to dispatch");
        CHECK_INT_EQ(g_ipc_calls, 0, "no matching instance: IPC call counter remains zero");
        shoji_pipeline_release(&pl);

        /* ------------------------------------------------------------------ */
        /* kill: argv vector, newest selection, --all, identity refusals       */
        /* ------------------------------------------------------------------ */

        free(ctx.store.dir); /* owned field; shell_qml points at a static buffer */
        memset(&opts, 0, sizeof(opts));
        opts.store_override = shj_strdup(g_expected);
        memset(&ctx, 0, sizeof(ctx));
        ctx.qs_bin = "mockqs";
        ctx.spawn = fake_spawn;
        ctx.spawn_user = NULL;

        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"}]", g_expected);
        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        g_call_exit = 0;
        g_call_out = "Killed aaa111xxx\n";
        g_call_err = "";
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_OK,
                     "kill succeeds on qs exit 0");
        CHECK_STR_EQ(g_recorded, "mockqs kill -i aaa111xxx",
                     "kill argv vector exact");
        CHECK_INT_EQ(g_ipc_calls, 1, "kill dispatches exactly once");
        shoji_store_free(&ctx.store);

        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"},"
                 "{\"id\":\"zzz999xxx\",\"pid\":6001,\"shell_id\":\"s9\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T10:00:00\"}]",
                 g_expected, g_expected);
        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        g_call_out = "";
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_OK,
                     "bare kill with several matches kills the newest");
        CHECK_STR_EQ(g_recorded, "mockqs kill -i zzz999xxx",
                     "bare kill selects the highest pid");
        CHECK_INT_EQ(g_ipc_calls, 1, "bare kill dispatches once");
        shoji_store_free(&ctx.store);

        opts.kill_all = 1;
        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_OK,
                     "kill --all succeeds when every kill succeeds");
        CHECK_INT_EQ(g_ipc_calls, 2, "kill --all dispatches once per match");
        CHECK_STR_EQ(g_recorded, "mockqs kill -i zzz999xxx",
                     "kill --all covers the full target set");
        shoji_store_free(&ctx.store);

        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        g_call_exit = 255;
        g_call_err = "";
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_FAILED,
                     "kill --all fails when a kill fails");
        CHECK_INT_EQ(g_ipc_calls, 2, "kill --all attempts every match despite failures");
        g_call_exit = 0;
        shoji_store_free(&ctx.store);
        opts.kill_all = 0;

        opts.instance_id = shj_strdup("qqq");
        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"},"
                 "{\"id\":\"qqq222yyy\",\"pid\":8,\"shell_id\":\"s2\","
                 "\"config_path\":\"/some/other/shell.qml\","
                 "\"launch_time\":\"2026-11-17T09:00:00\"}]", g_expected);
        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_NOINSTANCE,
                     "explicit foreign selection refuses to kill");
        CHECK_INT_EQ(g_ipc_calls, 0, "foreign refusal dispatches nothing");
        free(opts.instance_id);
        opts.instance_id = NULL;
        shoji_store_free(&ctx.store);

        opts.instance_id = shj_strdup("aaa111");
        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"},"
                 "{\"id\":\"aaa111yyy\",\"pid\":6002,\"shell_id\":\"s3\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T11:00:00\"}]",
                 g_expected, g_expected);
        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_AMBIGUOUS,
                     "ambiguous id prefix refuses to kill");
        CHECK_INT_EQ(g_ipc_calls, 0, "ambiguous prefix dispatches nothing");
        free(opts.instance_id);
        opts.instance_id = NULL;
        shoji_store_free(&ctx.store);

        opts.instance_id = shj_strdup("unc");
        set_list("[{\"id\":\"unc111xxx\",\"pid\":9,\"shell_id\":\"s4\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T07:00:00\"}]",
                 cat2(g_tmp, "/alias/shell.qml"));
        set_script(probe_ok, 1);
        g_ipc_calls = 0;
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_NOINSTANCE,
                     "uncertain generation refuses to kill");
        CHECK_INT_EQ(g_ipc_calls, 0, "uncertain refusal dispatches nothing");
        free(opts.instance_id);
        opts.instance_id = NULL;
        shoji_store_free(&ctx.store);

        free(opts.store_override);
        opts.store_override = shj_strcat(2, g_tmp, "/does-not-exist");
        CHECK_INT_EQ(shoji_cmd_kill(&ctx, &opts), SHOJI_EXIT_NOSTORE,
                     "kill without a resolvable store refuses");
        free(opts.store_override);
        opts.store_override = NULL;
        shoji_store_free(&ctx.store);

        /* ------------------------------------------------------------------ */
        /* unresolved store, host-independent: a nonexistent --store override  */
        /* decides, never the host environment.                                */
        /* ------------------------------------------------------------------ */

        free(ctx.store.dir); /* owned field; shell_qml points at a static buffer */
        memset(&ctx, 0, sizeof(ctx));
        ctx.qs_bin = "mockqs";
        ctx.spawn = fake_spawn;
        ctx.spawn_user = NULL;
        ctx.have_store = 0;
        opts.store_override = shj_strcat(2, g_tmp, "/does-not-exist");
        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"}]", g_expected);
        set_script(probe_ok, 1);
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOSTORE,
                     "unresolved store refuses dispatch");
        free(opts.store_override);
        opts.store_override = NULL;
        shoji_pipeline_release(&pl);
        shoji_store_free(&ctx.store);

        CHECK_INT_EQ(g_list_arg_errors, 0,
                     "all qs list probes use the exact live/dead argv vectors");

        /* ------------------------------------------------------------------ */
        /* JSON output: every --json command must emit exactly one parseable   */
        /* JSON value with the expected fields.                                */
        /* ------------------------------------------------------------------ */

        memset(&opts, 0, sizeof(opts));
        memset(&ctx, 0, sizeof(ctx));
        ctx.qs_bin = "mockqs";
        ctx.spawn = fake_spawn;
        ctx.spawn_user = NULL;
        ctx.have_store = 1;
        snprintf(g_store_dir, sizeof(g_store_dir), "%s/store/aaaaaaaa-shoji", g_tmp);
        ctx.store.shell_qml = g_expected;
        ctx.store.dir = shj_strdup(g_store_dir);
        ctx.store.source_name = "explicit";
        ctx.store.source_detail = NULL;
        set_list("[{\"id\":\"aaa111xxx\",\"pid\":4242,\"shell_id\":\"s1\","
                 "\"config_path\":\"%s\","
                 "\"launch_time\":\"2026-11-17T08:00:00\"}]", g_expected);
        set_script(probe_ok, 1);
        g_call_exit = 0;

        /* status re-resolves the store and REPLACES ctx.store wholesale:
         * drop the injected dir first so it is never lost. */
        free(ctx.store.dir);
        memset(&ctx.store, 0, sizeof(ctx.store));
        g_call_out = "target island\n";
        g_call_err = "";

        out = capture_stdout(run_status_json, &ctx, cat2(g_tmp, "/cap-status.json"));
        if (out) {
                size_t errpos = 0;
                struct shj_json *v = shj_json_parse(out, &errpos);

                CHECK(v && v->type == SHOJI_JSON_OBJECT, "status --json: one complete object");
                if (v) {
                        const struct shj_json *verdict = shj_json_get(v, "verdict");
                        const struct shj_json *insts = shj_json_get(v, "instances");

                        if (check_json_field(v, "verdict", SHOJI_JSON_STRING,
                                             "status --json: verdict field"))
                                CHECK(strcmp(verdict->string, "match") == 0,
                                      "status --json: verdict match");
                        CHECK(insts && insts->type == SHOJI_JSON_ARRAY && insts->items &&
                              insts->items->next == NULL,
                              "status --json: one instance");
                        if (insts && insts->items) {
                                check_json_field(insts->items, "matches_expected",
                                                 SHOJI_JSON_BOOL,
                                                 "status --json: matches_expected bool");
                                check_json_field(insts->items, "id", SHOJI_JSON_STRING,
                                                 "status --json: instance id");
                        }
                        shj_json_free(v);
                }
        }

        out = capture_stdout(run_ilist_json, &ctx, cat2(g_tmp, "/cap-ilist.json"));
        if (out) {
                size_t errpos = 0;
                struct shj_json *v = shj_json_parse(out, &errpos);

                CHECK(v && v->type == SHOJI_JSON_ARRAY,
                      "instance list --json: one complete array");
                if (v && v->type == SHOJI_JSON_ARRAY) {
                        CHECK(v->items && v->items->next == NULL,
                              "instance list --json: one element");
                        check_json_field(v->items, "id", SHOJI_JSON_STRING,
                                         "instance list --json: id field");
                        shj_json_free(v);
                }
        }

        out = capture_stdout(run_icurrent_json, &ctx, cat2(g_tmp, "/cap-icur.json"));
        if (out) {
                size_t errpos = 0;
                struct shj_json *v = shj_json_parse(out, &errpos);

                CHECK(v && v->type == SHOJI_JSON_OBJECT,
                      "instance current --json: one complete object");
                if (v) {
                        const struct shj_json *id = shj_json_get(v, "id");

                        if (check_json_field(v, "id", SHOJI_JSON_STRING,
                                             "instance current --json: id field"))
                                CHECK(strcmp(id->string, "aaa111xxx") == 0,
                                      "instance current --json: selected id");
                        check_json_field(v, "matches_expected", SHOJI_JSON_BOOL,
                                         "instance current --json: match bool");
                        shj_json_free(v);
                }
        }

        out = capture_stdout(run_iinspect_json, &ctx, cat2(g_tmp, "/cap-iinsp.json"));
        if (out) {
                size_t errpos = 0;
                struct shj_json *v = shj_json_parse(out, &errpos);
                const struct shj_json *ipc;

                CHECK(v && v->type == SHOJI_JSON_OBJECT,
                      "instance inspect --json: one complete object");
                if (v) {
                        ipc = shj_json_get(v, "ipc_accessible");
                        CHECK(ipc && ipc->type == SHOJI_JSON_BOOL && ipc->boolean == 1,
                              "instance inspect --json: ipc_accessible is true");
                        shj_json_free(v);
                }
        }

        /* unsuccessful IPC probe still produces exactly one valid object
         * with ipc_accessible = false */
        g_call_exit = 255;
        g_call_err = "Target not found.\n";
        out = capture_stdout(run_iinspect_json, &ctx, cat2(g_tmp, "/cap-iinsp2.json"));
        if (out) {
                size_t errpos = 0;
                struct shj_json *v = shj_json_parse(out, &errpos);
                const struct shj_json *ipc;

                CHECK(v && v->type == SHOJI_JSON_OBJECT,
                      "instance inspect --json (probe failed): one complete object");
                if (v) {
                        ipc = shj_json_get(v, "ipc_accessible");
                        CHECK(ipc && ipc->type == SHOJI_JSON_BOOL && ipc->boolean == 0,
                              "instance inspect --json (probe failed): ipc_accessible false");
                        shj_json_free(v);
                }
        }

        /* status re-resolved the store, so every store field is
         * resolver-owned here; free them through the owner */
        shoji_store_free(&ctx.store);
        memset(&ctx, 0, sizeof(ctx));

        remove_fixture();
}
