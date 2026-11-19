/* shoji-cli tests -- store resolver precedence and canonicalization.
 *
 * Runs entirely on injected roots and temporary directories; no NixOS
 * system or quickshell session is required.
 */
#include "testmain.h"
#include "resolver.h"
#include "util.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char g_tmp[256];
/* g_store/g_profile hold g_tmp plus the longest fixed suffix, so both are
 * sized for g_tmp (256) plus suffix plus NUL, which keeps GCC's
 * -Wformat-truncation analysis provably within bounds. */
static char g_store[512];
static char g_profile[512];
static char g_empty_config_dirs[512];

/* rotate 8 static buffers for building small paths in tests */
static const char *cat2(const char *a, const char *b)
{
        static char bufs[8][1024];
        static int i = 0;
        char *p = bufs[i++ % 8];

        snprintf(p, 1024, "%s%s", a, b);
        return p;
}



static int write_fixture_file(const char *path, const char *contents)
{
        FILE *f = fopen(path, "w");
        int write_failed;
        int close_failed;

        if (!f)
                return -1;
        write_failed = fputs(contents, f) == EOF;
        close_failed = fclose(f) != 0;
        return write_failed || close_failed ? -1 : 0;
}

/* Create a fake nix-store shoji config under a temp dir. */
static int make_fixture(void)
{
        const char *tpl = "/tmp/shoji-test-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));

        if (!dir)
                return -1;
        snprintf(g_tmp, sizeof(g_tmp), "%s", dir);
        free(dir);
        snprintf(g_store, sizeof(g_store), "%s/store/aaaaaaaa-shoji-1.0", g_tmp);
        snprintf(g_profile, sizeof(g_profile), "%s/profile", g_tmp);
        snprintf(g_empty_config_dirs, sizeof(g_empty_config_dirs),
                 "%s/nonexistent-config-dirs", g_tmp);

        mkdir(cat2(g_tmp, "/store"), 0755);
        mkdir(g_store, 0755);
        if (write_fixture_file(cat2(g_store, "/shell.qml"),
                               "import QtQuick\nimport qs.Commons\nShellRoot {}\n") != 0)
                return -1;
        mkdir(g_profile, 0755);
        return 0;
}

static void rmtree(const char *path)
{
        char cmd[1024];

        snprintf(cmd, sizeof(cmd), "rm -rf '%s'", path);
        (void)system(cmd);
}

static struct shoji_resolver_env base_env(void)
{
        struct shoji_resolver_env env;

        memset(&env, 0, sizeof(env));
        env.home = g_tmp;
        env.user = "tester";
        env.config_home = NULL;
        env.config_dirs = g_empty_config_dirs;
        return env;
}

static void set_link(const char *link_path, const char *target)
{
        remove(link_path);
        symlink(target, link_path);
}

