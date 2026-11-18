#define _POSIX_C_SOURCE 200809L

#include "resolver.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef SHOJI_DEFAULT_STORE
#define SHOJI_DEFAULT_STORE ""
#endif

static const char *source_name(enum shoji_store_source s)
{
        switch (s) {
        case SHOJI_STORE_EXPLICIT: return "explicit";
        case SHOJI_STORE_ENV: return "environment";
        case SHOJI_STORE_BUILTIN: return "build-time";
        case SHOJI_STORE_CONFIG_LINK: return "config-link";
        case SHOJI_STORE_PROFILE: return "profile-scan";
        }
        return "unknown";
}

/* Local dirname helper (POSIX dirname() mutates its argument). */
static char *dirname_of(const char *path)
{
        const char *slash = strrchr(path, '/');

        if (!slash)
                return shj_strdup(".");
        if (slash == path)
                return shj_strdup("/");
        return shj_strndup(path, (size_t)(slash - path));
}

void shoji_resolver_env_init(struct shoji_resolver_env *env, const char *store_override)
{
        memset(env, 0, sizeof(*env));
        env->store_override = store_override;
        env->env_store_path = getenv("SHOJI_STORE_PATH");
        if (strlen(SHOJI_DEFAULT_STORE) > 0)
                env->builtin_store = SHOJI_DEFAULT_STORE;
        env->config_home = getenv("XDG_CONFIG_HOME");
        env->config_dirs = getenv("XDG_CONFIG_DIRS");
        env->home = getenv("HOME");
        env->user = getenv("USER");
        env->profile_roots = getenv("SHOJI_PROFILE_ROOTS");
}

char *shoji_default_profile_roots(const struct shoji_resolver_env *env)
{
        struct shj_sbuf b;
        const char *home = env->home;
        const char *user = env->user && *env->user ? env->user : "default";

        shj_sbuf_init(&b);
        if (home && *home) {
                shj_sbuf_addf(&b, "%s/.nix-profile", home);
                shj_sbuf_addch(&b, ':');
                shj_sbuf_addf(&b, "%s/.local/state/nix/profiles/profile", home);
                shj_sbuf_addch(&b, ':');
        }
        shj_sbuf_addf(&b, "/etc/profiles/per-user/%s", user);
        shj_sbuf_addch(&b, ':');
        shj_sbuf_addf(&b, "/nix/var/nix/profiles/per-user/%s/profile", user);
        shj_sbuf_addch(&b, ':');
        shj_sbuf_add(&b, "/run/current-system");
        return shj_sbuf_detach(&b);
}

/* Consider a candidate shell.qml path: it must exist after canonicalization
 * and look like Shoji (heuristic content check on bare layout candidates is
 * applied by the caller; this only checks existence). */
static int try_candidate(const char *candidate, char **out_qml, char **out_dir)
{
        char *real;

        if (!shj_is_regular_file(candidate))
                return -1;
        real = shj_realpath_safe(candidate);
        if (!real)
                return -1;
        if (out_dir) {
                char *raw_dir = dirname_of(candidate);
                char *dir = shj_realpath_safe(raw_dir);

                free(raw_dir);
                if (dir) {
                        *out_dir = dir;
                } else {
                        free(real);
                        return -1;
                }
        }
        *out_qml = real;
        return 0;
}

/* Check that a shell.qml mentions the Shoji QML namespace. Bare profile
 * layouts (share/quickshell/shell.qml) could belong to any shell, so we
 * verify the file actually looks like Shoji before trusting it. */
static int looks_like_shoji(const char *qml)
{
        size_t len = 0;
        char *text = shj_read_file(qml, &len);
        int ok = 0;

        if (!text)
                return 0;
        ok = strstr(text, "import qs.Commons") != NULL ||
             strstr(text, "import qs.Island") != NULL;
        free(text);
        return ok;
}

int shoji_canonicalize_store_path(const char *raw, char **out_qml, char **out_dir)
{
        if (!raw || !*raw)
                return -1;

        if (shj_is_dir(raw)) {
                char *join = shj_path_join(raw, "shell.qml");
                int r = try_candidate(join, out_qml, out_dir);

                free(join);
                return r;
        }
        if (shj_is_regular_file(raw)) {
                const char *base = shj_basename(raw);
                char *real_qml, *real_dir;

                if (strcmp(base, "shell.qml") != 0) {
                        shj_msg("store path override points at '%s'; expected a directory "
                                "or shell.qml", raw);
                        return -1;
                }
                real_qml = shj_realpath_safe(raw);
                if (!real_qml)
                        return -1;
                {
                        char *dir = dirname_of(raw);

                        real_dir = shj_realpath_safe(dir);
                        free(dir);
                }
                if (!real_dir) {
                        free(real_qml);
                        return -1;
                }
                *out_qml = real_qml;
                *out_dir = real_dir;
                return 0;
        }
        /* Path does not exist (or is neither file nor directory). */
        return -1;
}

