/*
 * shoji-cli tests -- command-to-IPC mapping.
 *
 * The frozen fixture below was extracted from shell.qml on branch eup
 * (commit aed6ae9). `make check-qml` re-extracts the handlers from shell.qml
 * with tests/qml_ipc.awk and verifies this table never drifts.
 */
#include "testmain.h"
#include "ipctable.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct frozen {
        const char *target;
        const char *function;
};

static const struct frozen frozen_handlers[] = {
        { "screenshot", "fullscreen" }, { "screenshot", "output" },
        { "screenshot", "window" }, { "screenshot", "region" },
        { "awake", "toggle" }, { "awake", "on" }, { "awake", "off" },
        { "lock", "activate" },
        { "spotlight", "toggle" }, { "spotlight", "open" }, { "spotlight", "close" },
        { "wallpaper", "set" }, { "wallpaper", "next" }, { "wallpaper", "previous" },
        { "wallpaper", "random" }, { "wallpaper", "toggle" }, { "wallpaper", "open" },
        { "wallpaper", "close" },
        { "media", "toggle" }, { "media", "open" }, { "media", "close" },
        { "media", "playPause" }, { "media", "next" }, { "media", "previous" },
        { "control", "toggle" }, { "control", "open" }, { "control", "close" },
        { "power", "toggle" }, { "power", "open" }, { "power", "close" },
        { "notifications", "toggleDnd" }, { "notifications", "dnd" },
        { "notifications", "clear" }, { "notifications", "hidePopup" },
        { "osd", "volume" }, { "osd", "brightness" },
        { "settings", "set" }, { "settings", "get" }, { "settings", "reset" },
        { "settings", "reload" }, { "settings", "open" }, { "settings", "close" },
        { "settings", "toggle" },
        { "theme", "scheme" }, { "theme", "mode" }, { "theme", "current" },
        { "theme", "list" }, { "theme", "preview" },
        { "clipboard", "toggle" }, { "clipboard", "open" }, { "clipboard", "close" },
        { "monitor", "toggle" }, { "monitor", "open" }, { "monitor", "close" },
        { "colorpicker", "copy" }, { "colorpicker", "pick" }, { "colorpicker", "gui" },
        { "colorpicker", "cancel" }, { "colorpicker", "hex" },
        { "mic", "toggle" }, { "mic", "mute" }, { "mic", "unmute" }, { "mic", "state" },
        { "island", "toggle" }, { "island", "open" }, { "island", "close" },
        { "island", "tab" },
};

static int table_has(const char *target, const char *function)
{
        for (int i = 0; i < shoji_ipc_table_len; i++)
                if (strcmp(shoji_ipc_table[i].target, target) == 0 &&
                    strcmp(shoji_ipc_table[i].function, function) == 0)
                        return 1;
        return 0;
}

void test_commands(void)
{
        test_section("command-to-IPC mapping");

        CHECK_INT_EQ(shoji_ipc_table_len, (int)(sizeof(frozen_handlers) / sizeof(frozen_handlers[0])),
                      "table covers exactly the frozen handler set");

        for (unsigned i = 0; i < sizeof(frozen_handlers) / sizeof(frozen_handlers[0]); i++) {
                char name[256];

                snprintf(name, sizeof(name), "%s.%s exists in table",
                         frozen_handlers[i].target, frozen_handlers[i].function);
                CHECK(table_has(frozen_handlers[i].target, frozen_handlers[i].function), name);
        }

        /* The task-mandated facade commands dispatch to the documented targets. */
        {
                const struct shoji_cmd *c;

                c = shoji_ipc_table_find("island", "toggle");
                CHECK(c && strcmp(c->target, "island") == 0 && strcmp(c->function, "toggle") == 0,
                      "shoji island toggle -> island.toggle");

                c = shoji_ipc_table_find("media", "play-pause");
                CHECK(c && strcmp(c->target, "media") == 0 && strcmp(c->function, "playPause") == 0,
                      "shoji media play-pause -> media.playPause");

                c = shoji_ipc_table_find("wallpaper", "set");
                CHECK(c && strcmp(c->target, "wallpaper") == 0 && strcmp(c->function, "set") == 0 &&
                      c->arg_count == 1 && c->args[0].type == SHOJI_ARG_STRING,
                      "shoji wallpaper set -> wallpaper.set(string)");

                c = shoji_ipc_table_find("awake", "on");
                CHECK(c && strcmp(c->function, "on") == 0 && c->arg_count == 1 &&
                      c->args[0].type == SHOJI_ARG_INT,
                      "shoji awake on -> awake.on(int)");

                c = shoji_ipc_table_find("notifications", "dnd");
                CHECK(c && strcmp(c->function, "dnd") == 0 && c->arg_count == 1 &&
                      c->args[0].type == SHOJI_ARG_BOOL,
                      "shoji notifications dnd -> notifications.dnd(bool)");

                c = shoji_ipc_table_find("screenshot", "output");
                CHECK(c && c->arg_count == 1 && c->args[0].type == SHOJI_ARG_STRING,
                      "screenshot output takes one string");

                c = shoji_ipc_table_find("lock", "activate");
                CHECK(c && c->arg_count == 0, "shoji lock activate -> lock.activate()");

                c = shoji_ipc_table_find("osd", "volume");
                CHECK(c && c->arg_count == 1 && c->args[0].type == SHOJI_ARG_INT,
                      "osd volume takes one int");
        }

        /* Argument normalization. */
        {
                struct shoji_arg_spec s_str = { SHOJI_ARG_STRING, "name" };
                struct shoji_arg_spec s_int = { SHOJI_ARG_INT, "minutes" };
                struct shoji_arg_spec s_bool = { SHOJI_ARG_BOOL, "on" };
                char *v;

                v = shoji_arg_normalize(&s_str, "/tmp/a b.jpg");
                CHECK_STR_EQ(v, "/tmp/a b.jpg", "string normalization is identity");
                free(v);

                v = shoji_arg_normalize(&s_int, "-5");
                CHECK_STR_EQ(v, "-5", "negative int accepted");
                free(v);

                v = shoji_arg_normalize(&s_int, "2147483648");
                CHECK(!v, "int out of range rejected");
                free(v);

                v = shoji_arg_normalize(&s_int, "3x");
                CHECK(!v, "malformed int rejected");
                free(v);

                v = shoji_arg_normalize(&s_bool, "1");
                CHECK_STR_EQ(v, "true", "bool 1 -> true");
                free(v);

                v = shoji_arg_normalize(&s_bool, "0");
                CHECK_STR_EQ(v, "false", "bool 0 -> false");
                free(v);

                v = shoji_arg_normalize(&s_bool, "off");
                CHECK_STR_EQ(v, "false", "bool off -> false");
                free(v);

                v = shoji_arg_normalize(&s_bool, "2");
                CHECK(!v, "bool 2 rejected (quickshell would take it, we stay strict)");
                free(v);
        }
}
