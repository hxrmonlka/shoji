/* shoji-cli -- small shared utilities: allocation, string buffers, paths. */
#ifndef SHOJI_UTIL_H
#define SHOJI_UTIL_H

#include <stddef.h>
#include <stdio.h>

/* Print a formatted message to stderr with the "shoji: " prefix. */
void shj_msg(const char *fmt, ...);
/* Like shj_msg(), prefixed with "shoji: hint: ". */
void shj_hint(const char *fmt, ...);
/* Print a formatted error and exit with the given code. */
void shj_die(int code, const char *fmt, ...);

/* Allocation that aborts on failure. */
void *shj_alloc(size_t n);
void *shj_realloc(void *p, size_t n);
char *shj_strdup(const char *s);
char *shj_strndup(const char *s, size_t n);
/* Concatenate n strings; returns malloc'd memory. */
char *shj_strcat(int n, ...);

/* Growable string buffer. Always NUL-terminated. */
struct shj_sbuf {
        char *s;
        size_t len;
        size_t cap;
};

void shj_sbuf_init(struct shj_sbuf *b);
void shj_sbuf_free(struct shj_sbuf *b);
void shj_sbuf_add(struct shj_sbuf *b, const char *s);
void shj_sbuf_addn(struct shj_sbuf *b, const char *s, size_t n);
void shj_sbuf_addch(struct shj_sbuf *b, char c);
void shj_sbuf_addf(struct shj_sbuf *b, const char *fmt, ...);
/* Detach the buffer contents (caller frees). */
char *shj_sbuf_detach(struct shj_sbuf *b);

/* Read a whole stream into a malloc'd NUL-terminated buffer; NULL on error. */
char *shj_read_all(FILE *f, size_t *len_out);
/* Read a whole file; NULL on error. */
char *shj_read_file(const char *path, size_t *len_out);

/* Path helpers (all return malloc'd memory unless noted). */
int shj_file_exists(const char *path);       /* exists and is any type   */
int shj_is_regular_file(const char *path);   /* exists and is regular    */
int shj_is_dir(const char *path);            /* exists and is directory  */
/* realpath(3) result; NULL if the path does not resolve. */
char *shj_realpath_safe(const char *path);
/* dir + "/" + name; dir may end in "/" already. */
char *shj_path_join(const char *dir, const char *name);
/* Filename of the last path component; points inside `path`. */
const char *shj_basename(const char *path);
/* True if path starts with '-'. */
int shj_is_flag(const char *s);

/* Find `name` in $PATH (or the given PATH value when non-NULL).
 * Returns malloc'd absolute path, or NULL. */
char *shj_find_in_path(const char *name, const char *path_override);

/* Version string of shoji-cli (compile-time overridable). */
#ifndef SHOJI_CLI_VERSION
#define SHOJI_CLI_VERSION "0.1.0"
#endif

#endif /* SHOJI_UTIL_H */
