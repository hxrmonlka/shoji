#define _POSIX_C_SOURCE 200809L

#include "settings.h"
#include "cli.h"
#include "dispatch.h"
#include "exitcodes.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define SETTINGS_CONS_MAX 512

static int settings_call(struct shoji_context *ctx, const struct shoji_options *opts,
                         const char *function, char *const args[], int argc,
                         struct shoji_pipeline *pl, char **out)
{
        shoji_pipeline_run_fast(ctx, opts, 1, pl);
        if (pl->exit_code != SHOJI_EXIT_OK)
                return pl->exit_code;
        return shoji_dispatch_call_capture(ctx, pl, "settings", function, args, argc, out);
}

static const struct shj_json *payload_array(const struct shj_json *root, const char *key)
{
        const struct shj_json *v = shj_json_get(root, key);

        if (!v || v->type != SHOJI_JSON_ARRAY)
                return NULL;
        return v;
}

static struct shj_json *parse_payload(const char *out, const char *what,
                                      const struct shj_json **categories,
                                      const struct shj_json **settings,
                                      int require_both)
{
        struct shj_json *root;
        const struct shj_json *cats = NULL;
        const struct shj_json *rows = NULL;

        *categories = NULL;
        *settings = NULL;
        if (!out || !*out) {
                shj_msg("settings %s returned no data from the shell", what);
                return NULL;
        }
        root = shj_json_parse(out, NULL);
        if (!root) {
                shj_msg("settings %s returned data that is not valid JSON", what);
                return NULL;
        }
        if (root->type != SHOJI_JSON_OBJECT) {
                shj_msg("settings %s returned unexpected JSON (expected an object)", what);
                shj_json_free(root);
                return NULL;
        }
        if (require_both) {
                cats = payload_array(root, "categories");
                rows = payload_array(root, "settings");
                if (!cats || !rows) {
                        shj_msg("settings %s returned unexpected JSON "
                                "(expected categories and settings arrays)", what);
                        shj_json_free(root);
                        return NULL;
                }
        }
        *categories = cats;
        *settings = rows;
        return root;
}

int shoji_settings_category_matches(const struct shj_json *categories, const char *filter)
{
        const struct shj_json *c;

        if (!filter || !*filter)
                return 1;
        if (!categories)
                return 0;
        for (c = categories->items; c; c = c->next) {
                const char *id = shj_json_str(shj_json_get(c, "id"), NULL);
                const char *title = shj_json_str(shj_json_get(c, "title"), NULL);

                if (id && strcasecmp(id, filter) == 0)
                        return 1;
                if (title && strcasecmp(title, filter) == 0)
                        return 1;
        }
        return 0;
}

char *shoji_settings_resolve_category(const struct shj_json *categories, const char *filter)
{
        const struct shj_json *c;

        if (!filter || !*filter)
                return NULL;
        if (!categories)
                return NULL;
        for (c = categories->items; c; c = c->next) {
                const char *id = shj_json_str(shj_json_get(c, "id"), NULL);
                const char *title = shj_json_str(shj_json_get(c, "title"), NULL);

                if ((id && strcasecmp(id, filter) == 0) ||
                    (title && strcasecmp(title, filter) == 0))
                        return shj_strdup(id ? id : "");
        }
        return NULL;
}

const struct shj_json *shoji_settings_find_entry(const struct shj_json *entries,
                                                 const char *key)
{
        const struct shj_json *e;

        if (!entries || entries->type != SHOJI_JSON_ARRAY || !key)
                return NULL;
        for (e = entries->items; e; e = e->next)
                if (strcmp(shj_json_str(shj_json_get(e, "key"), ""), key) == 0)
                        return e;
        return NULL;
}

char *shoji_settings_display_value(const struct shj_json *v)
{
        struct shj_sbuf b;

        shj_sbuf_init(&b);
        if (!v) {
                shj_sbuf_add(&b, "null");
        } else {
                switch (v->type) {
                case SHOJI_JSON_NULL:
                        shj_sbuf_add(&b, "null");
                        break;
                case SHOJI_JSON_BOOL:
                        shj_sbuf_add(&b, v->boolean ? "true" : "false");
                        break;
                case SHOJI_JSON_NUMBER: {
                        char tmp[40];

                        shj_json_number_str(tmp, sizeof(tmp), v->number);
                        shj_sbuf_add(&b, tmp);
                        break;
                }
                case SHOJI_JSON_STRING:
                        shj_sbuf_add(&b, v->string ? v->string : "");
                        break;
                default: {
                        char *c = shj_json_emit(v, 0, 0);

                        shj_sbuf_add(&b, c ? c : "null");
                        free(c);
                        break;
                }
                }
        }
        return shj_sbuf_detach(&b);
}

