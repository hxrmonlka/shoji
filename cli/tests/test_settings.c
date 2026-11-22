#include "testmain.h"
#include "cli.h"
#include "dispatch.h"
#include "exitcodes.h"
#include "json.h"
#include "proc.h"
#include "settings.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char g_tmp[256];
static char g_store[384];
static char g_shell_qml[448];
static char g_instance_json[1024];

static int g_list_calls;
static int g_ipc_calls;
static char g_last_fn[32];
static char g_last_args[256];
static const char *g_set_reply = "true";
static const char *g_get_reply = NULL;

static const char *LIST_JSON =
        "{\"categories\":[{\"id\":\"island\",\"title\":\"Island\"},"
        "{\"id\":\"features\",\"title\":\"Features\"},"
        "{\"id\":\"system\",\"title\":\"System\"}],"
        "\"settings\":["
        "{\"key\":\"pillHeight\",\"category\":\"island\",\"section\":\"Pill\","
        "\"label\":\"Pill height\",\"type\":\"int\",\"default\":44,\"value\":48,"
        "\"min\":32,\"max\":72,\"step\":1},"
        "{\"key\":\"mergeCircles\",\"category\":\"features\",\"section\":\"Island\","
        "\"label\":\"Merge\",\"type\":\"bool\",\"default\":false,\"value\":true,"
        "\"description\":\"Hide the two circles.\"},"
        "{\"key\":\"searchEngine\",\"category\":\"features\",\"section\":\"Spotlight\","
        "\"label\":\"Web search engine\",\"type\":\"choice\",\"default\":\"kagi\","
        "\"value\":\"google\",\"options\":[\"kagi\",\"google\"],"
        "\"description\":\"Used by the >w prefix.\"},"
        "{\"key\":\"nightCommand\",\"category\":\"system\",\"section\":\"Night mode\","
        "\"label\":\"Night command\",\"type\":\"string\","
        "\"default\":\"gammastep -m wayland -O {temp}\",\"value\":\"\"}"
        "]}";

static const char *DUMP_JSON =
        "{\"searchEngine\":\"google\",\"pillHeight\":44,\"flag\":true,\"none\":null}";

static const char *EXPORT_JSON =
        "{\"nightCommand\":\"gammastep -m wayland -O {temp}\",\"pillHeight\":44}";

#define CANONICAL_DUMP \
        "{\n  \"flag\": true,\n  \"none\": null,\n  \"pillHeight\": 44,\n" \
        "  \"searchEngine\": \"google\"\n}"

#define CANONICAL_EXPORT \
        "{\n  \"nightCommand\": \"gammastep -m wayland -O {temp}\",\n" \
        "  \"pillHeight\": 44\n}"

#define CANONICAL_DUMP_OUT CANONICAL_DUMP "\n"
#define CANONICAL_EXPORT_OUT CANONICAL_EXPORT "\n"

static struct shj_proc_result *fake_result(const char *out)
{
        struct shj_proc_result *r = calloc(1, sizeof(*r));

        r->exit = 0;
        r->out = strdup(out ? out : "");
        r->err = strdup("");
        return r;
}

static struct shj_proc_result *fake_spawn(const char *const argv[], void *user)
{
        (void)user;

        if (strcmp(argv[1], "list") == 0) {
                g_list_calls++;
                return fake_result(g_instance_json);
        }
        if (strcmp(argv[1], "ipc") == 0) {
                const char *fn = argv[6];

                g_ipc_calls++;
                snprintf(g_last_fn, sizeof(g_last_fn), "%s", fn);
                snprintf(g_last_args, sizeof(g_last_args), "%s", argv[7] ? argv[7] : "");
                for (int i = 8; argv[i]; i++) {
                        strncat(g_last_args, "|", sizeof(g_last_args) - strlen(g_last_args) - 1);
                        strncat(g_last_args, argv[i],
                                sizeof(g_last_args) - strlen(g_last_args) - 1);
                }
                if (strcmp(fn, "list") == 0)
                        return fake_result(LIST_JSON);
                if (strcmp(fn, "dump") == 0)
                        return fake_result(DUMP_JSON);
                if (strcmp(fn, "exportOverrides") == 0)
                        return fake_result(EXPORT_JSON);
                if (strcmp(fn, "get") == 0) {
                        if (g_get_reply)
                                return fake_result(g_get_reply);
                        if (strcmp(argv[7], "pillHeight") == 0)
                                return fake_result("44\n");
                        return fake_result("\n");
                }
                if (strcmp(fn, "set") == 0)
                        return fake_result(g_set_reply);
        }
        return fake_result("");
}

