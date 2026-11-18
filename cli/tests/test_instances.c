/* shoji-cli tests -- instance discovery, selection policy and dispatch argv.
 *
 * Uses a fake spawn function that records the argv vector shoji builds and
 * returns canned `qs list -j` output; no real quickshell is involved.
 */
#include "testmain.h"
#include "dispatch.h"
#include "instances.h"
#include "exitcodes.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char g_tmp[256];
static char g_expected[256];

/* rotate 8 static buffers for building small paths in tests */
static const char *cat2(const char *a, const char *b)
{
        static char bufs[8][1024];
        static int i = 0;
        char *p = bufs[i++ % 8];

        snprintf(p, 1024, "%s%s", a, b);
        return p;
}


/* canned quickshell behavior ------------------------------------------- */

static char g_recorded[4096];
static char g_json[2048];
static const char *g_list_json;
static int g_call_exit = 0;
static const char *g_call_err = "";
static const char *g_call_out = "";

static void set_list(const char *fmt, ...)
{
        va_list ap;

        va_start(ap, fmt);
        vsnprintf(g_json, sizeof(g_json), fmt, ap);
        va_end(ap);
        g_list_json = g_json;
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
                r->exit = 0;
                r->out = shj_strdup(g_list_json);
                r->err = shj_strdup("");
                return r;
        }
        if (argv[1] && strcmp(argv[1], "ipc") == 0) {
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

static void make_fixture(void)
{
        const char *tpl = "/tmp/shoji-inst-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));

        snprintf(g_tmp, sizeof(g_tmp), "%s", dir);
        free(dir);
        snprintf(g_expected, sizeof(g_expected), "%s/store/aaaaaaaa-shoji/shell.qml", g_tmp);
        mkdir(cat2(g_tmp, "/store"), 0755);
        mkdir(cat2(g_tmp, "/store/aaaaaaaa-shoji"), 0755);
        {
                FILE *f = fopen(g_expected, "w");

                fputs("import qs.Commons\nShellRoot {}\n", f);
                fclose(f);
        }
}

static struct shoji_instance_list *discover(void)
{
        int err = 0;
        struct shoji_instance_list *l =
            shoji_discover_instances(fake_spawn, NULL, "mockqs", &err);

        CHECK_INT_EQ(err, 0, "discovery reports no error");
        return l;
}

void test_instances(void)
{
        struct shoji_instance_list *list;
        struct shoji_selection sel;
        struct shoji_context ctx;
        struct shoji_options opts;
        struct shoji_pipeline pl;

        test_section("instance discovery and selection");
        make_fixture();

        /* canned `qs list -a -j --show-dead` output */
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

        list = discover();
        CHECK_INT_EQ(list->count, 3, "three instances parsed");
        CHECK_INT_EQ(shoji_live_count(list), 2, "two live instances");
        CHECK_STR_EQ(list->items[0].id, "aaa111xxx", "id parsed");
        CHECK_INT_EQ(list->items[0].pid, 4242, "pid parsed");
        CHECK_STR_EQ(list->items[0].launch_time, "2026-11-17T08:00:00", "launch time parsed");
        CHECK_INT_EQ(list->items[2].dead, 1, "dead instance flagged");

        /* matching works through a canonical path that no longer exists on
         * disk (the instance record wins, no realpath needed) */
        CHECK_INT_EQ(shoji_select_instance(list, g_expected, NULL, &sel), SHOJI_SELECT_OK,
                     "expected config matches");
        CHECK_INT_EQ(sel.match_count, 1, "one live match");
        CHECK_INT_EQ(sel.dead_match_count, 1, "one dead match");
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

        /* ambiguous: two live instances of the same config */
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

        /* dead-only match */
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

        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_OK, "pipeline selects instance");
        CHECK(pl.sel.selected && strcmp(pl.sel.selected->id, "aaa111xxx") == 0,
              "pipeline selected expected instance");

        g_call_exit = 0;
        g_call_out = "";
        g_call_err = "";
        {
                char *args[1];

                args[0] = (char *)"calendar";
                CHECK_INT_EQ(shoji_dispatch_call(&ctx, &pl, "island", "tab", args, 1),
                             SHOJI_EXIT_OK, "dispatch succeeds on qs exit 0");
        }
        CHECK_STR_EQ(g_recorded,
                     "mockqs ipc -i aaa111xxx --any-display call island tab calendar",
                     "dispatch builds the exact argv vector");
        shoji_pipeline_release(&pl);

        /* qs reports an unknown target -> mapped to exit 65 */
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        g_call_exit = 255;
        g_call_err = "Target not found.\n";
        CHECK_INT_EQ(shoji_dispatch_call(&ctx, &pl, "bogus", "fn", NULL, 0),
                     SHOJI_EXIT_BADIPC, "target-not-found maps to 65");
        shoji_pipeline_release(&pl);

        /* generic qs failure -> exit 1 */
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
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOINSTANCE,
                     "no match refuses to dispatch");
        CHECK(strstr(g_recorded, "ipc") == NULL, "no ipc dispatch when no instance matches");
        shoji_pipeline_release(&pl);

        /* store unresolved + no override -> 66 */
        memset(&ctx, 0, sizeof(ctx));
        ctx.qs_bin = "mockqs";
        ctx.spawn = fake_spawn;
        ctx.spawn_user = NULL;
        ctx.have_store = 0;
        shoji_pipeline_run(&ctx, &opts, 1, &pl);
        CHECK_INT_EQ(pl.exit_code, SHOJI_EXIT_NOSTORE,
                     "unresolved store refuses dispatch");
        shoji_pipeline_release(&pl);

        shoji_store_free(&ctx.store);
        rmdir(cat2(g_tmp, "/store/aaaaaaaa-shoji"));
        rmdir(cat2(g_tmp, "/store"));
        rmdir(g_tmp);
}
