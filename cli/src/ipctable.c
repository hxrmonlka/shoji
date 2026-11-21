#define _POSIX_C_SOURCE 200809L

#include "ipctable.h"
#include "util.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

/*
 * Mirrors the IpcHandlers in shell.qml (verified against branch eup).
 * Keep sorted by group, then name.
 */
const struct shoji_cmd shoji_ipc_table[] = {
        /* island ------------------------------------------------------------ */
        { "island", "toggle", "island", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "island", "open", "island", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "island", "close", "island", "close", { { 0, NULL }, { 0, NULL } }, 0 },
        { "island", "tab", "island", "tab", { { SHOJI_ARG_STRING, "name" }, { 0, NULL } }, 1 },

        /* wallpaper --------------------------------------------------------- */
        { "wallpaper", "toggle", "wallpaper", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "wallpaper", "open", "wallpaper", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "wallpaper", "close", "wallpaper", "close", { { 0, NULL }, { 0, NULL } }, 0 },
        { "wallpaper", "set", "wallpaper", "set", { { SHOJI_ARG_STRING, "path" }, { 0, NULL } }, 1 },
        { "wallpaper", "next", "wallpaper", "next", { { 0, NULL }, { 0, NULL } }, 0 },
        { "wallpaper", "previous", "wallpaper", "previous", { { 0, NULL }, { 0, NULL } }, 0 },
        { "wallpaper", "random", "wallpaper", "random", { { 0, NULL }, { 0, NULL } }, 0 },

        /* media ------------------------------------------------------------- */
        { "media", "toggle", "media", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "open", "media", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "close", "media", "close", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "play-pause", "media", "playPause", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "next", "media", "next", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "previous", "media", "previous", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "player-next", "media", "playerNext", { { 0, NULL }, { 0, NULL } }, 0 },
        { "media", "player-previous", "media", "playerPrevious", { { 0, NULL }, { 0, NULL } }, 0 },

        /* control / power --------------------------------------------------- */
        { "control", "toggle", "control", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "control", "open", "control", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "control", "close", "control", "close", { { 0, NULL }, { 0, NULL } }, 0 },
        { "power", "toggle", "power", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "power", "open", "power", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "power", "close", "power", "close", { { 0, NULL }, { 0, NULL } }, 0 },

        /* spotlight --------------------------------------------------------- */
        { "spotlight", "toggle", "spotlight", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "spotlight", "open", "spotlight", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "spotlight", "close", "spotlight", "close", { { 0, NULL }, { 0, NULL } }, 0 },

        /* lock -------------------------------------------------------------- */
        { "lock", "activate", "lock", "activate", { { 0, NULL }, { 0, NULL } }, 0 },

        /* screenshot -------------------------------------------------------- */
        { "screenshot", "fullscreen", "screenshot", "fullscreen", { { 0, NULL }, { 0, NULL } }, 0 },
        { "screenshot", "output", "screenshot", "output", { { SHOJI_ARG_STRING, "name" }, { 0, NULL } }, 1 },
        { "screenshot", "window", "screenshot", "window", { { 0, NULL }, { 0, NULL } }, 0 },
        { "screenshot", "region", "screenshot", "region", { { 0, NULL }, { 0, NULL } }, 0 },

        /* awake ------------------------------------------------------------- */
        { "awake", "toggle", "awake", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "awake", "on", "awake", "on", { { SHOJI_ARG_INT, "minutes" }, { 0, NULL } }, 1 },
        { "awake", "off", "awake", "off", { { 0, NULL }, { 0, NULL } }, 0 },

        /* mic --------------------------------------------------------------- */
        { "mic", "toggle", "mic", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "mic", "mute", "mic", "mute", { { 0, NULL }, { 0, NULL } }, 0 },
        { "mic", "unmute", "mic", "unmute", { { 0, NULL }, { 0, NULL } }, 0 },
        { "mic", "state", "mic", "state", { { 0, NULL }, { 0, NULL } }, 0 },

        /* notifications ----------------------------------------------------- */
        { "notifications", "clear", "notifications", "clear", { { 0, NULL }, { 0, NULL } }, 0 },
        { "notifications", "toggle-dnd", "notifications", "toggleDnd", { { 0, NULL }, { 0, NULL } }, 0 },
        { "notifications", "dnd", "notifications", "dnd", { { SHOJI_ARG_BOOL, "on" }, { 0, NULL } }, 1 },
        { "notifications", "hide-popup", "notifications", "hidePopup", { { 0, NULL }, { 0, NULL } }, 0 },

        /* osd --------------------------------------------------------------- */
        { "osd", "volume", "osd", "volume", { { SHOJI_ARG_INT, "steps" }, { 0, NULL } }, 1 },
        { "osd", "brightness", "osd", "brightness", { { SHOJI_ARG_INT, "steps" }, { 0, NULL } }, 1 },

        /* clipboard / monitor ----------------------------------------------- */
        { "clipboard", "toggle", "clipboard", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "clipboard", "open", "clipboard", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "clipboard", "close", "clipboard", "close", { { 0, NULL }, { 0, NULL } }, 0 },
        { "monitor", "toggle", "monitor", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },
        { "monitor", "open", "monitor", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "monitor", "close", "monitor", "close", { { 0, NULL }, { 0, NULL } }, 0 },

        /* colorpicker ------------------------------------------------------- */
        { "colorpicker", "copy", "colorpicker", "copy", { { 0, NULL }, { 0, NULL } }, 0 },
        { "colorpicker", "pick", "colorpicker", "pick", { { 0, NULL }, { 0, NULL } }, 0 },
        { "colorpicker", "gui", "colorpicker", "gui", { { 0, NULL }, { 0, NULL } }, 0 },
        { "colorpicker", "cancel", "colorpicker", "cancel", { { 0, NULL }, { 0, NULL } }, 0 },
        { "colorpicker", "hex", "colorpicker", "hex", { { 0, NULL }, { 0, NULL } }, 0 },

        /* settings (minimal pass-through; no settings manager here) --------- */
        { "settings", "set", "settings", "set", { { SHOJI_ARG_STRING, "key" }, { SHOJI_ARG_STRING, "value" } }, 2 },
        { "settings", "get", "settings", "get", { { SHOJI_ARG_STRING, "key" }, { 0, NULL } }, 1 },
        { "settings", "reset", "settings", "reset", { { 0, NULL }, { 0, NULL } }, 0 },
        { "settings", "reload", "settings", "reload", { { 0, NULL }, { 0, NULL } }, 0 },
        { "settings", "open", "settings", "open", { { 0, NULL }, { 0, NULL } }, 0 },
        { "settings", "close", "settings", "close", { { 0, NULL }, { 0, NULL } }, 0 },
        { "settings", "toggle", "settings", "toggle", { { 0, NULL }, { 0, NULL } }, 0 },

        /* theme (minimal pass-through) -------------------------------------- */
        { "theme", "scheme", "theme", "scheme", { { SHOJI_ARG_STRING, "name" }, { 0, NULL } }, 1 },
        { "theme", "mode", "theme", "mode", { { SHOJI_ARG_STRING, "name" }, { 0, NULL } }, 1 },
        { "theme", "current", "theme", "current", { { 0, NULL }, { 0, NULL } }, 0 },
        { "theme", "list", "theme", "list", { { 0, NULL }, { 0, NULL } }, 0 },
        { "theme", "preview", "theme", "preview", { { 0, NULL }, { 0, NULL } }, 0 },
};