static char *g_stdout_data;
static char *g_stderr_data;

static void begin_capture(void)
{
        fflush(stdout);
        fflush(stderr);
}

static void end_capture(FILE *to, FILE *te, int saved_out, int saved_err)
{
        long n;
        char buf[4096];
        struct shj_sbuf so, se;

        fflush(stdout);
        fflush(stderr);
        dup2(saved_out, STDOUT_FILENO);
        dup2(saved_err, STDERR_FILENO);
        close(saved_out);
        close(saved_err);

        shj_sbuf_init(&so);
        rewind(to);
        while ((n = (long)fread(buf, 1, sizeof(buf), to)) > 0)
                shj_sbuf_addn(&so, buf, (size_t)n);
        fclose(to);

        shj_sbuf_init(&se);
        rewind(te);
        while ((n = (long)fread(buf, 1, sizeof(buf), te)) > 0)
                shj_sbuf_addn(&se, buf, (size_t)n);
        fclose(te);

        free(g_stdout_data);
        free(g_stderr_data);
        g_stdout_data = shj_sbuf_detach(&so);
        g_stderr_data = shj_sbuf_detach(&se);
}

static void reset_state(void)
{
        g_list_calls = 0;
        g_ipc_calls = 0;
        g_last_fn[0] = '\0';
        g_last_args[0] = '\0';
        g_set_reply = "true";
        g_get_reply = NULL;
}

static void reset_counters(void)
{
        g_list_calls = 0;
        g_ipc_calls = 0;
        g_last_fn[0] = '\0';
        g_last_args[0] = '\0';
}

static struct shoji_context g_ctx;
static struct shoji_options g_opts;

static void setup_context(void)
{
        memset(&g_opts, 0, sizeof(g_opts));
        shoji_context_init(&g_ctx, &g_opts);
        g_ctx.spawn = fake_spawn;
        shoji_context_resolve_store(&g_ctx, &g_opts);
        reset_state();
}

static int run_list(const char *category, int json)
{
        FILE *to, *te;
        int saved_out, saved_err, code;

        reset_counters();
        begin_capture();
        to = tmpfile();
        te = tmpfile();
        saved_out = dup(STDOUT_FILENO);
        saved_err = dup(STDERR_FILENO);
        dup2(fileno(to), STDOUT_FILENO);
        dup2(fileno(te), STDERR_FILENO);
        g_opts.json = json;
        code = shoji_cmd_settings_list(&g_ctx, &g_opts, category);
        end_capture(to, te, saved_out, saved_err);
        return code;
}

static int run_dump(void)
{
        FILE *to, *te;
        int saved_out, saved_err, code;

        reset_counters();
        begin_capture();
        to = tmpfile();
        te = tmpfile();
        saved_out = dup(STDOUT_FILENO);
        saved_err = dup(STDERR_FILENO);
        dup2(fileno(to), STDOUT_FILENO);
        dup2(fileno(te), STDERR_FILENO);
        code = shoji_cmd_settings_dump(&g_ctx, &g_opts);
        end_capture(to, te, saved_out, saved_err);
        return code;
}

static int run_export(void)
{
        FILE *to, *te;
        int saved_out, saved_err, code;

        reset_counters();
        begin_capture();
        to = tmpfile();
        te = tmpfile();
        saved_out = dup(STDOUT_FILENO);
        saved_err = dup(STDERR_FILENO);
        dup2(fileno(to), STDOUT_FILENO);
        dup2(fileno(te), STDERR_FILENO);
        code = shoji_cmd_settings_export(&g_ctx, &g_opts);
        end_capture(to, te, saved_out, saved_err);
        return code;
}

