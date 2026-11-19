#define _POSIX_C_SOURCE 200809L

#include "json.h"
#include "util.h"

#include <stdlib.h>
#include <string.h>

struct parser {
        const char *p;
        size_t off;
        size_t len;
        size_t err;
        int depth;
};

#define SHOJI_JSON_MAX_DEPTH 64

static struct shj_json *parse_value(struct parser *ps);

static struct shj_json *node(enum shj_json_type t)
{
        struct shj_json *v = shj_alloc(sizeof(*v));

        v->type = t;
        return v;
}

void shj_json_free(struct shj_json *v)
{
        while (v) {
                struct shj_json *next = v->next;

                /* v->string doubles as nothing for objects; keys and strings
                 * are the only owned allocations besides child arrays. */
                if (v->type == SHOJI_JSON_STRING)
                        free(v->string);
                if (v->key)
                        free(v->key);
                if (v->type == SHOJI_JSON_ARRAY || v->type == SHOJI_JSON_OBJECT)
                        shj_json_free(v->items);
                free(v);
                v = next;
        }
}

static void skip_ws(struct parser *ps)
{
        while (ps->off < ps->len) {
                char c = ps->p[ps->off];

                if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
                        ps->off++;
                else
                        break;
        }
}

static int peek(struct parser *ps)
{
        if (ps->off >= ps->len)
                return -1;
        return (unsigned char)ps->p[ps->off];
}

static int advance(struct parser *ps)
{
        if (ps->off >= ps->len) {
                ps->err = ps->len;
                return -1;
        }
        return (unsigned char)ps->p[ps->off++];
}

static int fail(struct parser *ps, size_t at)
{
        if (!ps->err)
                ps->err = at ? at : 1;
        return -1;
}

