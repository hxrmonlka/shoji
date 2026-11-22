/* shoji-cli -- minimal JSON parser and writer (enough for quickshell's
 * `qs list -j` and the settings JSON payloads). */
#ifndef SHOJI_JSON_H
#define SHOJI_JSON_H

#include <stddef.h>
#include <stdio.h>

struct shj_sbuf;

enum shj_json_type {
        SHOJI_JSON_NULL,
        SHOJI_JSON_BOOL,
        SHOJI_JSON_NUMBER,
        SHOJI_JSON_STRING,
        SHOJI_JSON_ARRAY,
        SHOJI_JSON_OBJECT,
};

struct shj_json {
        enum shj_json_type type;
        int boolean;
        double number;            /* valid when type == SHOJI_JSON_NUMBER */
        char *string;             /* valid when type == SHOJI_JSON_STRING */
        struct shj_json *items;   /* array/object members; NULL-terminated chain */
        struct shj_json *next;    /* next sibling in arrays/objects */
        char *key;                /* object member key (owned) */
};

/* Parse text; returns NULL on error (with *errpos set to the byte offset). */
struct shj_json *shj_json_parse(const char *text, size_t *errpos);
void shj_json_free(struct shj_json *v);

/* Object lookup; NULL when missing or not an object. */
struct shj_json *shj_json_get(const struct shj_json *obj, const char *key);
/* Safe string access: returns v->string or fallback. */
const char *shj_json_str(const struct shj_json *v, const char *fallback);

void shj_json_number_str(char *buf, size_t size, double d);
void shj_json_emit_value(struct shj_sbuf *b, const struct shj_json *v,
                         int pretty, int indent, int sort_keys);
char *shj_json_emit(const struct shj_json *v, int pretty, int sort_keys);

#endif /* SHOJI_JSON_H */