static int run_get(const char *key)
{
        FILE *to, *te;
        int saved_out, saved_err, code;

        reset_counters();
        begin_capture();
        to = tmpfile();
        te = tmpfile();
        saved_out = dup(STDOUT_FILENO);
        saved_err = dup(STDERR_FILENO);
        dup2(fileno(to), STDOUT_FILENO);
        dup2(fileno(te), STDERR_FILENO);
        code = shoji_cmd_settings_get(&g_ctx, &g_opts, key);
        end_capture(to, te, saved_out, saved_err);
        return code;
}

static int run_set(const char *key, const char *value)
{
        FILE *to, *te;
        int saved_out, saved_err, code;

        reset_counters();
        begin_capture();
        to = tmpfile();
        te = tmpfile();
        saved_out = dup(STDOUT_FILENO);
        saved_err = dup(STDERR_FILENO);
        dup2(fileno(to), STDOUT_FILENO);
        dup2(fileno(te), STDERR_FILENO);
        code = shoji_cmd_settings_set(&g_ctx, &g_opts, key, value);
        end_capture(to, te, saved_out, saved_err);
        return code;
}

static int write_file(const char *path, const char *contents)
{
        FILE *f = fopen(path, "w");

        if (!f)
                return -1;
        if (fputs(contents, f) == EOF) {
                fclose(f);
                return -1;
        }
        return fclose(f) != 0 ? -1 : 0;
}

static int make_env(void)
{
        const char *tpl = "/tmp/shoji-settings-test-XXXXXX";
        char *dir = mkdtemp(strdup(tpl));
        char storedir[320];

        if (!dir)
                return -1;
        snprintf(g_tmp, sizeof(g_tmp), "%s", dir);
        free(dir);
        snprintf(g_store, sizeof(g_store), "%s/store/aaaaaaaa-shoji", g_tmp);
        snprintf(g_shell_qml, sizeof(g_shell_qml), "%s/shell.qml", g_store);
        snprintf(storedir, sizeof(storedir), "%s/store", g_tmp);

        if (mkdir(storedir, 0755) != 0)
                return -1;
        if (mkdir(g_store, 0755) != 0)
                return -1;
        if (write_file(g_shell_qml, "import qs.Commons\nShellRoot {}\n") != 0)
                return -1;
        if (setenv("SHOJI_STORE_PATH", g_store, 1) != 0)
                return -1;
        snprintf(g_instance_json, sizeof(g_instance_json),
                 "[{\"id\":\"testsettings01\",\"pid\":4242,\"shell_id\":\"p1\","
                 "\"config_path\":\"%s\",\"launch_time\":\"2026-11-17T08:00:00\"}]",
                 g_shell_qml);
        return 0;
}