static void append_utf8(struct shj_sbuf *b, unsigned int cp)
{
        char enc[4];

        if (cp < 0x80) {
                shj_sbuf_addch(b, (char)cp);
        } else if (cp < 0x800) {
                enc[0] = (char)(0xC0 | (cp >> 6));
                enc[1] = (char)(0x80 | (cp & 0x3F));
                shj_sbuf_addn(b, enc, 2);
        } else if (cp < 0x10000) {
                enc[0] = (char)(0xE0 | (cp >> 12));
                enc[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
                enc[2] = (char)(0x80 | (cp & 0x3F));
                shj_sbuf_addn(b, enc, 3);
        } else {
                enc[0] = (char)(0xF0 | (cp >> 18));
                enc[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
                enc[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
                enc[3] = (char)(0x80 | (cp & 0x3F));
                shj_sbuf_addn(b, enc, 4);
        }
}

static int hex4(struct parser *ps, unsigned int *out)
{
        unsigned int v = 0;
        int i;

        for (i = 0; i < 4; i++) {
                int c = advance(ps);

                if (c >= '0' && c <= '9')
                        v = v * 16 + (unsigned)(c - '0');
                else if (c >= 'a' && c <= 'f')
                        v = v * 16 + (unsigned)(c - 'a' + 10);
                else if (c >= 'A' && c <= 'F')
                        v = v * 16 + (unsigned)(c - 'A' + 10);
                else
                        return -1;
        }
        *out = v;
        return 0;
}

static char *parse_string_raw(struct parser *ps)
{
        struct shj_sbuf b;

        if (advance(ps) != '"')
                return NULL;

        shj_sbuf_init(&b);
        for (;;) {
                int c = advance(ps);

                if (c == -1)
                        goto bad;
                if (c == '"')
                        return shj_sbuf_detach(&b);
                if (c == '\\') {
                        int e = advance(ps);
                        unsigned int cp;

                        switch (e) {
                        case '"': shj_sbuf_addch(&b, '"'); break;
                        case '\\': shj_sbuf_addch(&b, '\\'); break;
                        case '/': shj_sbuf_addch(&b, '/'); break;
                        case 'b': shj_sbuf_addch(&b, '\b'); break;
                        case 'f': shj_sbuf_addch(&b, '\f'); break;
                        case 'n': shj_sbuf_addch(&b, '\n'); break;
                        case 'r': shj_sbuf_addch(&b, '\r'); break;
                        case 't': shj_sbuf_addch(&b, '\t'); break;
                        case 'u':
                                if (hex4(ps, &cp) != 0)
                                        goto bad;
                                /* Surrogate pair handling. */
                                if (cp >= 0xD800 && cp <= 0xDBFF) {
                                        unsigned int lo;
                                        int d1 = advance(ps);
                                        int d2 = advance(ps);

                                        if (d1 != '\\' || d2 != 'u')
                                                goto bad;
                                        if (hex4(ps, &lo) != 0)
                                                goto bad;
                                        if (lo < 0xDC00 || lo > 0xDFFF)
                                                goto bad;
                                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                                        goto bad;
                                }
                                /* The parser's public string representation
                                 * is NUL-terminated. Reject U+0000 rather than
                                 * silently truncating decoded identifiers. */
                                if (cp == 0)
                                        goto bad;
                                append_utf8(&b, cp);
                                break;
                        default:
                                goto bad;
                        }
                } else {
                        shj_sbuf_addch(&b, (char)c);
                }
        }
bad:
        shj_sbuf_free(&b);
        return NULL;
}

static struct shj_json *parse_number(struct parser *ps)
{
        size_t start = ps->off;
        int isnum = 0;
        double d;
        char *end;
        struct shj_json *v;

        if (peek(ps) == '-')
                ps->off++;
        while (ps->off < ps->len) {
                char c = ps->p[ps->off];

                if ((c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' ||
                    c == '+' || c == '-') {
                        isnum = 1;
                        ps->off++;
                } else {
                        break;
                }
        }
        if (!isnum)
                return fail(ps, start), NULL;

        d = strtod(ps->p + start, &end);
        if (end != ps->p + ps->off)
                return fail(ps, start), NULL;

        v = node(SHOJI_JSON_NUMBER);
        v->number = d;
        return v;
}

static struct shj_json *parse_object(struct parser *ps)
{
        struct shj_json *obj = node(SHOJI_JSON_OBJECT);
        struct shj_json **tail = &obj->items;

        if (advance(ps) != '{')
                return fail(ps, ps->off - 1), NULL;

        skip_ws(ps);
        if (peek(ps) == '}') {
                ps->off++;
                return obj;
        }
        for (;;) {
                char *key;
                struct shj_json *val;

                skip_ws(ps);
                if (peek(ps) != '"') {
                        fail(ps, ps->off);
                        break;
                }
                key = parse_string_raw(ps);
                if (!key) {
                        fail(ps, ps->off);
                        break;
                }
                skip_ws(ps);
                if (advance(ps) != ':') {
                        free(key);
                        fail(ps, ps->off - 1);
                        break;
                }
                val = parse_value(ps);
                if (!val) {
                        free(key);
                        break;
                }
                val->key = key;
                *tail = val;
                tail = &val->next;

                skip_ws(ps);
                if (peek(ps) == ',') {
                        ps->off++;
                        continue;
                }
                if (peek(ps) == '}') {
                        ps->off++;
                        return obj;
                }
                fail(ps, ps->off);
                break;
        }
        shj_json_free(obj);
        return NULL;
}

static struct shj_json *parse_array(struct parser *ps)
{
        struct shj_json *arr = node(SHOJI_JSON_ARRAY);
        struct shj_json **tail = &arr->items;

        if (advance(ps) != '[')
                return fail(ps, ps->off - 1), NULL;

        skip_ws(ps);
        if (peek(ps) == ']') {
                ps->off++;
                return arr;
        }
        for (;;) {
                struct shj_json *val = parse_value(ps);

                if (!val)
                        break;
                *tail = val;
                tail = &val->next;

                skip_ws(ps);
                if (peek(ps) == ',') {
                        ps->off++;
                        continue;
                }
                if (peek(ps) == ']') {
                        ps->off++;
                        return arr;
                }
                fail(ps, ps->off);
                break;
        }
        shj_json_free(arr);
        return NULL;
}

static struct shj_json *parse_value(struct parser *ps)
{
        int c;

        if (++ps->depth > SHOJI_JSON_MAX_DEPTH)
                return fail(ps, ps->off), NULL;

        skip_ws(ps);
        c = peek(ps);

        if (c == '{') {
                struct shj_json *v = parse_object(ps);
                ps->depth--;
                return v;
        }
        if (c == '[') {
                struct shj_json *v = parse_array(ps);
                ps->depth--;
                return v;
        }
        if (c == '"') {
                char *s = parse_string_raw(ps);
                struct shj_json *v;

                if (!s)
                        return fail(ps, ps->off), NULL;
                v = node(SHOJI_JSON_STRING);
                v->string = s;
                ps->depth--;
                return v;
        }
        if (c == 't') {
                if (ps->off + 4 <= ps->len && memcmp(ps->p + ps->off, "true", 4) == 0) {
                        ps->off += 4;
                        {
                                struct shj_json *v = node(SHOJI_JSON_BOOL);
                                v->boolean = 1;
                                ps->depth--;
                                return v;
                        }
                }
                return fail(ps, ps->off), NULL;
        }
        if (c == 'f') {
                if (ps->off + 5 <= ps->len && memcmp(ps->p + ps->off, "false", 5) == 0) {
                        ps->off += 5;
                        {
                                struct shj_json *v = node(SHOJI_JSON_BOOL);
                                v->boolean = 0;
                                ps->depth--;
                                return v;
                        }
                }
                return fail(ps, ps->off), NULL;
        }
        if (c == 'n') {
                if (ps->off + 4 <= ps->len && memcmp(ps->p + ps->off, "null", 4) == 0) {
                        ps->off += 4;
                        {
                                struct shj_json *v = node(SHOJI_JSON_NULL);
                                ps->depth--;
                                return v;
                        }
                }
                return fail(ps, ps->off), NULL;
        }
        if (c == '-' || (c >= '0' && c <= '9')) {
                struct shj_json *v = parse_number(ps);
                ps->depth--;
                return v;
        }
        return fail(ps, ps->off), NULL;
}

struct shj_json *shj_json_parse(const char *text, size_t *errpos)
{
        struct parser ps = { text, 0, strlen(text), 0, 0 };
        struct shj_json *v = parse_value(&ps);

        if (!v) {
                if (errpos)
                        *errpos = ps.err;
                return NULL;
        }
        skip_ws(&ps);
        if (ps.off != ps.len) {
                fail(&ps, ps.off);
                shj_json_free(v);
                if (errpos)
                        *errpos = ps.err;
                return NULL;
        }
        return v;
}

struct shj_json *shj_json_get(const struct shj_json *obj, const char *key)
{
        struct shj_json *it;

        if (!obj || obj->type != SHOJI_JSON_OBJECT)
                return NULL;
        for (it = obj->items; it; it = it->next)
                if (it->key && strcmp(it->key, key) == 0)
                        return it;
        return NULL;
}

const char *shj_json_str(const struct shj_json *v, const char *fallback)
{
        if (v && v->type == SHOJI_JSON_STRING && v->string)
                return v->string;
        return fallback;
}
