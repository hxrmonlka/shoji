#define _POSIX_C_SOURCE 200809L

#include "cli.h"
#include "util.h"
#include "exitcodes.h"

#include <stdlib.h>
#include <string.h>

void shoji_options_free(struct shoji_options *opts)
{
        int i;

        free(opts->store_override);
        free(opts->qs_bin);
        free(opts->instance_id);
        for (i = 0; i < opts->run_argc; i++)
                free(opts->run_args[i]);
        free(opts->run_args);
        free(opts->ipc_target);
        free(opts->ipc_function);
        for (i = 0; i < opts->ipc_argc; i++)
                free(opts->ipc_args[i]);
        free(opts->ipc_args);
        free(opts->facade_args[0]);
        free(opts->facade_args[1]);
        memset(opts, 0, sizeof(*opts));
}

/* Returns 0 on success, -1 when the value is missing. */
static int set_flag_value(char **slot, const char *value, const char *flag)
{
        if (!value) {
                shj_msg("option %s requires a value", flag);
                return -1;
        }
        if (strcmp(flag, "--instance-id") == 0 && !*value) {
                shj_msg("option %s requires a non-empty value", flag);
                return -1;
        }
        free(*slot);
        *slot = shj_strdup(value);
        return 0;
}

/* Extract global flags from argv; the remaining tokens are stored in *rest
 * (malloc'd, NULL-terminated). Returns 0 on success, -1 on a malformed flag.
 * *rest_out is published before the first possible failure so the caller can
 * free it without reading an uninitialized pointer. */
static int extract_global_flags(int argc, char **argv, const char ***rest_out,
                                int *rest_count, struct shoji_options *opts,
                                int *want_help, int *want_version)
{
        const char **rest = shj_alloc(sizeof(char *) * (size_t)(argc + 1));
        int n = 0;
        int i;
        int flags_done = 0;

        *rest_out = rest;
        *rest_count = 0;

        for (i = 1; i < argc; i++) {
                const char *tok = argv[i];

                if (flags_done || !shj_is_flag(tok) || strcmp(tok, "-") == 0) {
                        rest[n++] = tok;
                        continue;
                }
                if (strcmp(tok, "--") == 0) {
                        flags_done = 1;
                        continue;
                }
                if (strcmp(tok, "--json") == 0) {
                        opts->json = 1;
                        continue;
                }
                if (strcmp(tok, "--help") == 0 || strcmp(tok, "-h") == 0) {
                        *want_help = 1;
                        continue;
                }
                if (strcmp(tok, "--version") == 0 || strcmp(tok, "-V") == 0) {
                        *want_version = 1;
                        continue;
                }
                if (strcmp(tok, "--store") == 0) {
                        if (set_flag_value(&opts->store_override,
                                           i + 1 < argc ? argv[++i] : NULL, "--store") != 0)
                                return -1;
                        continue;
                }
                if (strcmp(tok, "--qs") == 0) {
                        if (set_flag_value(&opts->qs_bin,
                                           i + 1 < argc ? argv[++i] : NULL, "--qs") != 0)
                                return -1;
                        continue;
                }
                if (strcmp(tok, "--instance-id") == 0) {
                        if (set_flag_value(&opts->instance_id,
                                           i + 1 < argc ? argv[++i] : NULL,
                                           "--instance-id") != 0)
                                return -1;
                        continue;
                }
                /* Not a recognized global flag: treat as a command token. */
                rest[n++] = tok;
        }
        rest[n] = NULL;
        *rest_out = rest;
        *rest_count = n;
        return 0;
}

static int run_arg_is_config_selector(const char *arg)
{
        return strcmp(arg, "-p") == 0 || strncmp(arg, "-p", 2) == 0 ||
               strcmp(arg, "--path") == 0 || strncmp(arg, "--path=", 7) == 0 ||
               strcmp(arg, "-c") == 0 || strncmp(arg, "-c", 2) == 0 ||
               strcmp(arg, "--config") == 0 || strncmp(arg, "--config=", 9) == 0 ||
               strcmp(arg, "-m") == 0 || strncmp(arg, "-m", 2) == 0 ||
               strcmp(arg, "--manifest") == 0 || strncmp(arg, "--manifest=", 11) == 0;
}