static void test_json_emit(void)
{
        struct shj_json *v;
        char *text;
        char num[40];

        test_section("json emit");

        shj_json_number_str(num, sizeof(num), 44.0);
        CHECK_STR_EQ(num, "44", "number 44 renders as integer");
        shj_json_number_str(num, sizeof(num), -3.0);
        CHECK_STR_EQ(num, "-3", "negative integer renders");
        shj_json_number_str(num, sizeof(num), 0.0);
        CHECK_STR_EQ(num, "0", "zero renders as 0");
        shj_json_number_str(num, sizeof(num), 44.5);
        CHECK_STR_EQ(num, "44.5", "fractional number renders");
        shj_json_number_str(num, sizeof(num), 0.1);
        CHECK_STR_EQ(num, "0.1", "0.1 renders without noise");
        shj_json_number_str(num, sizeof(num), 1e16);
        CHECK_STR_EQ(num, "1e+16", "large number stays valid JSON");
        {
                double d = strtod(num, NULL);

                CHECK(d == 1e16, "large number round-trips");
        }

        v = shj_json_parse(DUMP_JSON, NULL);
        CHECK(v != NULL, "dump fixture parses");
        text = shj_json_emit(v, 1, 1);
        CHECK_STR_EQ(text, CANONICAL_DUMP, "sorted pretty emit matches canonical dump");
        free(text);
        text = shj_json_emit(v, 0, 0);
        CHECK_STR_EQ(text, DUMP_JSON, "compact unsorted emit preserves parse order");
        free(text);
        shj_json_free(v);

        v = shj_json_parse(EXPORT_JSON, NULL);
        text = shj_json_emit(v, 1, 1);
        CHECK_STR_EQ(text, CANONICAL_EXPORT, "sorted pretty emit matches canonical export");
        free(text);
        shj_json_free(v);

        v = shj_json_parse("{\"s\":\"a\\\"b\\\\c\\nd\\t\\u0001\\u00e9\",\"e\":{},\"a\":[]}",
                           NULL);
        CHECK(v != NULL, "escape fixture parses");
        text = shj_json_emit(v, 0, 0);
        CHECK_STR_EQ(text,
                     "{\"s\":\"a\\\"b\\\\c\\nd\\t\\u0001\xc3\xa9\",\"e\":{},\"a\":[]}",
                     "emit escapes quotes backslash controls and keeps utf-8");
        free(text);
        shj_json_free(v);

        v = shj_json_parse("{}", NULL);
        text = shj_json_emit(v, 1, 1);
        CHECK_STR_EQ(text, "{}", "empty object stays inline when pretty");
        free(text);
        shj_json_free(v);

        v = shj_json_parse("[]", NULL);
        text = shj_json_emit(v, 1, 0);
        CHECK_STR_EQ(text, "[]", "empty array stays inline when pretty");
        free(text);
        shj_json_free(v);

        v = shj_json_parse("{\"z\":[1,{\"b\":1,\"a\":2}],\"y\":-2.5}", NULL);
        text = shj_json_emit(v, 1, 1);
        CHECK_STR_EQ(text,
                     "{\n  \"y\": -2.5,\n  \"z\": [\n    1,\n    {\n      \"a\": 2,\n"
                     "      \"b\": 1\n    }\n  ]\n}",
                     "nested pretty sorted emit indents");
        {
                struct shj_json *again = shj_json_parse(text, NULL);

                CHECK(again != NULL, "nested emit re-parses");
                shj_json_free(again);
        }
        free(text);
        shj_json_free(v);
}

static void test_settings_helpers(void)
{
        struct shj_json *root;
        const struct shj_json *categories = NULL;
        const struct shj_json *settings = NULL;
        const struct shj_json *entry;
        char cons[128];

        test_section("settings payload helpers");

        root = shj_json_parse(LIST_JSON, NULL);
        CHECK(root != NULL, "list fixture parses");
        categories = shj_json_get(root, "categories");
        settings = shj_json_get(root, "settings");
        CHECK(categories && categories->type == SHOJI_JSON_ARRAY, "categories array present");
        CHECK(settings && settings->type == SHOJI_JSON_ARRAY, "settings array present");

        CHECK(shoji_settings_category_matches(categories, NULL), "no filter matches");
        CHECK(shoji_settings_category_matches(categories, ""), "empty filter matches");
        CHECK(shoji_settings_category_matches(categories, "island"), "id match");
        CHECK(shoji_settings_category_matches(categories, "ISLAND"), "id match is case-insensitive");
        CHECK(shoji_settings_category_matches(categories, "features"), "second id match");
        CHECK(shoji_settings_category_matches(categories, "Features"), "title match");
        CHECK(shoji_settings_category_matches(categories, "SYSTEM"), "title match case-insensitive");
        CHECK(!shoji_settings_category_matches(categories, "bogus"), "unknown filter rejected");
        CHECK(!shoji_settings_category_matches(NULL, "island"), "missing categories reject");

        {
                char *id = shoji_settings_resolve_category(categories, "Features");

                CHECK_STR_EQ(id, "features", "resolve category by title returns id");
                free(id);
                id = shoji_settings_resolve_category(categories, "nope");
                CHECK(!id, "resolve category fails on unknown filter");
                free(id);
        }

        entry = shoji_settings_find_entry(settings, "pillHeight");
        CHECK(entry != NULL, "find entry by key");
        CHECK_STR_EQ(shj_json_str(shj_json_get(entry, "category"), ""), "island",
                     "entry category");
        CHECK(!shoji_settings_find_entry(settings, "nope"), "unknown key not found");
        CHECK(!shoji_settings_find_entry(NULL, "pillHeight"), "missing array not found");

        entry = shoji_settings_find_entry(settings, "pillHeight");
        shoji_settings_entry_constraints(entry, cons, sizeof(cons));
        CHECK_STR_EQ(cons, "32..72 step 1", "int constraints rendered");
        entry = shoji_settings_find_entry(settings, "searchEngine");
        shoji_settings_entry_constraints(entry, cons, sizeof(cons));
        CHECK_STR_EQ(cons, "kagi|google", "choice constraints rendered");
        entry = shoji_settings_find_entry(settings, "mergeCircles");
        shoji_settings_entry_constraints(entry, cons, sizeof(cons));
        CHECK_STR_EQ(cons, "", "bool has no constraints");
        entry = shoji_settings_find_entry(settings, "nightCommand");
        shoji_settings_entry_constraints(entry, cons, sizeof(cons));
        CHECK_STR_EQ(cons, "", "string has no constraints");

        {
                struct shj_json *num = shj_json_parse("48", NULL);
                char *s = shoji_settings_display_value(num);

                CHECK_STR_EQ(s, "48", "display number");
                free(s);
                shj_json_free(num);
        }
        {
                struct shj_json *b = shj_json_parse("true", NULL);
                char *s = shoji_settings_display_value(b);

                CHECK_STR_EQ(s, "true", "display bool");
                free(s);
                shj_json_free(b);
        }
        {
                struct shj_json *arr = shj_json_parse("[1,\"x\"]", NULL);
                char *s = shoji_settings_display_value(arr);

                CHECK_STR_EQ(s, "[1,\"x\"]", "display container as compact json");
                free(s);
                shj_json_free(arr);
        }
        {
                struct shj_json *nul = shj_json_parse("null", NULL);
                char *s = shoji_settings_display_value(nul);

                CHECK_STR_EQ(s, "null", "display null");
                free(s);
                shj_json_free(nul);
        }

        shj_json_free(root);
}