const int shoji_ipc_table_len = (int)(sizeof(shoji_ipc_table) / sizeof(shoji_ipc_table[0]));

const struct shoji_cmd *shoji_ipc_table_find(const char *group, const char *name)
{
        int i;

        if (!group || !name)
                return NULL;
        for (i = 0; i < shoji_ipc_table_len; i++)
                if (strcmp(shoji_ipc_table[i].group, group) == 0 &&
                    strcmp(shoji_ipc_table[i].name, name) == 0)
                        return &shoji_ipc_table[i];
        return NULL;
}

int shoji_ipc_table_group_exists(const char *group)
{
        int i;

        if (!group)
                return 0;
        for (i = 0; i < shoji_ipc_table_len; i++)
                if (strcmp(shoji_ipc_table[i].group, group) == 0)
                        return 1;
        return 0;
}

char *shoji_arg_normalize(const struct shoji_arg_spec *spec, const char *value)
{
        if (!spec || spec->type == SHOJI_ARG_NONE || !value)
                return NULL;

        if (spec->type == SHOJI_ARG_STRING)
                return shj_strdup(value);

        if (spec->type == SHOJI_ARG_INT) {
                char *end;
                long v;

                errno = 0;
                v = strtol(value, &end, 10);
                if (errno != 0 || end == value || *end != '\0' ||
                    v < INT_MIN || v > INT_MAX) {
                        shj_msg("argument '%s' expects an integer, got '%s'", spec->name, value);
                        return NULL;
                }
                return shj_strdup(value);
        }

        /* SHOJI_ARG_BOOL: quickshell accepts "true"/"false"/integer; normalize
         * the friendly spellings ourselves so keybinds can use on/off. */
        {
                static const char *yes[] = { "true", "1", "yes", "on", "True", "TRUE", NULL };
                static const char *no[] = { "false", "0", "no", "off", "False", "FALSE", NULL };
                int i;

                for (i = 0; yes[i]; i++)
                        if (strcmp(value, yes[i]) == 0)
                                return shj_strdup("true");
                for (i = 0; no[i]; i++)
                        if (strcmp(value, no[i]) == 0)
                                return shj_strdup("false");

                shj_msg("argument '%s' expects a boolean (true/false/on/off), got '%s'",
                        spec->name, value);
                return NULL;
        }
}

void shoji_ipc_table_dump_tsv(void)
{
        int i;

        for (i = 0; i < shoji_ipc_table_len; i++) {
                const struct shoji_cmd *c = &shoji_ipc_table[i];

                printf("%s\t%s\t%s\t%s\t", c->group, c->name, c->target, c->function);
                if (c->arg_count == 0) {
                        printf("-\n");
                        continue;
                }
                for (int a = 0; a < c->arg_count; a++) {
                        const char *t = c->args[a].type == SHOJI_ARG_STRING ? "string"
                                        : c->args[a].type == SHOJI_ARG_INT ? "int"
                                        : "bool";

                        printf("%s%s:%s", a ? "," : "", t, c->args[a].name);
                }
                printf("\n");
        }
}
