/* shoji-cli tests -- command line parsing and argument validation. */
#include "testmain.h"
#include "cli.h"
#include "exitcodes.h"
#include "ipctable.h"

#include <stdlib.h>
#include <string.h>

#define ARGV(...) \
        const char *_tokens[] = { "shoji", __VA_ARGS__, NULL }; \
        ARGV_PREP(_tokens)

#define ARGV0() \
        const char *_tokens[] = { "shoji", NULL }; \
        ARGV_PREP(_tokens)

#define ARGV_PREP(_toks) \
        int _n = (int)(sizeof(_toks) / sizeof(_toks[0])) - 1; \
        char **_argv = calloc((size_t)_n + 1, sizeof(char *)); \
        struct shoji_options _opts; \
        memset(&_opts, 0, sizeof(_opts)); \
        for (int _i = 0; _i < _n; _i++) _argv[_i] = (char *)(_toks)[_i]

#define ARGV_END() free(_argv); shoji_options_free(&_opts)

void test_parser(void)
{
        test_section("argument parsing");

        {
                ARGV("--help");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "--help parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_HELP, "--help kind");
                ARGV_END();
        }
        {
                ARGV("-h");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "-h parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_HELP, "-h kind");
                ARGV_END();
        }
        {
                ARGV("--version");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "--version parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_VERSION, "--version kind");
                ARGV_END();
        }
        {
                ARGV("version");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "version parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_VERSION, "version subcommand");
                ARGV_END();
        }
        {
                ARGV0();
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "bare shoji parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_HELP, "bare shoji prints help");
                ARGV_END();
        }
        {
                ARGV("island", "tab", "calendar");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "island tab parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_FACADE, "island tab is facade");
                CHECK(_opts.facade && strcmp(_opts.facade->function, "tab") == 0,
                      "island tab maps to tab()");
                CHECK_STR_EQ(_opts.facade_args[0], "calendar", "tab argument");
                ARGV_END();
        }
        {
                ARGV("media", "play-pause");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "play-pause parses");
                CHECK_STR_EQ(_opts.facade->function, "playPause", "play-pause -> playPause");
                ARGV_END();
        }
        {
                ARGV("awake", "on", "30");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "awake on parses");
                CHECK_STR_EQ(_opts.facade_args[0], "30", "int argument kept");
                ARGV_END();
        }
        {
                ARGV("awake", "on", "abc");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "awake on rejects non-integer");
                ARGV_END();
        }
        {
                ARGV("awake", "on");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "awake on without argument rejected");
                ARGV_END();
        }
        {
                ARGV("awake", "on", "30", "extra");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "too many facade arguments rejected");
                ARGV_END();
        }
        {
                ARGV("notifications", "dnd", "off");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "dnd off parses");
                CHECK_STR_EQ(_opts.facade_args[0], "false", "bool normalized to false");
                ARGV_END();
        }
        {
                ARGV("notifications", "dnd", "yes");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "dnd yes parses");
                CHECK_STR_EQ(_opts.facade_args[0], "true", "bool yes normalized");
                ARGV_END();
        }
        {
                ARGV("notifications", "dnd", "maybe");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "dnd rejects invalid bool");
                ARGV_END();
        }
        {
                ARGV("wallpaper", "set", "/nix/store/x.jpg");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "wallpaper set parses");
                CHECK_STR_EQ(_opts.facade_args[0], "/nix/store/x.jpg", "path argument kept");
                ARGV_END();
        }
        {
                ARGV("wallpaper", "set", "--", "-weird.jpg");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "-- stops flag parsing");
                CHECK_STR_EQ(_opts.facade_args[0], "-weird.jpg", "dash-prefixed path kept");
                ARGV_END();
        }
        {
                ARGV("bogus");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "unknown command rejected");
                ARGV_END();
        }
        {
                ARGV("island");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "facade group without subcommand rejected");
                ARGV_END();
        }
        {
                ARGV("island", "explode");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "unknown facade subcommand rejected");
                ARGV_END();
        }
        {
                ARGV("instance", "list");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "instance list parses");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_INSTANCE_LIST, "instance list kind");
                ARGV_END();
        }
        {
                ARGV("instance", "reap");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "unknown instance subcommand rejected");
                ARGV_END();
        }
        {
                ARGV("--store", "/nix/store/abc-shoji", "island", "toggle");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "global flag parses");
                CHECK_STR_EQ(_opts.store_override, "/nix/store/abc-shoji", "--store captured");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_FACADE, "command still parsed");
                ARGV_END();
        }
        {
                ARGV("island", "toggle", "--store", "/nix/store/abc-shoji");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK,
                             "global flag after command parses");
                CHECK_STR_EQ(_opts.store_override, "/nix/store/abc-shoji", "--store captured 2");
                ARGV_END();
        }
        {
                ARGV("--instance-id", "abc", "--json", "instance", "current");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK, "multiple flags parse");
                CHECK_STR_EQ(_opts.instance_id, "abc", "--instance-id captured");
                CHECK_INT_EQ(_opts.json, 1, "--json captured");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_INSTANCE_CURRENT, "instance current kind");
                ARGV_END();
        }
        {
                ARGV("--instance-id", "", "instance", "current");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "empty --instance-id rejected rather than treated as omitted");
                ARGV_END();
        }
        {
                ARGV("--store", "-h", "status");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK,
                             "dash-prefixed store value is not treated as help");
                CHECK_STR_EQ(_opts.store_override, "-h", "dash-prefixed store value retained");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_STATUS, "command after dash-prefixed value parsed");
                ARGV_END();
        }
        {
                ARGV("status", "--unknown-flag");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "fixed-arity status rejects extra arguments");
                ARGV_END();
        }
        {
                ARGV("instance", "list", "extra");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "instance list rejects extra arguments");
                ARGV_END();
        }
        {
                ARGV("ipc", "show", "extra");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "ipc show rejects extra arguments");
                ARGV_END();
        }
        {
                ARGV("debug", "map", "extra");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "debug map rejects extra arguments");
                ARGV_END();
        }
        {
                ARGV("ipc", "call", "island", "tab", "calendar", "extra");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK,
                             "raw ipc call accepts extra args");
                CHECK_STR_EQ(_opts.ipc_target, "island", "raw target");
                CHECK_STR_EQ(_opts.ipc_function, "tab", "raw function");
                CHECK_INT_EQ(_opts.ipc_argc, 2, "raw argument count");
                CHECK_STR_EQ(_opts.ipc_args[1], "extra", "raw argument content");
                ARGV_END();
        }
        {
                ARGV("run", "--daemonize", "--no-duplicate", "--verbose");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK,
                             "run accepts Quickshell launch options");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_RUN, "run command kind");
                CHECK_INT_EQ(_opts.run_argc, 3, "run option count");
                CHECK_STR_EQ(_opts.run_args[0], "--daemonize", "run daemonize option");
                CHECK_STR_EQ(_opts.run_args[1], "--no-duplicate", "run no-duplicate option");
                CHECK_STR_EQ(_opts.run_args[2], "--verbose", "run verbose option");
                ARGV_END();
        }
        {
                ARGV("run", "--", "--help");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_OK,
                             "run forwards options after separator");
                CHECK_INT_EQ(_opts.kind, SHOJI_CMD_RUN, "run separator command kind");
                CHECK_STR_EQ(_opts.run_args[0], "--help", "run forwards Quickshell help");
                ARGV_END();
        }
        {
                ARGV("run", "--path", "/tmp/other/shell.qml");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "run rejects conflicting config selectors");
                ARGV_END();
        }
        {
                ARGV("ipc", "call", "island");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "raw ipc call without function rejected");
                ARGV_END();
        }
        {
                ARGV("--store");
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "--store without value rejected");
                ARGV_END();
        }
        {
                ARGV("--unknown-flag", "status");
                /* Unknown flags are passed through as command tokens, so this is a
                 * usage error from the unknown-command path. */
                CHECK_INT_EQ(shoji_parse(_n, _argv, &_opts), SHOJI_EXIT_USAGE,
                             "unknown flag rejected");
                ARGV_END();
        }
}
