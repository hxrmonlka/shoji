#ifndef SHOJI_SETTINGS_H
#define SHOJI_SETTINGS_H

#include "json.h"

struct shoji_context;
struct shoji_options;

int shoji_cmd_settings_list(struct shoji_context *ctx, const struct shoji_options *opts,
                            const char *category);
int shoji_cmd_settings_dump(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_settings_export(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_settings_get(struct shoji_context *ctx, const struct shoji_options *opts,
                           const char *key);
int shoji_cmd_settings_set(struct shoji_context *ctx, const struct shoji_options *opts,
                           const char *key, const char *value);

int shoji_settings_category_matches(const struct shj_json *categories, const char *filter);
char *shoji_settings_resolve_category(const struct shj_json *categories, const char *filter);
const struct shj_json *shoji_settings_find_entry(const struct shj_json *entries,
                                                 const char *key);
char *shoji_settings_display_value(const struct shj_json *v);
void shoji_settings_entry_constraints(const struct shj_json *entry, char *buf, size_t size);

#endif /* SHOJI_SETTINGS_H */
