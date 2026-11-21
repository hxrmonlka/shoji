/*
 * shoji-cli -- generation-aware Shoji store path resolution.
 *
 * Shoji's configuration is immutable in the Nix store. The CLI must decide
 * which Shoji store path belongs to the *active* generation, then compare it
 * against the configuration a running quickshell instance actually loaded.
 *
 * Resolution sources, in documented precedence order:
 *
 *   1. --store PATH             explicit CLI override
 *   2. SHOJI_STORE_PATH         runtime environment override (testing,
 *                               custom deployments)
 *   3. SHOJI_DEFAULT_STORE      compile-time reference baked in by the
 *                               packaging derivation (Lumina): -DSHOJI_DEFAULT_STORE="..."
 *   4. Active config link       $XDG_CONFIG_HOME/quickshell/shoji/shell.qml
 *                               (plus XDG_CONFIG_DIRS), as installed by
 *                               Home Manager home.file links or activation
 *                               scripts. Symlinks resolve to the store path.
 *   5. Profile scan             active system / Home Manager profiles:
 *                                 $HOME/.nix-profile
 *                                 $HOME/.local/state/nix/profiles/profile
 *                                 /etc/profiles/per-user/$USER
 *                                 /nix/var/nix/profiles/per-user/$USER/profile
 *                                 /run/current-system          (last resort)
 *                               Candidate layouts inside each root:
 *                                 share/quickshell/shoji/shell.qml
 *                                 etc/xdg/quickshell/shoji/shell.qml
 *                               SHOJI_PROFILE_ROOTS (colon-separated) replaces
 *                               the default roots when set.
 *
 * /run/current-system is deliberately LAST: Shoji may be installed through
 * Home Manager rather than the NixOS system profile.
 *
 * All resolved paths are canonicalized with realpath(3) and must point to an
 * existing regular shell.qml file (a directory argument gets "/shell.qml"
 * appended). Resolution never invokes nix eval -- it is cheap enough to run
 * for every IPC command.
 */
#ifndef SHOJI_RESOLVER_H
#define SHOJI_RESOLVER_H

/* Which precedence level produced the result. */
enum shoji_store_source {
	SHOJI_STORE_EXPLICIT,   /* --store */
	SHOJI_STORE_ENV,        /* SHOJI_STORE_PATH */
	SHOJI_STORE_BUILTIN,    /* SHOJI_DEFAULT_STORE (compile-time) */
	SHOJI_STORE_CONFIG_LINK,/* XDG config dirs */
	SHOJI_STORE_PROFILE,    /* profile scan */
};

struct shoji_store {
	char *shell_qml;        /* canonical path to shell.qml (must exist) */
	char *dir;              /* directory containing shell_qml */
	enum shoji_store_source source;
	const char *source_name;/* "explicit", "environment", "build-time",
				 * "config-link", "profile-scan" */
	char *source_detail;    /* where it came from (path of link/root) */
};

/* Injectable environment for tests and non-standard setups. */
struct shoji_resolver_env {
	const char *store_override;      /* --store value or NULL */
	const char *env_store_path;      /* $SHOJI_STORE_PATH or NULL */
	const char *builtin_store;       /* compile-time default or NULL */
	const char *config_home;         /* $XDG_CONFIG_HOME or NULL (derived) */
	const char *config_dirs;         /* $XDG_CONFIG_DIRS or NULL */
	const char *home;                /* $HOME or NULL */
	const char *user;                /* $USER or NULL */
	const char *profile_roots;       /* $SHOJI_PROFILE_ROOTS or NULL;
					  * colon-separated, replaces defaults */
};

/* Fill env from the real process environment (store_override from --store). */
void shoji_resolver_env_init(struct shoji_resolver_env *env, const char *store_override);

/* Resolve; returns 0 and fills *out on success, -1 on failure (*out cleared).
 * `out.source_detail` and all strings are malloc'd; free with shoji_store_free(). */
int shoji_resolve_store(const struct shoji_resolver_env *env, struct shoji_store *out);

/* Default profile roots for this process (malloc'd, colon-separated). */
char *shoji_default_profile_roots(const struct shoji_resolver_env *env);

/* Accepts a path to shell.qml, to a config directory, or to a store path
 * root; canonicalizes and appends shell.qml as needed. Returns 0 and sets
 * *out_qml / *out_dir on success. Used by --store and SHOJI_STORE_PATH. */
int shoji_canonicalize_store_path(const char *raw, char **out_qml, char **out_dir);

void shoji_store_free(struct shoji_store *store);

#endif /* SHOJI_RESOLVER_H */