void shoji_settings_entry_constraints(const struct shj_json *entry, char *buf, size_t size)
{
        const char *type = shj_json_str(shj_json_get(entry, "type"), "int");
        struct shj_sbuf b;

        buf[0] = '\0';
        shj_sbuf_init(&b);
        if (strcmp(type, "choice") == 0) {
                const struct shj_json *opts = shj_json_get(entry, "options");
                const struct shj_json *o;

                if (opts && opts->type == SHOJI_JSON_ARRAY) {
                        for (o = opts->items; o; o = o->next) {
                                const char *value = shj_json_str(o, NULL);

                                if (!value)
                                        continue;
                                if (b.len)
                                        shj_sbuf_addch(&b, '|');
                                shj_sbuf_add(&b, value);
                        }
                }
        } else if (strcmp(type, "int") == 0) {
                struct shj_json *mn = shj_json_get(entry, "min");
                struct shj_json *mx = shj_json_get(entry, "max");
                struct shj_json *st = shj_json_get(entry, "step");
                char tmp[40];

                if (mn && mx && mn->type == SHOJI_JSON_NUMBER && mx->type == SHOJI_JSON_NUMBER) {
                        shj_json_number_str(tmp, sizeof(tmp), mn->number);
                        shj_sbuf_add(&b, tmp);
                        shj_sbuf_add(&b, "..");
                        shj_json_number_str(tmp, sizeof(tmp), mx->number);
                        shj_sbuf_add(&b, tmp);
                        if (st && st->type == SHOJI_JSON_NUMBER) {
                                shj_sbuf_add(&b, " step ");
                                shj_json_number_str(tmp, sizeof(tmp), st->number);
                                shj_sbuf_add(&b, tmp);
                        }
                }
        }
        if (b.len >= size)
                b.len = size - 1;
        memcpy(buf, b.s, b.len);
        buf[b.len] = '\0';
        shj_sbuf_free(&b);
}

static size_t display_width(const struct shj_json *v)
{
        char *s = shoji_settings_display_value(v);
        size_t n = strlen(s);

        free(s);
        return n;
}

static int row_selected(const struct shj_json *e, const char *category_id)
{
        if (!category_id)
                return 1;
        return strcmp(shj_json_str(shj_json_get(e, "category"), ""), category_id) == 0;
}

static void print_list_table(const struct shj_json *settings, const char *category_id)
{
        struct shj_sbuf b;
        const struct shj_json *e;
        size_t w_key = strlen("KEY"), w_cat = strlen("CATEGORY"), w_type = strlen("TYPE");
        size_t w_def = strlen("DEFAULT"), w_val = strlen("CURRENT"), w_cons = strlen("CONSTRAINTS");
        int any = 0;

        for (e = settings->items; e; e = e->next) {
                char cons[SETTINGS_CONS_MAX];

                if (!row_selected(e, category_id))
                        continue;
                any = 1;
                w_key = w_key > strlen(shj_json_str(shj_json_get(e, "key"), ""))
                            ? w_key : strlen(shj_json_str(shj_json_get(e, "key"), ""));
                w_cat = w_cat > strlen(shj_json_str(shj_json_get(e, "category"), ""))
                            ? w_cat : strlen(shj_json_str(shj_json_get(e, "category"), ""));
                w_type = w_type > strlen(shj_json_str(shj_json_get(e, "type"), "int"))
                             ? w_type : strlen(shj_json_str(shj_json_get(e, "type"), "int"));
                w_def = w_def > display_width(shj_json_get(e, "default"))
                            ? w_def : display_width(shj_json_get(e, "default"));
                w_val = w_val > display_width(shj_json_get(e, "value"))
                            ? w_val : display_width(shj_json_get(e, "value"));
                shoji_settings_entry_constraints(e, cons, sizeof(cons));
                w_cons = w_cons > strlen(cons) ? w_cons : strlen(cons);
        }
        if (!any) {
                printf("(no matching settings)\n");
                return;
        }

        shj_sbuf_init(&b);
        shj_sbuf_addf(&b, "%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %s\n",
                      (int)w_key, "KEY", (int)w_cat, "CATEGORY", (int)w_type, "TYPE",
                      (int)w_def, "DEFAULT", (int)w_val, "CURRENT", (int)w_cons,
                      "CONSTRAINTS", "DESCRIPTION");
        for (e = settings->items; e; e = e->next) {
                const char *type = shj_json_str(shj_json_get(e, "type"), "int");
                char *def;
                char *val;
                char cons[SETTINGS_CONS_MAX];
                const char *desc = shj_json_str(shj_json_get(e, "description"), "");
                const char *key;
                const char *cat;

                if (!row_selected(e, category_id))
                        continue;
                key = shj_json_str(shj_json_get(e, "key"), "");
                cat = shj_json_str(shj_json_get(e, "category"), "");
                def = shoji_settings_display_value(shj_json_get(e, "default"));
                val = shoji_settings_display_value(shj_json_get(e, "value"));
                shoji_settings_entry_constraints(e, cons, sizeof(cons));
                shj_sbuf_addf(&b, "%-*s  %-*s  %-*s  %-*s  %-*s  %-*s  %s\n",
                              (int)w_key, key, (int)w_cat, cat, (int)w_type, type,
                              (int)w_def, def, (int)w_val, val, (int)w_cons, cons, desc);
                free(def);
                free(val);
        }
        fputs(b.s, stdout);
        shj_sbuf_free(&b);
}