static void test_settings_parse(void)
{
        struct shoji_options opts;
        char *argv1[] = { "shoji", "settings", "list", NULL };
        char *argv2[] = { "shoji", "settings", "list", "features", NULL };
        char *argv3[] = { "shoji", "settings", "dump", NULL };
        char *argv4[] = { "shoji", "settings", "export", NULL };
        char *argv5[] = { "shoji", "settings", "get", "pillHeight", NULL };
        char *argv6[] = { "shoji", "settings", "set", "pillHeight", "44", NULL };
        char *argv7[] = { "shoji", "settings", "reset", NULL };
        char *argv8[] = { "shoji", "settings", NULL };
        char *argv9[] = { "shoji", "settings", "explode", NULL };
        char *argv10[] = { "shoji", "settings", "list", "a", "b", NULL };
        char *argv11[] = { "shoji", "settings", "dump", "x", NULL };
        char *argv12[] = { "shoji", "settings", "get", NULL };
        char *argv13[] = { "shoji", "settings", "set", "k", NULL };
        char *argv14[] = { "shoji", "settings", "set", "a", "b", "c", NULL };
        char *argv15[] = { "shoji", "settings", "list", "--json", NULL };

        test_section("settings parse");

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(3, argv1, &opts) == 0, "settings list parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_LIST, "list kind");
        CHECK(!opts.facade_args[0], "list without filter");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(4, argv2, &opts) == 0, "settings list category parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_LIST, "list category kind");
        CHECK_STR_EQ(opts.facade_args[0], "features", "list category stored");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(4, argv15, &opts) == 0, "settings list --json parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_LIST, "list --json kind");
        CHECK_INT_EQ(opts.json, 1, "--json consumed as global flag");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(3, argv3, &opts) == 0, "settings dump parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_DUMP, "dump kind");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(3, argv4, &opts) == 0, "settings export parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_EXPORT, "export kind");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(4, argv5, &opts) == 0, "settings get parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_GET, "get kind");
        CHECK_STR_EQ(opts.facade_args[0], "pillHeight", "get key stored");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(5, argv6, &opts) == 0, "settings set parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_SETTINGS_SET, "set kind");
        CHECK_STR_EQ(opts.facade_args[0], "pillHeight", "set key stored");
        CHECK_STR_EQ(opts.facade_args[1], "44", "set value stored");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK(shoji_parse(3, argv7, &opts) == 0, "settings reset still parses");
        CHECK_INT_EQ(opts.kind, SHOJI_CMD_FACADE, "reset stays facade");
        CHECK(opts.facade && strcmp(opts.facade->function, "reset") == 0,
              "reset maps to settings.reset");
        shoji_options_free(&opts);

        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(2, argv8, &opts), SHOJI_EXIT_USAGE, "bare settings usage");
        shoji_options_free(&opts);
        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(3, argv9, &opts), SHOJI_EXIT_USAGE,
                     "unknown settings subcommand usage");
        shoji_options_free(&opts);
        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(5, argv10, &opts), SHOJI_EXIT_USAGE,
                     "list with two arguments usage");
        shoji_options_free(&opts);
        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(4, argv11, &opts), SHOJI_EXIT_USAGE,
                     "dump with argument usage");
        shoji_options_free(&opts);
        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(3, argv12, &opts), SHOJI_EXIT_USAGE,
                     "get without key usage");
        shoji_options_free(&opts);
        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(4, argv13, &opts), SHOJI_EXIT_USAGE,
                     "set without value usage");
        shoji_options_free(&opts);
        memset(&opts, 0, sizeof(opts));
        CHECK_INT_EQ(shoji_parse(6, argv14, &opts), SHOJI_EXIT_USAGE,
                     "set with three arguments usage");
        shoji_options_free(&opts);
}

