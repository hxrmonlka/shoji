/* shoji-cli tests -- store resolver precedence and canonicalization.
 *
 * Runs entirely on injected roots and temporary directories; no NixOS
 * system or quickshell session is required.
 */
#include "testmain.h"
#include "resolver.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char g_tmp[256];
static char g_store[256];
static char g_profile[256];

/* rotate 8 static buffers for building small paths in tests */
static const char *cat2(const char *a, const char *b)
{
        static char bufs[8][1024];
        static int i = 0;
        char *p = bufs[i++ % 8];

        snprintf(p, 1024, "%s%s", a, b);
        return p;
}


/* Create a fake nix-store shoji config under a temp dir. */
static void make_fixture(void)
{
        const char *tpl = "/tmp/shoji-test-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));

        snprintf(g_tmp, sizeof(g_tmp), "%s", dir);
        free(dir);
        snprintf(g_store, sizeof(g_store), "%s/store/aaaaaaaa-shoji-1.0", g_tmp);
        snprintf(g_profile, sizeof(g_profile), "%s/profile", g_tmp);

        mkdir(cat2(g_tmp, "/store"), 0755);
        mkdir(g_store, 0755);
        {
                FILE *f = fopen(cat2(g_store, "/shell.qml"), "w");

                fputs("import QtQuick\nimport qs.Commons\nShellRoot {}\n", f);
                fclose(f);
        }
        mkdir(g_profile, 0755);
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
        env.config_dirs = NULL;
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
        make_fixture();

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
                mkdir(shj_strcat(2, xdg, "/quickshell"), 0755);
                mkdir(qsdir, 0755);
                mkdir(fake_store, 0755);
                {
                        FILE *f = fopen(cat2(fake_store, "/shell.qml"), "w");

                        fputs("import qs.Commons\nShellRoot {}\n", f);
                        fclose(f);
                }
                set_link(shj_strcat(2, qsdir, "/shell.qml"), cat2(fake_store, "/shell.qml"));

                env = base_env();
                env.config_home = xdg;
                env.profile_roots = cat2(g_tmp, "/nowhere");
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "config link resolves");
                CHECK_STR_EQ(store.source_name, "config-link", "config-link source name");
                CHECK_STR_EQ(store.shell_qml, cat2(fake_store, "/shell.qml"),
                             "config link canonicalizes through symlink");
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

                mkdir(shj_strcat(2, g_profile, "/share"), 0755);
                mkdir(shj_path_join(g_profile, "share/quickshell"), 0755);
                mkdir(layout, 0755);
                mkdir(fake_store, 0755);
                {
                        FILE *f = fopen(cat2(fake_store, "/shell.qml"), "w");

                        fputs("import qs.Commons\nShellRoot {}\n", f);
                        fclose(f);
                }
                set_link(shj_strcat(2, layout, "/shell.qml"), cat2(fake_store, "/shell.qml"));

                env = base_env();
                env.profile_roots = g_profile;
                CHECK_INT_EQ(shoji_resolve_store(&env, &store), 0, "profile scan resolves");
                CHECK_STR_EQ(store.source_name, "profile-scan", "profile-scan source name");
                CHECK_STR_EQ(store.shell_qml, cat2(fake_store, "/shell.qml"), "profile link canonical");
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
                        FILE *f = fopen(shj_strcat(2, paths[i], "/shell.qml"), "w");

                        fputs("import qs.Commons\nShellRoot {}\n", f);
                        fclose(f);
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

        rmtree(g_tmp);
}