void test_resolver(void)
{
        struct shoji_resolver_env env;
        struct shoji_store store;
        char *qml;
        char *dir;

        test_section("store resolver");
        if (make_fixture() != 0) {
                test_fail("resolver fixture created");
                return;
        }

        /* 1. explicit --store wins over everything */
        env = base_env();
        env.store_override = g_store;
        env.env_store_path = cat2(g_tmp, "/nowhere");
        env.profile_roots = cat2(g_tmp, "/nowhere");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "explicit --store resolves");
        CHECK_STR_EQ(store.source_name, "explicit", "explicit source name");
        CHECK_STR_EQ(store.shell_qml, cat2(g_store, "/shell.qml"), "dir override gets shell.qml");
        shoji_store_free(&store);

        /* 1b. explicit --store pointing at shell.qml directly */
        env.store_override = cat2(g_store, "/shell.qml");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "file override resolves");
        CHECK_STR_EQ(store.shell_qml, cat2(g_store, "/shell.qml"), "file override canonical");
        shoji_store_free(&store);

        /* 1c. explicit --store with a trailing slash */
        env.store_override = shj_strcat(2, g_store, "/");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "trailing slash resolved");
        CHECK_STR_EQ(store.shell_qml, cat2(g_store, "/shell.qml"), "trailing slash canonical");
        shoji_store_free(&store);
        free((void *)env.store_override);

        /* 2. environment variable */
        env = base_env();
        env.env_store_path = g_store;
        env.profile_roots = cat2(g_tmp, "/nowhere");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "SHOJI_STORE_PATH resolves");
        CHECK_STR_EQ(store.source_name, "environment", "environment source name");
        shoji_store_free(&store);

        /* 3. build-time macro */
        env = base_env();
        env.builtin_store = g_store;
        env.profile_roots = cat2(g_tmp, "/nowhere");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "built-in store resolves");
        CHECK_STR_EQ(store.source_name, "build-time", "build-time source name");
        shoji_store_free(&store);

        /* 4. active config link ($XDG_CONFIG_HOME/quickshell/shoji) */
        {
                char *xdg = shj_strcat(2, g_tmp, "/xdgconfig");
                char *qsdir = shj_path_join(xdg, "quickshell/shoji");
                char *fake_store = shj_strcat(2, g_tmp, "/store/bbbbbbbb-shoji-1.1");

                mkdir(xdg, 0755);
                mkdir(cat2(xdg, "/quickshell"), 0755);
                mkdir(qsdir, 0755);
                mkdir(fake_store, 0755);
                if (write_fixture_file(cat2(fake_store, "/shell.qml"),
                                       "import qs.Commons\nShellRoot {}\n") != 0) {
                        test_fail("config-link fixture written");
                        free(xdg); free(qsdir); free(fake_store);
                        goto cleanup;
                }
                set_link(cat2(qsdir, "/shell.qml"), cat2(fake_store, "/shell.qml"));

                env = base_env();
                env.config_home = xdg;
                env.profile_roots = cat2(g_tmp, "/nowhere");
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "config link resolves");
                CHECK_STR_EQ(store.source_name, "config-link", "config-link source name");
                CHECK_STR_EQ(store.shell_qml, cat2(fake_store, "/shell.qml"),
                             "config link canonicalizes through symlink");
                CHECK_STR_EQ(store.dir, fake_store,
                             "config link directory follows canonical shell.qml target");
                shoji_store_free(&store);
                rmtree(xdg);
                free(xdg);
                free(qsdir);
                free(fake_store);
        }

        /* 5. profile scan: share/quickshell/shoji/shell.qml */
        {
                char *layout = shj_path_join(g_profile, "share/quickshell/shoji");
                char *fake_store = shj_strcat(2, g_tmp, "/store/cccccccc-shoji-1.2");

                mkdir(cat2(g_profile, "/share"), 0755);
                mkdir(cat2(g_profile, "/share/quickshell"), 0755);
                mkdir(layout, 0755);
                mkdir(fake_store, 0755);
                if (write_fixture_file(cat2(fake_store, "/shell.qml"),
                                       "import qs.Commons\nShellRoot {}\n") != 0) {
                        test_fail("profile fixture written");
                        free(layout); free(fake_store);
                        goto cleanup;
                }
                set_link(cat2(layout, "/shell.qml"), cat2(fake_store, "/shell.qml"));

                env = base_env();
                env.profile_roots = g_profile;
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "profile scan resolves");
                CHECK_STR_EQ(store.source_name, "profile-scan", "profile-scan source name");
                CHECK_STR_EQ(store.shell_qml, cat2(fake_store, "/shell.qml"), "profile link canonical");
                CHECK_STR_EQ(store.dir, fake_store,
                             "profile directory follows canonical shell.qml target");
                shoji_store_free(&store);
                free(layout);
                free(fake_store);
        }

        /* 6. missing store path fails */
        env = base_env();
        env.store_override = cat2(g_tmp, "/nonexistent");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), -1, "missing --store fails");
        shoji_store_free(&store);

        /* 6b. nonexistent file inside an existing dir fails */
        env.store_override = g_tmp;
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), -1,
                     "dir without shell.qml fails");
        shoji_store_free(&store);

        /* 6c. nothing resolvable fails */
        env = base_env();
        env.profile_roots = cat2(g_tmp, "/nowhere");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), -1, "no source fails");
        shoji_store_free(&store);

        /* 7. precedence: --store beats env, env beats builtin */
        {
                char *s1 = shj_strcat(2, g_tmp, "/store/dddddddd-a");
                char *s2 = shj_strcat(2, g_tmp, "/store/dddddddd-b");
                char *s3 = shj_strcat(2, g_tmp, "/store/dddddddd-c");

                mkdir(s1, 0755); mkdir(s2, 0755); mkdir(s3, 0755);
                for (int i = 0; i < 3; i++) {
                        const char *paths[] = { s1, s2, s3 };

                        if (write_fixture_file(cat2(paths[i], "/shell.qml"),
                                               "import qs.Commons\nShellRoot {}\n") != 0) {
                                test_fail("precedence fixture written");
                                free(s1); free(s2); free(s3);
                                goto cleanup;
                        }
                }

                env = base_env();
                env.store_override = s1;
                env.env_store_path = s2;
                env.builtin_store = s3;
                env.profile_roots = cat2(g_tmp, "/nowhere");
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "precedence resolves");
                CHECK_STR_EQ(store.shell_qml, cat2(s1, "/shell.qml"), "--store beats env beats builtin");
                shoji_store_free(&store);

                env.store_override = NULL;
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "env resolves 2");
                CHECK_STR_EQ(store.shell_qml, cat2(s2, "/shell.qml"), "env beats builtin");
                shoji_store_free(&store);

                env.env_store_path = NULL;
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "builtin resolves 2");
                CHECK_STR_EQ(store.shell_qml, cat2(s3, "/shell.qml"), "builtin used");
                shoji_store_free(&store);

                free(s1);
                free(s2);
                free(s3);
        }

        /* 8. canonicalization rejects a non-shell.qml file */
        env = base_env();
        env.store_override = cat2(g_tmp, "/store");
        CHECK_INT_EQ(shoji_resolve_store(&env, &store), -1,
                     "file override must be shell.qml");
        shoji_store_free(&store);

        /* 9. default profile roots are generated */
        {
                char *roots = shoji_default_profile_roots(&env);

                CHECK(roots && strstr(roots, "/run/current-system") != NULL,
                      "default roots end with /run/current-system");
                CHECK(roots && strstr(roots, "/etc/profiles/per-user/tester") != NULL,
                      "default roots include per-user profile");
                free(roots);
        }

        /* 10. path helpers */
        qml = shj_path_join("/a/b", "c");
        CHECK_STR_EQ(qml, "/a/b/c", "path join basic");
        free(qml);
        qml = shj_path_join("/a/b/", "c");
        CHECK_STR_EQ(qml, "/a/b/c", "path join trailing slash");
        free(qml);
        dir = shj_find_in_path("definitely-not-here-xyz", g_tmp);
        CHECK(!dir, "find_in_path misses missing binary");
        free(dir);
        {
                char *program = shj_strcat(2, g_tmp, "/qs");
                char cwd[PATH_MAX];
                char *old_path = getenv("PATH") ? shj_strdup(getenv("PATH")) : NULL;

                if (write_fixture_file(program, "#!/bin/sh\nexit 0\n") != 0 ||
                    chmod(program, 0755) != 0 || !getcwd(cwd, sizeof(cwd)) ||
                    chdir(g_tmp) != 0) {
                        test_fail("PATH lookup fixture prepared");
                        free(program); free(old_path);
                        goto cleanup;
                }
                unsetenv("PATH");
                dir = shj_find_in_path(program, NULL);
                CHECK(dir != NULL, "explicit executable path works without PATH");
                free(dir);
                dir = shj_find_in_path("qs", ":/usr/bin");
                CHECK(dir && strcmp(dir, "./qs") == 0,
                      "empty PATH entry resolves in current directory");
                free(dir);
                (void)chdir(cwd);
                if (old_path) {
                        setenv("PATH", old_path, 1);
                        free(old_path);
                }
                free(program);
        }

        /* 11. XDG_CONFIG_DIRS tokenization: one, several, empty entries and
         * the directory cap. The resolver env is injected directly, so
         * these cases never read the host environment. */
        {
                char *base = shj_strcat(2, g_tmp, "/xdgdirs");
                char *store1 = shj_strcat(2, g_tmp, "/store/eeeeeeee-xdg-1");
                char *store2 = shj_strcat(2, g_tmp, "/store/ffffffff-xdg-2");
                int i;

                mkdir(base, 0755);
                mkdir(store1, 0755);
                mkdir(store2, 0755);
                if (write_fixture_file(cat2(store1, "/shell.qml"),
                                       "import qs.Commons\nShellRoot {}\n") != 0 ||
                    write_fixture_file(cat2(store2, "/shell.qml"),
                                       "import qs.Commons\nShellRoot {}\n") != 0) {
                        test_fail("XDG fixture files written");
                        free(base); free(store1); free(store2);
                        goto cleanup;
                }

                /* one directory */
                {
                        char *d1 = shj_path_join(base, "one");
                        char *qd = shj_path_join(d1, "quickshell/shoji");

                        mkdir(cat2(base, "/one"), 0755);
                        mkdir(cat2(d1, "/quickshell"), 0755);
                        mkdir(qd, 0755);
                        set_link(cat2(qd, "/shell.qml"), cat2(store1, "/shell.qml"));

                        env = base_env();
                        env.config_dirs = d1;
                        env.profile_roots = cat2(g_tmp, "/nowhere");
                        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0,
                                     "config dirs: single directory resolves");
                        CHECK_STR_EQ(store.shell_qml, cat2(store1, "/shell.qml"),
                                     "config dirs: single directory target");
                        shoji_store_free(&store);
                        free(d1);
                        free(qd);
                }

                /* several colon-separated directories: first wins */
                {
                        char *d1 = shj_path_join(base, "two");
                        char *d2 = shj_path_join(base, "three");
                        char *qd1 = shj_path_join(d1, "quickshell/shoji");
                        char *qd2 = shj_path_join(d2, "quickshell/shoji");
                        char *dirs = shj_strcat(3, d1, ":", d2);

                        mkdir(cat2(base, "/two"), 0755);
                        mkdir(cat2(base, "/three"), 0755);
                        mkdir(cat2(d1, "/quickshell"), 0755);
                        mkdir(qd1, 0755);
                        mkdir(cat2(d2, "/quickshell"), 0755);
                        mkdir(qd2, 0755);
                        set_link(cat2(qd1, "/shell.qml"), cat2(store1, "/shell.qml"));
                        set_link(cat2(qd2, "/shell.qml"), cat2(store2, "/shell.qml"));

                        env = base_env();
                        env.config_dirs = dirs;
                        env.profile_roots = cat2(g_tmp, "/nowhere");
                        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0,
                                     "config dirs: multiple directories resolve");
                        CHECK_STR_EQ(store.shell_qml, cat2(store1, "/shell.qml"),
                                     "config dirs: earlier directory wins");
                        shoji_store_free(&store);

                        /* second directory is still reachable */
                        env.config_dirs = d2;
                        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0,
                                     "config dirs: later directory resolves alone");
                        CHECK_STR_EQ(store.shell_qml, cat2(store2, "/shell.qml"),
                                     "config dirs: later directory target");
                        shoji_store_free(&store);

                        free(d1);
                        free(d2);
                        free(qd1);
                        free(qd2);
                        free(dirs);
                }

                /* empty entries are skipped, not treated as candidates */
                {
                        char *d1 = shj_path_join(base, "four");
                        char *qd = shj_path_join(d1, "quickshell/shoji");
                        char *dirs = shj_strcat(3, "::", d1, "::");

                        mkdir(cat2(base, "/four"), 0755);
                        mkdir(cat2(d1, "/quickshell"), 0755);
                        mkdir(qd, 0755);
                        set_link(cat2(qd, "/shell.qml"), cat2(store1, "/shell.qml"));

                        env = base_env();
                        env.config_dirs = dirs;
                        env.profile_roots = cat2(g_tmp, "/nowhere");
                        CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0,
                                     "config dirs: empty entries skipped");
                        CHECK_STR_EQ(store.shell_qml, cat2(store1, "/shell.qml"),
                                     "config dirs: resolution after empty entries");
                        shoji_store_free(&store);
                        free(d1);
                        free(qd);
                        free(dirs);
                }

                /* an all-empty variable yields no candidates and falls
                 * through to the profile scan */
                env = base_env();
                env.config_dirs = ":::";
                env.profile_roots = cat2(g_tmp, "/nowhere");
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), -1,
                             "config dirs: only empty entries fall through");
                shoji_store_free(&store);

                /* the directory cap is respected: with more entries than
                 * dirs[] can hold, later entries are ignored (never
                 * overflowed) */
                {
                        char *dirs = NULL;
                        char *deep = NULL;

                        for (i = 0; i < 12; i++) {
                                char name[32];
                                char *di;
                                char *joined;

                                snprintf(name, sizeof(name), "/cap%02d", i);
                                di = shj_strcat(2, base, name);
                                mkdir(di, 0755);
                                if (i == 11) {
                                        char *qsdir = shj_path_join(di, "quickshell");
                                        char *qd;

                                        mkdir(qsdir, 0755);
                                        qd = shj_path_join(qsdir, "shoji");
                                        free(qsdir);
                                        mkdir(qd, 0755);
                                        set_link(cat2(qd, "/shell.qml"),
                                                 cat2(store1, "/shell.qml"));
                                        deep = shj_strdup(di);
                                        free(qd);
                                }
                                joined = dirs ? shj_strcat(3, dirs, ":", di)
                                              : shj_strdup(di);
                                free(dirs);
                                dirs = joined;
                                free(di);
                        }
                        env = base_env();
                        env.config_dirs = dirs;
                        env.profile_roots = cat2(g_tmp, "/nowhere");
                        CHECK_INT_EQ(shoji_resolve_store(&env, &store), -1,
                                     "config dirs: entries beyond the cap are ignored");
                        shoji_store_free(&store);
                        free(deep);
                        free(dirs);
                }

                free(base);
                free(store1);
                free(store2);
        }

cleanup:
        rmtree(g_tmp);
}