static void test_settings_commands(void)
{
        int code;

        test_section("settings managed commands");

        CHECK(make_env() == 0, "fake store environment created");
        setup_context();

        code = run_list(NULL, 0);
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings list exits 0");
        CHECK(g_list_calls == 1, "settings list runs exactly one listing");
        CHECK(g_ipc_calls == 1, "settings list runs exactly one IPC call");
        CHECK(g_stdout_data && strstr(g_stdout_data, "KEY") != NULL, "list prints header");
        CHECK(g_stdout_data && strstr(g_stdout_data, "pillHeight") != NULL,
              "list contains key");
        CHECK(g_stdout_data && strstr(g_stdout_data, "32..72 step 1") != NULL,
              "list contains numeric constraints");
        CHECK(g_stdout_data && strstr(g_stdout_data, "kagi|google") != NULL,
              "list contains choice constraints");
        CHECK(g_stdout_data && strstr(g_stdout_data, "Hide the two circles.") != NULL,
              "list contains description");

        code = run_list("features", 0);
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings list features exits 0");
        CHECK(g_stdout_data && strstr(g_stdout_data, "mergeCircles") != NULL,
              "filtered list keeps feature rows");
        CHECK(g_stdout_data && !strstr(g_stdout_data, "pillHeight"),
              "filtered list drops other categories");

        code = run_list("Features", 0);
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings list by title exits 0");
        CHECK(g_stdout_data && strstr(g_stdout_data, "mergeCircles") != NULL,
              "title filter matches");

        code = run_list("bogus", 0);
        CHECK_INT_EQ(code, SHOJI_EXIT_USAGE, "unknown category exits 64");
        CHECK(g_stderr_data && strstr(g_stderr_data, "unknown setting category 'bogus'") != NULL,
              "unknown category diagnostic");
        CHECK(g_stderr_data && strstr(g_stderr_data, "island") != NULL,
              "unknown category hint lists categories");

        code = run_list(NULL, 1);
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings list --json exits 0");
        CHECK(g_stdout_data && strncmp(g_stdout_data, "{\"categories\":", 14) == 0,
              "list --json starts with categories object");
        CHECK(g_stdout_data && strstr(g_stdout_data, "\"settings\":[") != NULL,
              "list --json contains settings array");
        {
                struct shj_json *v = shj_json_parse(g_stdout_data, NULL);

                CHECK(v != NULL, "list --json output is valid JSON");
                CHECK(v && v->type == SHOJI_JSON_OBJECT, "list --json output is an object");
                shj_json_free(v);
        }

        code = run_list("features", 1);
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings list --json filtered exits 0");
        CHECK(g_stdout_data && !strstr(g_stdout_data, "\"pillHeight\""),
              "filtered json drops other categories");
        CHECK(g_stdout_data && strstr(g_stdout_data, "\"mergeCircles\"") != NULL,
              "filtered json keeps feature rows");

        code = run_dump();
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings dump exits 0");
        CHECK(g_list_calls == 1, "settings dump runs exactly one listing");
        CHECK(g_ipc_calls == 1, "settings dump runs exactly one IPC call");
        CHECK_STR_EQ(g_stdout_data, CANONICAL_DUMP_OUT, "dump output is canonical sorted JSON");
        {
                struct shj_json *v = shj_json_parse(g_stdout_data, NULL);

                CHECK(v && v->type == SHOJI_JSON_OBJECT, "dump output parses as object");
                shj_json_free(v);
        }

        code = run_dump();
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings dump reruns");
        CHECK_STR_EQ(g_stdout_data, CANONICAL_DUMP_OUT, "dump output is deterministic");

        code = run_export();
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings export exits 0");
        CHECK_STR_EQ(g_stdout_data, CANONICAL_EXPORT_OUT, "export output is canonical sorted JSON");
        {
                struct shj_json *v = shj_json_parse(g_stdout_data, NULL);

                CHECK(v && v->type == SHOJI_JSON_OBJECT, "export output parses as object");
                shj_json_free(v);
        }

        code = run_get("pillHeight");
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings get known key exits 0");
        CHECK(g_ipc_calls == 1, "get with value needs no existence check");
        CHECK_STR_EQ(g_stdout_data, "44\n", "get relays the effective value");

        code = run_get("nightCommand");
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings get empty string value exits 0");
        CHECK(g_ipc_calls == 2, "empty get triggers the existence check");
        CHECK_STR_EQ(g_stdout_data, "\n", "known empty value prints empty line");

        code = run_get("nope");
        CHECK_INT_EQ(code, SHOJI_EXIT_BADIPC, "settings get unknown key exits 65");
        CHECK(g_stderr_data && strstr(g_stderr_data, "unknown setting 'nope'") != NULL,
              "unknown key diagnostic");

        code = run_set("pillHeight", "44");
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "settings set valid exits 0");
        CHECK_STR_EQ(g_stdout_data, "true\n", "set success relays true");
        CHECK(strstr(g_last_args, "pillHeight|44") != NULL, "set argv carries key and value");

        g_set_reply = "false";
        code = run_set("nope", "x");
        CHECK_INT_EQ(code, SHOJI_EXIT_BADIPC, "rejected set with unknown key exits 65");
        CHECK(g_list_calls == 1, "set failure path does not re-list");
        CHECK(g_ipc_calls == 2, "set failure path checks existence once");
        CHECK(g_stderr_data && strstr(g_stderr_data, "unknown setting 'nope'") != NULL,
              "set unknown key diagnostic");

        code = run_set("pillHeight", "999");
        CHECK_INT_EQ(code, SHOJI_EXIT_BADIPC, "rejected set with known key exits 65");
        CHECK(g_stderr_data && strstr(g_stderr_data, "invalid value for 'pillHeight'") != NULL,
              "set invalid value diagnostic");
        CHECK(g_stderr_data && strstr(g_stderr_data, "32..72") != NULL,
              "invalid value diagnostic includes constraints");

        g_set_reply = "false";
        code = run_set("pillHeight", "44");
        CHECK_INT_EQ(code, SHOJI_EXIT_BADIPC, "shell false on valid-shaped value still rejects");
        g_set_reply = "true";

        g_set_reply = "garbage";
        code = run_set("pillHeight", "44");
        CHECK_INT_EQ(code, SHOJI_EXIT_FAILED, "unexpected set reply exits 1");
        CHECK(g_stderr_data && strstr(g_stderr_data, "unexpected data") != NULL,
              "unexpected reply diagnostic");
        g_set_reply = "true";

        g_get_reply = "\n";
        code = run_get("nightCommand");
        CHECK_INT_EQ(code, SHOJI_EXIT_OK, "get of empty value still resolves");
        CHECK_STR_EQ(g_stdout_data, "\n", "empty value passthrough");
        g_get_reply = NULL;
}

void test_settings(void)
{
        test_json_emit();
        test_settings_helpers();
        test_settings_parse();
        test_settings_commands();
        free(g_stdout_data);
        free(g_stderr_data);
        g_stdout_data = NULL;
        g_stderr_data = NULL;
        unsetenv("SHOJI_STORE_PATH");
}