static int resolve_from(const char *raw, enum shoji_store_source source,
                        const char *detail, struct shoji_store *out)
{
        char *qml = NULL, *dir = NULL;

        if (shoji_canonicalize_store_path(raw, &qml, &dir) != 0)
                return -1;

        out->shell_qml = qml;
        out->dir = dir;
        out->source = source;
        out->source_name = source_name(source);
        out->source_detail = detail ? shj_strdup(detail) : NULL;
        return 0;
}

static int resolve_config_links(const struct shoji_resolver_env *env, struct shoji_store *out)
{
        char *dirs[9];
        int n = 0;
        int i;
        int found = -1;

        if (env->config_home && *env->config_home)
                dirs[n++] = shj_strcat(2, env->config_home, "/quickshell");
        else if (env->home && *env->home)
                dirs[n++] = shj_strcat(2, env->home, "/.config/quickshell");

        if (env->config_dirs && *env->config_dirs) {
                char *dup = shj_strdup(env->config_dirs);
                char *tok, *save = NULL;

                for (tok = dup; tok && n < 9; tok = strtok_r(tok, ":", &save)) {
                        char *dir = shj_strcat(2, tok, "/quickshell");

                        dirs[n++] = dir;
                        tok = NULL;
                }
                free(dup);
        } else {
                if (n < 9)
                        dirs[n++] = shj_strdup("/etc/xdg/quickshell");
        }

        for (i = 0; i < n && found != 0; i++) {
                char *candidate = shj_path_join(dirs[i], "shoji/shell.qml");
                char *detail = shj_strcat(2, dirs[i], "/shoji");

                found = resolve_from(candidate, SHOJI_STORE_CONFIG_LINK, detail, out);
                free(candidate);
                free(detail);
        }
        for (i = 0; i < n; i++)
                free(dirs[i]);
        return found;
}

static int resolve_profiles(const struct shoji_resolver_env *env, struct shoji_store *out)
{
        char *roots;
        char *dup;
        char *tok, *save = NULL;
        int found = -1;

        if (env->profile_roots && *env->profile_roots)
                roots = shj_strdup(env->profile_roots);
        else
                roots = shoji_default_profile_roots(env);

        dup = roots;
        for (tok = dup; found != 0 && (tok = strtok_r(tok, ":", &save)); tok = NULL) {
                static const char *layouts[] = {
                        "share/quickshell/shoji/shell.qml",
                        "etc/xdg/quickshell/shoji/shell.qml",
                        NULL,
                };
                int i;
                char *detail = shj_strdup(tok);

                for (i = 0; layouts[i] && found != 0; i++) {
                        char *candidate = shj_path_join(tok, layouts[i]);

                        if (shj_is_regular_file(candidate))
                                found = resolve_from(candidate, SHOJI_STORE_PROFILE, detail, out);
                        free(candidate);
                }

                /* Bare layout: <root>/share/quickshell/shell.qml. Only trust it
                 * when the file content identifies it as Shoji. */
                if (found != 0) {
                        char *candidate = shj_path_join(tok, "share/quickshell/shell.qml");

                        if (shj_is_regular_file(candidate) && looks_like_shoji(candidate))
                                found = resolve_from(candidate, SHOJI_STORE_PROFILE, detail, out);
                        free(candidate);
                }

                free(detail);
        }
        free(dup);
        return found;
}

int shoji_resolve_store(const struct shoji_resolver_env *env, struct shoji_store *out)
{
        memset(out, 0, sizeof(*out));

        if (env->store_override && *env->store_override)
                return resolve_from(env->store_override, SHOJI_STORE_EXPLICIT, "--store", out);

        if (env->env_store_path && *env->env_store_path)
                return resolve_from(env->env_store_path, SHOJI_STORE_ENV, "$SHOJI_STORE_PATH", out);

        if (env->builtin_store && *env->builtin_store)
                return resolve_from(env->builtin_store, SHOJI_STORE_BUILTIN,
                                    "SHOJI_DEFAULT_STORE (compile-time)", out);

        if (resolve_config_links(env, out) == 0)
                return 0;

        if (resolve_profiles(env, out) == 0)
                return 0;

        return -1;
}

void shoji_store_free(struct shoji_store *store)
{
        if (!store)
                return;
        free(store->shell_qml);
        free(store->dir);
        free(store->source_detail);
        memset(store, 0, sizeof(*store));
}