static void print_list_json(const struct shj_json *categories, const struct shj_json *settings,
                            const char *category_id)
{
        struct shj_sbuf b;
        const struct shj_json *e;
        int first = 1;

        shj_sbuf_init(&b);
        shj_sbuf_add(&b, "{\"categories\":");
        shj_json_emit_value(&b, categories, 0, 0, 0);
        shj_sbuf_add(&b, ",\"settings\":[");
        for (e = settings->items; e; e = e->next) {
                if (!row_selected(e, category_id))
                        continue;
                if (!first)
                        shj_sbuf_addch(&b, ',');
                first = 0;
                shj_json_emit_value(&b, e, 0, 0, 0);
        }
        shj_sbuf_add(&b, "]}\n");
        fputs(b.s, stdout);
        shj_sbuf_free(&b);
}

int shoji_cmd_settings_list(struct shoji_context *ctx, const struct shoji_options *opts,
                            const char *category)
{
        struct shoji_pipeline pl;
        struct shj_json *root;
        const struct shj_json *categories = NULL;
        const struct shj_json *settings = NULL;
        char *out = NULL;
        char *category_id = NULL;
        int code;

        code = settings_call(ctx, opts, "list", NULL, 0, &pl, &out);
        shoji_pipeline_release(&pl);
        if (code != SHOJI_EXIT_OK) {
                free(out);
                return code;
        }

        root = parse_payload(out, "list", &categories, &settings, 1);
        if (!root) {
                free(out);
                return SHOJI_EXIT_INTERNAL;
        }

        if (category && *category) {
                category_id = shoji_settings_resolve_category(categories, category);
                if (!category_id) {
                        struct shj_sbuf b;
                        const struct shj_json *c;
                        int first = 1;

                        shj_msg("unknown setting category '%s'", category);
                        shj_sbuf_init(&b);
                        for (c = categories->items; c; c = c->next) {
                                const char *id = shj_json_str(shj_json_get(c, "id"), NULL);

                                if (!id)
                                        continue;
                                shj_sbuf_addf(&b, "%s%s", first ? "" : ", ", id);
                                first = 0;
                        }
                        shj_hint("valid categories: %s", b.s);
                        shj_sbuf_free(&b);
                        shj_json_free(root);
                        free(out);
                        return SHOJI_EXIT_USAGE;
                }
        }

        if (opts->json)
                print_list_json(categories, settings, category_id);
        else
                print_list_table(settings, category_id);

        free(category_id);
        shj_json_free(root);
        free(out);
        return SHOJI_EXIT_OK;
}

static int emit_object_command(struct shoji_context *ctx, const struct shoji_options *opts,
                               const char *function, const char *what)
{
        struct shoji_pipeline pl;
        struct shj_json *root;
        const struct shj_json *categories = NULL;
        const struct shj_json *settings = NULL;
        char *out = NULL;
        char *text;
        int code;

        code = settings_call(ctx, opts, function, NULL, 0, &pl, &out);
        shoji_pipeline_release(&pl);
        if (code != SHOJI_EXIT_OK) {
                free(out);
                return code;
        }

        root = parse_payload(out, what, &categories, &settings, 0);
        if (!root) {
                free(out);
                return SHOJI_EXIT_INTERNAL;
        }

        text = shj_json_emit(root, 1, 1);
        if (!text) {
                shj_json_free(root);
                free(out);
                return SHOJI_EXIT_INTERNAL;
        }
        fputs(text, stdout);
        fputc('\n', stdout);
        free(text);
        shj_json_free(root);
        free(out);
        return SHOJI_EXIT_OK;
}

int shoji_cmd_settings_dump(struct shoji_context *ctx, const struct shoji_options *opts)
{
        return emit_object_command(ctx, opts, "dump", "dump");
}

