/* shoji-cli tests -- minimal JSON parser. */
#include "testmain.h"
#include "json.h"
#include "util.h"

#include <stdlib.h>
#include <string.h>

void test_json(void)
{
        struct shj_json *v;
        size_t errpos = 0;

        test_section("json parser");

        v = shj_json_parse("[]", NULL);
        CHECK(v && v->type == SHOJI_JSON_ARRAY && !v->items, "empty array");
        shj_json_free(v);

        v = shj_json_parse("[ {\"id\": \"abc\", \"pid\": 42, \"alive\": false}, null ]", NULL);
        CHECK(v && v->type == SHOJI_JSON_ARRAY, "array of objects");
        CHECK(v->items && v->items->type == SHOJI_JSON_OBJECT, "first item is object");
        {
                struct shj_json *o = v->items;

                CHECK_STR_EQ(shj_json_str(shj_json_get(o, "id"), NULL), "abc", "id field");
                {
                        struct shj_json *pid = shj_json_get(o, "pid");

                        CHECK(pid && pid->type == SHOJI_JSON_NUMBER && pid->number == 42,
                              "pid field");
                }
                {
                        struct shj_json *al = shj_json_get(o, "alive");

                        CHECK(al && al->type == SHOJI_JSON_BOOL && al->boolean == 0,
                              "alive field");
                }
        }
        {
                struct shj_json *second = v->items->next;

                CHECK(second && second->type == SHOJI_JSON_NULL, "second item is null");
        }
        shj_json_free(v);

        v = shj_json_parse("\"path with \\\"quote\\\" and \\u00e9\"", NULL);
        CHECK(v && v->type == SHOJI_JSON_STRING, "string escapes");
        CHECK_STR_EQ(v->string, "path with \"quote\" and \xc3\xa9", "\\u escape decoded");
        shj_json_free(v);

        v = shj_json_parse("{ \"a\": [1, 2, 3], \"b\": \"x\" }", NULL);
        CHECK(v && v->type == SHOJI_JSON_OBJECT, "object with nested array");
        CHECK(shj_json_get(v, "a")->items->next->number == 2, "nested array index 1");
        shj_json_free(v);

        v = shj_json_parse("{\"launch_time\": \"2026-11-17T09:41:22\"}", NULL);
        CHECK_STR_EQ(shj_json_str(shj_json_get(v, "launch_time"), NULL),
                     "2026-11-17T09:41:22", "iso launch time");
        shj_json_free(v);

        /* Malformed inputs must fail without crashing. */
        v = shj_json_parse("{", &errpos);
        CHECK(!v && errpos > 0, "unterminated object fails");
        shj_json_free(v);

        v = shj_json_parse("[1, 2", NULL);
        CHECK(!v, "unterminated array fails");
        shj_json_free(v);

        v = shj_json_parse("{\"a\" 1}", NULL);
        CHECK(!v, "missing colon fails");
        shj_json_free(v);

        v = shj_json_parse("nul", NULL);
        CHECK(!v, "truncated literal fails");
        shj_json_free(v);

        v = shj_json_parse("", NULL);
        CHECK(!v, "empty input fails");
        shj_json_free(v);

        v = shj_json_parse("[] trailing", NULL);
        CHECK(!v, "trailing garbage fails");
        shj_json_free(v);

        v = shj_json_parse("{\"x\":\"line\nbreak\"}", NULL);
        CHECK(!v, "unescaped control characters in strings are rejected");
        shj_json_free(v);

        v = shj_json_parse("[{\"n\":01}]", NULL);
        CHECK(!v, "leading-zero JSON number is rejected");
        shj_json_free(v);
        v = shj_json_parse("[{\"n\":1.}]", NULL);
        CHECK(!v, "JSON fraction requires at least one digit");
        shj_json_free(v);
        v = shj_json_parse("[{\"n\":-.5}]", NULL);
        CHECK(!v, "JSON number requires an integer part before fraction");
        shj_json_free(v);
        v = shj_json_parse("[{\"n\":1.5},{\"n\":1e2},{\"n\":-1}]", NULL);
        CHECK(v && v->type == SHOJI_JSON_ARRAY, "valid JSON number forms are accepted");
        shj_json_free(v);

        v = shj_json_parse("\"bad \\x escape\"", NULL);
        CHECK(!v, "invalid escape fails");
        shj_json_free(v);

        v = shj_json_parse("\"abc\\u0000def\"", NULL);
        CHECK(!v, "decoded NUL rejected because JSON strings are exposed as C strings");
        shj_json_free(v);

        v = shj_json_parse("\"surrogate \\ud83d\\ude00\"", NULL);
        CHECK(v && v->type == SHOJI_JSON_STRING, "surrogate pair accepted");
        CHECK_STR_EQ(v->string, "surrogate \xf0\x9f\x98\x80", "surrogate pair decoded to utf-8");
        shj_json_free(v);
}