static int facade_fill_args(struct shoji_options *opts, const struct shoji_cmd *cmd,
                            const char **rest, int n)
{
        if (n - 2 != cmd->arg_count) {
                shj_msg("command '%s %s' expects %d argument%s, got %d",
                        cmd->group, cmd->name, cmd->arg_count,
                        cmd->arg_count == 1 ? "" : "s", n - 2);
                return -1;
        }
        for (int a = 0; a < cmd->arg_count; a++) {
                char *norm = shoji_arg_normalize(&cmd->args[a], rest[2 + a]);

                if (!norm)
                        return -1;
                opts->facade_args[a] = norm;
        }
        return 0;
}

static int settings_managed_kind(const char *sub)
{
        if (strcmp(sub, "list") == 0)
                return SHOJI_CMD_SETTINGS_LIST;
        if (strcmp(sub, "dump") == 0)
                return SHOJI_CMD_SETTINGS_DUMP;
        if (strcmp(sub, "export") == 0)
                return SHOJI_CMD_SETTINGS_EXPORT;
        if (strcmp(sub, "get") == 0)
                return SHOJI_CMD_SETTINGS_GET;
        if (strcmp(sub, "set") == 0)
                return SHOJI_CMD_SETTINGS_SET;
        return SHOJI_CMD_NONE;
}

static int parse_settings_group(struct shoji_options *opts, const char **rest, int n)
{
        int skind = n >= 2 ? settings_managed_kind(rest[1]) : SHOJI_CMD_NONE;

        if (skind == SHOJI_CMD_NONE) {
                const struct shoji_cmd *cmd = n >= 2 ? shoji_ipc_table_find(rest[0], rest[1])
                                                     : NULL;

                if (!cmd) {
                        shj_msg("missing or unknown subcommand for 'settings' (expected "
                                "list, dump, export, get, set, reset, reload, open, close "
                                "or toggle)");
                        return SHOJI_EXIT_USAGE;
                }
                opts->kind = SHOJI_CMD_FACADE;
                opts->facade = cmd;
                if (facade_fill_args(opts, cmd, rest, n) != 0)
                        return SHOJI_EXIT_USAGE;
                return 0;
        }

        switch (skind) {
        case SHOJI_CMD_SETTINGS_LIST:
                if (n > 3) {
                        shj_msg("usage: shoji settings list [category]");
                        return SHOJI_EXIT_USAGE;
                }
                opts->kind = skind;
                if (n == 3)
                        opts->facade_args[0] = shj_strdup(rest[2]);
                break;

        case SHOJI_CMD_SETTINGS_DUMP:
        case SHOJI_CMD_SETTINGS_EXPORT:
                if (n != 2) {
                        shj_msg("usage: shoji settings %s", rest[1]);
                        return SHOJI_EXIT_USAGE;
                }
                opts->kind = skind;
                break;

        case SHOJI_CMD_SETTINGS_GET:
                if (n != 3) {
                        shj_msg("usage: shoji settings get <key>");
                        return SHOJI_EXIT_USAGE;
                }
                opts->kind = skind;
                opts->facade_args[0] = shj_strdup(rest[2]);
                break;

        case SHOJI_CMD_SETTINGS_SET:
                if (n != 4) {
                        shj_msg("usage: shoji settings set <key> <value>");
                        return SHOJI_EXIT_USAGE;
                }
                opts->kind = skind;
                opts->facade_args[0] = shj_strdup(rest[2]);
                opts->facade_args[1] = shj_strdup(rest[3]);
                break;

        default:
                shj_msg("unknown settings subcommand '%s'", rest[1]);
                return SHOJI_EXIT_USAGE;
        }
        return 0;
}