int shoji_cmd_settings_export(struct shoji_context *ctx, const struct shoji_options *opts)
{
        return emit_object_command(ctx, opts, "exportOverrides", "export");
}

static void report_unknown_setting(const char *key)
{
        shj_msg("unknown setting '%s'", key);
        shj_hint("run 'shoji settings list' to list the available settings");
}

static void report_invalid_value(const struct shj_json *entry, const char *key)
{
        const char *type = shj_json_str(shj_json_get(entry, "type"), "int");
        char cons[SETTINGS_CONS_MAX];

        shoji_settings_entry_constraints(entry, cons, sizeof(cons));
        if (strcmp(type, "choice") == 0)
                shj_msg("invalid value for '%s': expected one of %s", key,
                        cons[0] ? cons : "(no options declared)");
        else if (strcmp(type, "bool") == 0)
                shj_msg("invalid value for '%s': expected a boolean (true/false)", key);
        else if (strcmp(type, "int") == 0)
                shj_msg("invalid value for '%s': expected a number%s%s", key,
                        cons[0] ? " in " : "", cons[0] ? cons : "");
        else
                shj_msg("invalid value for '%s': expected a string", key);
        shj_hint("run 'shoji settings list' to inspect the declared constraints");
}

int shoji_cmd_settings_get(struct shoji_context *ctx, const struct shoji_options *opts,
                           const char *key)
{
        struct shoji_pipeline pl;
        char *args[1];
        char *out = NULL;
        int code;

        args[0] = (char *)key;
        code = settings_call(ctx, opts, "get", args, 1, &pl, &out);
        if (code != SHOJI_EXIT_OK) {
                shoji_pipeline_release(&pl);
                free(out);
                return code;
        }
        if (out && *out) {
                printf("%s\n", out);
                free(out);
                shoji_pipeline_release(&pl);
                return SHOJI_EXIT_OK;
        }
        free(out);
        {
                char *list_out = NULL;
                struct shj_json *root;
                const struct shj_json *categories = NULL;
                const struct shj_json *settings = NULL;
                int list_code;

                list_code = shoji_dispatch_call_capture(ctx, &pl, "settings", "list",
                                                        NULL, 0, &list_out);
                shoji_pipeline_release(&pl);
                if (list_code != SHOJI_EXIT_OK) {
                        free(list_out);
                        return list_code;
                }
                root = parse_payload(list_out, "list", &categories, &settings, 1);
                if (!root) {
                        free(list_out);
                        return SHOJI_EXIT_INTERNAL;
                }
                if (shoji_settings_find_entry(settings, key)) {
                        printf("\n");
                        code = SHOJI_EXIT_OK;
                } else {
                        report_unknown_setting(key);
                        code = SHOJI_EXIT_BADIPC;
                }
                shj_json_free(root);
                free(list_out);
        }
        return code;
}

int shoji_cmd_settings_set(struct shoji_context *ctx, const struct shoji_options *opts,
                           const char *key, const char *value)
{
        struct shoji_pipeline pl;
        char *args[2];
        char *out = NULL;
        int code;

        args[0] = (char *)key;
        args[1] = (char *)value;
        code = settings_call(ctx, opts, "set", args, 2, &pl, &out);
        if (code != SHOJI_EXIT_OK) {
                shoji_pipeline_release(&pl);
                free(out);
                return code;
        }
        if (out && strcmp(out, "true") == 0) {
                printf("%s\n", out);
                free(out);
                shoji_pipeline_release(&pl);
                return SHOJI_EXIT_OK;
        }
        if (out && strcmp(out, "false") == 0) {
                char *list_out = NULL;
                struct shj_json *root;
                const struct shj_json *categories = NULL;
                const struct shj_json *settings = NULL;
                int list_code;

                list_code = shoji_dispatch_call_capture(ctx, &pl, "settings", "list",
                                                        NULL, 0, &list_out);
                shoji_pipeline_release(&pl);
                free(out);
                if (list_code != SHOJI_EXIT_OK) {
                        free(list_out);
                        return list_code;
                }
                root = parse_payload(list_out, "list", &categories, &settings, 1);
                if (!root) {
                        free(list_out);
                        return SHOJI_EXIT_INTERNAL;
                }
                {
                        const struct shj_json *entry = shoji_settings_find_entry(settings, key);

                        if (entry)
                                report_invalid_value(entry, key);
                        else
                                report_unknown_setting(key);
                        code = SHOJI_EXIT_BADIPC;
                }
                shj_json_free(root);
                free(list_out);
                return code;
        }
        shoji_pipeline_release(&pl);
        shj_msg("settings set returned unexpected data from the shell");
        free(out);
        return SHOJI_EXIT_FAILED;
}
