/* shoji-cli -- subprocess execution (argv vectors only, never a shell). */
#ifndef SHOJI_PROC_H
#define SHOJI_PROC_H

#include <stddef.h>

/* Result of one subprocess run. `out`/`err` are malloc'd NUL-terminated
 * strings ("" when empty); exit >= 0 is the child exit status (or 128+signal).
 * exit < 0 is a failure class:
 *   -1  child could not be started (spawn_errno = exec errno)
 *   -2  configured timeout expired during any stage of the lifecycle
 *       (spawn_errno = ETIMEDOUT; partial out/err are preserved)
 *   -3  internal failure while running the child: unexpected poll/read
 *       error or waitpid failure (spawn_errno = errno; partial out/err
 *       are preserved). Callers must treat captured output as incomplete. */
struct shj_proc_result {
        int exit;
        int spawn_errno;
        unsigned truncated; /* SHOJI_TRUNC_* bits; capture hit the 4 MiB cap */
        char *out;
        char *err;
};

/* Failure classes of shj_proc_result::exit (negative values); explicit
 * names instead of bare magic numbers at call sites. */
#define SHJ_PROC_EXIT_SPAWN (-1)
#define SHJ_PROC_EXIT_TIMEOUT (-2)
#define SHJ_PROC_EXIT_INTERNAL (-3)

/* A stream reached SHOJI_PROC_MAX_OUTPUT and further output was discarded
 * while draining continued. The corresponding out/err payload is partial. */
#define SHOJI_TRUNC_OUT 0x1u
#define SHOJI_TRUNC_ERR 0x2u

typedef struct shj_proc_result *(*shj_spawn_fn)(const char *const argv[], void *user);

/* The real implementation: fork + execve(argv[0], argv), stdout/stderr both
 * captured. Bare program names are resolved through PATH without execvp's
 * interpreter fallback. Runs the child in a dedicated process group; timeout
 * cleanup signals that group. Descendants that leave the group (for example by
 * starting a new session) are outside the cancellation guarantee. */
struct shj_proc_result *shj_proc_run(const char *const argv[], void *user);
struct shj_proc_result *shj_proc_run_qs(const char *const argv[], void *user);

void shj_proc_result_free(struct shj_proc_result *r);

/* Timeout for child processes, milliseconds. 0 = no timeout; negative values
 * are rejected by shj_proc_run as an internal configuration error. */
void shj_proc_set_timeout_ms(long ms);
long shj_proc_get_timeout_ms(void);

#endif /* SHOJI_PROC_H */