int shoji_parse(int argc, char **argv, struct shoji_options *opts)
{
        const char **rest;
        int n;
        int want_help = 0, want_version = 0;

        memset(opts, 0, sizeof(*opts));

        if (extract_global_flags(argc, argv, &rest, &n, opts,
                                 &want_help, &want_version) != 0) {
                free(rest);
                return SHOJI_EXIT_USAGE;
        }

        if (want_help) {
                opts->kind = SHOJI_CMD_HELP;
                free(rest);
                return 0;
        }
        if (want_version && n == 0) {
                opts->kind = SHOJI_CMD_VERSION;
                free(rest);
                return 0;
        }

        if (n == 0) {
                opts->kind = SHOJI_CMD_HELP;
                free(rest);
                return 0;
        }

        if (strcmp(rest[0], "help") == 0) {
                if (n != 1) goto bad_arity;
                opts->kind = SHOJI_CMD_HELP;
        } else if (strcmp(rest[0], "version") == 0) {
                if (n != 1) goto bad_arity;
                opts->kind = SHOJI_CMD_VERSION;
        } else if (strcmp(rest[0], "run") == 0) {
                for (int i = 1; i < n; i++) {
                        if (run_arg_is_config_selector(rest[i])) {
                                shj_msg("'shoji run' controls Quickshell configuration selection; "
                                        "use --store instead of %s", rest[i]);
                                free(rest);
                                return SHOJI_EXIT_USAGE;
                        }
                }
                opts->kind = SHOJI_CMD_RUN;
                opts->run_argc = n - 1;
                opts->run_args = shj_alloc(sizeof(char *) * (size_t)(opts->run_argc + 1));
                for (int i = 0; i < opts->run_argc; i++)
                        opts->run_args[i] = shj_strdup(rest[i + 1]);
        } else if (strcmp(rest[0], "status") == 0) {
                if (n != 1) goto bad_arity;
                opts->kind = SHOJI_CMD_STATUS;
        } else if (strcmp(rest[0], "doctor") == 0) {
                if (n != 1) goto bad_arity;
                opts->kind = SHOJI_CMD_DOCTOR;
        } else if (strcmp(rest[0], "kill") == 0) {
                opts->kind = SHOJI_CMD_KILL;
                for (int i = 1; i < n; i++) {
                        if (strcmp(rest[i], "--all") != 0) {
                                shj_msg("usage: shoji kill [--all]");
                                free(rest);
                                return SHOJI_EXIT_USAGE;
                        }
                        opts->kill_all = 1;
                }
                if (opts->kill_all && opts->instance_id) {
                        shj_msg("'shoji kill --all' and '--instance-id' are mutually exclusive");
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
        } else if (strcmp(rest[0], "instance") == 0) {
                if (n < 2) {
                        shj_msg("missing subcommand for 'instance' (expected list, current or inspect)");
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
                if (n != 2) goto bad_arity;
                if (strcmp(rest[1], "list") == 0)
                        opts->kind = SHOJI_CMD_INSTANCE_LIST;
                else if (strcmp(rest[1], "current") == 0)
                        opts->kind = SHOJI_CMD_INSTANCE_CURRENT;
                else if (strcmp(rest[1], "inspect") == 0)
                        opts->kind = SHOJI_CMD_INSTANCE_INSPECT;
                else {
                        shj_msg("unknown instance subcommand '%s'", rest[1]);
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
        } else if (strcmp(rest[0], "ipc") == 0) {
                if (n < 2) {
                        shj_msg("missing subcommand for 'ipc' (expected 'show' or 'call')");
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
                if (strcmp(rest[1], "show") == 0) {
                        if (n != 2) goto bad_arity;
                        opts->kind = SHOJI_CMD_IPC_SHOW;
                } else if (strcmp(rest[1], "call") == 0) {
                        if (n < 4) {
                                shj_msg("usage: shoji ipc call <target> <function> [arguments...]");
                                free(rest);
                                return SHOJI_EXIT_USAGE;
                        }
                        opts->kind = SHOJI_CMD_IPC_CALL;
                        opts->ipc_target = shj_strdup(rest[2]);
                        opts->ipc_function = shj_strdup(rest[3]);
                        opts->ipc_argc = n - 4;
                        opts->ipc_args = shj_alloc(sizeof(char *) * (size_t)(opts->ipc_argc + 1));
                        for (int i = 0; i < opts->ipc_argc; i++)
                                opts->ipc_args[i] = shj_strdup(rest[4 + i]);
                } else {
                        shj_msg("unknown ipc subcommand '%s'", rest[1]);
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
        } else if (strcmp(rest[0], "debug") == 0) {
                if (n != 2 || strcmp(rest[1], "map") != 0) {
                        shj_msg("usage: shoji debug map");
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
                opts->kind = SHOJI_CMD_DEBUG_MAP;
        } else if (strcmp(rest[0], "settings") == 0) {
                int pcode = parse_settings_group(opts, rest, n);

                if (pcode != 0) {
                        free(rest);
                        return pcode;
                }
        } else if (shoji_ipc_table_find(rest[0], n >= 2 ? rest[1] : "") != NULL) {
                const struct shoji_cmd *cmd = shoji_ipc_table_find(rest[0], rest[1]);

                opts->kind = SHOJI_CMD_FACADE;
                opts->facade = cmd;
                if (facade_fill_args(opts, cmd, rest, n) != 0) {
                        free(rest);
                        return SHOJI_EXIT_USAGE;
                }
        } else if (shoji_ipc_table_group_exists(rest[0])) {
                /* Known group but missing/unknown subcommand. */
                shj_msg("missing or unknown subcommand for '%s' (see 'shoji help')", rest[0]);
                free(rest);
                return SHOJI_EXIT_USAGE;
        } else {
                shj_msg("unknown command '%s'", rest[0]);
                free(rest);
                return SHOJI_EXIT_USAGE;
        }

        free(rest);
        return 0;

bad_arity:
        shj_msg("command '%s' does not accept extra arguments", rest[0]);
        free(rest);
        return SHOJI_EXIT_USAGE;
}

void shoji_print_version(void)
{
        printf("shoji-cli %s\n", SHOJI_CLI_VERSION);
}

void shoji_print_help(void)
{
        printf("shoji-cli %s -- command line interface for the Shoji Quickshell shell\n\n",
               SHOJI_CLI_VERSION);
        printf("usage: shoji [global options] <command> [arguments]\n\n");
        printf("global options:\n");
        printf("  --store PATH        resolve Shoji from an explicit configuration path\n");
        printf("                      (directory or shell.qml; overrides every other source)\n");
        printf("  --instance-id ID    operate on the given quickshell instance id\n");
        printf("                      (unique prefix of the id, as `qs -i` accepts)\n");
        printf("  --qs PATH           quickshell executable (default: qs on $PATH;\n");
        printf("                      env: SHOJI_QS_BIN)\n");
        printf("  --json              machine-readable output for status and instance list\n");
        printf("  -h, --help          show this help\n");
        printf("  -V, --version       show the version\n\n");
        printf("general:\n");
        printf("  shoji run [qs options]        launch the resolved Shoji configuration\n");
        printf("  shoji status                  expected store path, running instances, match verdict\n");
        printf("  shoji doctor                  check CLI, quickshell, store path, instance, IPC\n");
        printf("  shoji kill                    stop the newest instance of the expected configuration\n");
        printf("  shoji kill --all              stop every instance of the expected configuration\n\n");
        printf("instance management:\n");
        printf("  shoji instance list           all running quickshell instances (marked by match)\n");
        printf("  shoji instance current        the instance shoji would dispatch to\n");
        printf("  shoji instance inspect        details of the selected instance\n\n");
        printf("ipc inspection:\n");
        printf("  shoji ipc show                targets and functions of the selected instance\n");
        printf("  shoji ipc call <t> <f> [...]  raw pass-through to `qs ipc call`\n\n");
        printf("facade commands (mapped 1:1 onto shell.qml IpcHandlers):\n");
        printf("  island    toggle|open|close|tab <name>\n");
        printf("  wallpaper toggle|open|close|set <path>|next|previous|random\n");
        printf("  media     toggle|open|close|play-pause|next|previous|player-next|player-previous\n");
        printf("  control   toggle|open|close\n");
        printf("  power     toggle|open|close\n");
        printf("  spotlight toggle|open|close\n");
        printf("  lock      activate\n");
        printf("  screenshot fullscreen|window|region|output <name>\n");
        printf("  awake     toggle|on <minutes>|off\n");
        printf("  mic       toggle|mute|unmute|state\n");
        printf("  notifications clear|toggle-dnd|dnd <true|false>|hide-popup\n");
        printf("  osd       volume <steps>|brightness <steps>\n");
        printf("  clipboard toggle|open|close\n");
        printf("  monitor   toggle|open|close\n");
        printf("  colorpicker copy|pick|gui|cancel|hex\n");
        printf("  settings  list [category]|dump|export|get <key>|set <key> <value>|\n");
        printf("            reset|reload|open|close|toggle\n");
        printf("  theme     scheme <name>|mode <name>|current|list|preview\n\n");
        printf("examples:\n");
        printf("  shoji island tab calendar\n");
        printf("  shoji wallpaper set /path/to/image.jpg\n");
        printf("  shoji awake on 30\n");
        printf("  shoji settings list features\n");
        printf("  shoji settings set pillHeight 48\n");
        printf("  shoji settings dump > effective.json\n");
        printf("  shoji run --daemonize --no-duplicate\n");
        printf("  shoji kill\n");
        printf("  shoji --store /nix/store/…-shoji/status\n");
        printf("  shoji --instance-id abc123 ipc show\n\n");
        printf("exit codes: 0 ok; 1 quickshell failure; 64 usage; 65 bad IPC target/function;\n");
        printf("  66 store path unresolved or missing; 67 no matching instance;\n");
        printf("  68 ambiguous instances; 69 quickshell unavailable; 70 internal error.\n\n");
        printf("see cli/README.md in the Shoji repository for the full reference.\n");
}
