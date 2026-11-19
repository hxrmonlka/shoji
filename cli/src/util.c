#define _POSIX_C_SOURCE 200809L


#include "exitcodes.h"
#include "util.h"

#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

void shj_msg(const char *fmt, ...)
{
        va_list ap;

        fputs("shoji: ", stderr);
        va_start(ap, fmt);
        vfprintf(stderr, fmt, ap);
        va_end(ap);
        fputc('\n', stderr);
}

void shj_hint(const char *fmt, ...)
{
        va_list ap;

        fputs("shoji: hint: ", stderr);
        va_start(ap, fmt);
        vfprintf(stderr, fmt, ap);
        va_end(ap);
        fputc('\n', stderr);
}

void shj_die(int code, const char *fmt, ...)
{
        va_list ap;

        fputs("shoji: ", stderr);
        va_start(ap, fmt);
        vfprintf(stderr, fmt, ap);
        va_end(ap);
        fputc('\n', stderr);
        exit(code);
}

void *shj_alloc(size_t n)
{
        void *p = calloc(1, n ? n : 1);

        if (!p)
                shj_die(SHOJI_EXIT_INTERNAL, "out of memory");
        return p;
}

void *shj_realloc(void *p, size_t n)
{
        void *q = realloc(p, n ? n : 1);

        if (!q)
                shj_die(SHOJI_EXIT_INTERNAL, "out of memory");
        return q;
}

char *shj_strdup(const char *s)
{
        return shj_strndup(s, strlen(s));
}

char *shj_strndup(const char *s, size_t n)
{
        char *d = shj_alloc(n + 1);

        memcpy(d, s, n);
        d[n] = '\0';
        return d;
}

char *shj_strcat(int n, ...)
{
        va_list ap;
        struct shj_sbuf b;
        int i;

        shj_sbuf_init(&b);
        va_start(ap, n);
        for (i = 0; i < n; i++)
                shj_sbuf_add(&b, va_arg(ap, const char *));
        va_end(ap);
        return shj_sbuf_detach(&b);
}

void shj_sbuf_init(struct shj_sbuf *b)
{
        b->cap = 128;
        b->len = 0;
        b->s = shj_alloc(b->cap);
        b->s[0] = '\0';
}

void shj_sbuf_free(struct shj_sbuf *b)
{
        free(b->s);
        b->s = NULL;
        b->len = b->cap = 0;
}

static void sbuf_reserve(struct shj_sbuf *b, size_t extra)
{
        if (b->len + extra + 1 <= b->cap)
                return;
        while (b->len + extra + 1 > b->cap)
                b->cap *= 2;
        b->s = shj_realloc(b->s, b->cap);
}

void shj_sbuf_addch(struct shj_sbuf *b, char c)
{
        sbuf_reserve(b, 1);
        b->s[b->len++] = c;
        b->s[b->len] = '\0';
}

void shj_sbuf_add(struct shj_sbuf *b, const char *s)
{
        size_t n = strlen(s);

        sbuf_reserve(b, n);
        memcpy(b->s + b->len, s, n);
        b->len += n;
        b->s[b->len] = '\0';
}

void shj_sbuf_addn(struct shj_sbuf *b, const char *s, size_t n)
{
        sbuf_reserve(b, n);
        memcpy(b->s + b->len, s, n);
        b->len += n;
        b->s[b->len] = '\0';
}

void shj_sbuf_addf(struct shj_sbuf *b, const char *fmt, ...)
{
        va_list ap;
        char tmp[512];
        int n;

        va_start(ap, fmt);
        n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
        va_end(ap);
        if (n < 0)
                return;
        if ((size_t)n < sizeof(tmp)) {
                shj_sbuf_add(b, tmp);
                return;
        }
        /* Longer than the scratch buffer: format again with room. */
        {
                char *big = shj_alloc((size_t)n + 1);

                va_start(ap, fmt);
                vsnprintf(big, (size_t)n + 1, fmt, ap);
                va_end(ap);
                shj_sbuf_add(b, big);
                free(big);
        }
}

char *shj_sbuf_detach(struct shj_sbuf *b)
{
        char *s = b->s;

        b->s = NULL;
        b->len = b->cap = 0;
        return s;
}

char *shj_read_all(FILE *f, size_t *len_out)
{
        struct shj_sbuf b;
        char chunk[4096];
        size_t n;

        shj_sbuf_init(&b);
        while ((n = fread(chunk, 1, sizeof(chunk), f)) > 0)
                shj_sbuf_addn(&b, chunk, n);
        if (ferror(f)) {
                shj_sbuf_free(&b);
                return NULL;
        }
        if (len_out)
                *len_out = b.len;
        return shj_sbuf_detach(&b);
}

char *shj_read_file(const char *path, size_t *len_out)
{
        FILE *f = fopen(path, "rb");
        char *out;

        if (!f)
                return NULL;
        out = shj_read_all(f, len_out);
        fclose(f);
        return out;
}

int shj_file_exists(const char *path)
{
        struct stat st;

        return stat(path, &st) == 0;
}

int shj_is_regular_file(const char *path)
{
        struct stat st;

        return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

int shj_is_dir(const char *path)
{
        struct stat st;

        return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

char *shj_realpath_safe(const char *path)
{
        char buf[PATH_MAX];

        if (!realpath(path, buf))
                return NULL;
        return shj_strdup(buf);
}

char *shj_path_join(const char *dir, const char *name)
{
        size_t n = strlen(dir);

        if (n > 0 && dir[n - 1] == '/')
                return shj_strcat(2, dir, name);
        return shj_strcat(3, dir, "/", name);
}

const char *shj_basename(const char *path)
{
        const char *p = strrchr(path, '/');

        return p ? p + 1 : path;
}

int shj_is_flag(const char *s)
{
        return s[0] == '-';
}

char *shj_find_in_path(const char *name, const char *path_override)
{
        const char *path;
        const char *entry;
        const char *end;
        int denied = 0;

        if (!name || !*name) {
                errno = ENOENT;
                return NULL;
        }
        if (strchr(name, '/')) {
                if (shj_is_regular_file(name) && access(name, X_OK) == 0)
                        return shj_strdup(name);
                if (errno != EACCES)
                        errno = ENOENT;
                return NULL;
        }

        path = path_override ? path_override : getenv("PATH");
        if (!path) {
                errno = ENOENT;
                return NULL;
        }
        entry = path;
        for (;;) {
                char *dir;
                char *candidate;
                size_t len;

                end = strchr(entry, ':');
                len = end ? (size_t)(end - entry) : strlen(entry);
                dir = len ? shj_strndup(entry, len) : shj_strdup(".");
                candidate = shj_path_join(dir, name);
                free(dir);
                if (shj_is_regular_file(candidate)) {
                        if (access(candidate, X_OK) == 0)
                                return candidate;
                        if (errno == EACCES)
                                denied = 1;
                }
                free(candidate);
                if (!end)
                        break;
                entry = end + 1;
        }
        errno = denied ? EACCES : ENOENT;
        return NULL;
}
