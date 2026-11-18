/* shoji-cli -- subprocess execution (argv vectors only, never a shell). */
#ifndef SHOJI_PROC_H
#define SHOJI_PROC_H

#include <stddef.h>

/* Result of one subprocess run. `out`/`err` are malloc'd NUL-terminated
 * strings ("" when empty); exit >= 0 is the child exit status (or 128+signal);
 * exit < 0 means the child could not be started (spawn_errno set). */
struct shj_proc_result {
	int exit;
	int spawn_errno;
	char *out;
	char *err;
};

typedef struct shj_proc_result *(*shj_spawn_fn)(const char *const argv[], void *user);

/* The real implementation: fork + execvp(argv[0], argv), stdout/stderr both
 * captured. Applies the configured timeout (SIGKILL on expiry). */
struct shj_proc_result *shj_proc_run(const char *const argv[], void *user);

void shj_proc_result_free(struct shj_proc_result *r);

/* Timeout for child processes, milliseconds. 0 = no timeout. */
void shj_proc_set_timeout_ms(long ms);
long shj_proc_get_timeout_ms(void);

#endif /* SHOJI_PROC_H */
