#define _POSIX_C_SOURCE 200809L

#include "exitcodes.h"
#include "proc.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define SHOJI_PROC_MAX_OUTPUT (4u * 1024u * 1024u) /* 4 MiB per stream */

static long g_timeout_ms = 10000;

void shj_proc_set_timeout_ms(long ms)
{
        g_timeout_ms = ms;
}

long shj_proc_get_timeout_ms(void)
{
        return g_timeout_ms;
}

struct pipebuf {
        char *data;
        size_t len;
        size_t cap;
        int truncated;
};

static void pb_init(struct pipebuf *b)
{
        b->cap = 4096;
        b->len = 0;
        b->truncated = 0;
        b->data = shj_alloc(b->cap);
        b->data[0] = '\0';
}

static void pb_add(struct pipebuf *b, const char *src, ssize_t n)
{
        size_t need = (size_t)n;

        if (b->len + need > SHOJI_PROC_MAX_OUTPUT) {
                need = b->len >= SHOJI_PROC_MAX_OUTPUT ? 0 : SHOJI_PROC_MAX_OUTPUT - b->len;
                b->truncated = 1;
                if (need == 0)
                        return;
        }
        if (b->len + need + 1 > b->cap) {
                while (b->len + need + 1 > b->cap)
                        b->cap *= 2;
                b->data = shj_realloc(b->data, b->cap);
        }
        memcpy(b->data + b->len, src, need);
        b->len += need;
        b->data[b->len] = '\0';
}

/* Pump both capture pipes concurrently so a child blocked writing one
 * stream cannot deadlock us on the other; returns 0 on success, -1 on
 * timeout. */
static int drain_streams(int out_fd, struct pipebuf *ob, int err_fd, struct pipebuf *eb,
                         long deadline_ms)
{
        int open_out = 1, open_err = 1;

        while (open_out || open_err) {
                struct pollfd fds[2];
                nfds_t n = 0;
                long now;
                struct timespec ts;
                int timeout;
                int r;

                clock_gettime(CLOCK_MONOTONIC, &ts);
                now = ts.tv_sec * 1000 + ts.tv_nsec / 1000000;

                if (deadline_ms <= 0) {
                        timeout = -1;
                } else {
                        timeout = (int)(deadline_ms - now);
                        if (timeout <= 0)
                                return -1;
                }

                if (open_out) {
                        fds[n].fd = out_fd;
                        fds[n].events = POLLIN;
                        fds[n].revents = 0;
                        n++;
                }
                if (open_err) {
                        fds[n].fd = err_fd;
                        fds[n].events = POLLIN;
                        fds[n].revents = 0;
                        n++;
                }

                r = poll(fds, n, timeout);
                if (r < 0) {
                        if (errno == EINTR)
                                continue;
                        break;
                }
                if (r == 0)
                        return -1; /* timed out */

                for (nfds_t i = 0; i < n; i++) {
                        char chunk[8192];
                        ssize_t got;
                        struct pipebuf *b;

                        if (!(fds[i].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)))
                                continue;
                        b = (fds[i].fd == out_fd) ? ob : eb;
                        got = read(fds[i].fd, chunk, sizeof(chunk));
                        if (got == 0) {
                                if (fds[i].fd == out_fd)
                                        open_out = 0;
                                else
                                        open_err = 0;
                                continue;
                        }
                        if (got < 0) {
                                if (errno == EINTR || errno == EAGAIN)
                                        continue;
                                if (fds[i].fd == out_fd)
                                        open_out = 0;
                                else
                                        open_err = 0;
                                continue;
                        }
                        pb_add(b, chunk, got);
                }
        }
        return 0;
}

static int cloexec_pipe(int fds[2])
{
        if (pipe(fds) != 0)
                return -1;
        fcntl(fds[0], F_SETFD, FD_CLOEXEC);
        fcntl(fds[1], F_SETFD, FD_CLOEXEC);
        return 0;
}

struct shj_proc_result *shj_proc_run(const char *const argv[], void *user)
{
        int outfd[2], errfd[2], execfd[2];
        pid_t pid;
        int status = 0;
        long deadline_ms = 0;
        struct timespec ts;
        struct pipebuf ob, eb;
        struct shj_proc_result *res;

        (void)user;

        if (cloexec_pipe(outfd) != 0 || cloexec_pipe(errfd) != 0 ||
            cloexec_pipe(execfd) != 0)
                shj_die(SHOJI_EXIT_INTERNAL, "pipe: %s", strerror(errno));

        clock_gettime(CLOCK_MONOTONIC, &ts);
        if (g_timeout_ms > 0)
                deadline_ms = ts.tv_sec * 1000 + ts.tv_nsec / 1000000 + g_timeout_ms;

        pid = fork();
        if (pid < 0) {
                shj_die(SHOJI_EXIT_INTERNAL, "fork: %s", strerror(errno));
        } else if (pid == 0) {
                /* Child: wire the capture pipes onto stdout/stderr, then exec
                 * with the argv vector untouched (dup2 clears CLOEXEC on the
                 * new descriptors). */
                dup2(outfd[1], STDOUT_FILENO);
                dup2(errfd[1], STDERR_FILENO);
                close(outfd[0]);
                close(outfd[1]);
                close(errfd[0]);
                close(errfd[1]);
                execvp(argv[0], (char *const *)(uintptr_t)argv);
                /* Report the exec failure through the CLOEXEC pipe. */
                {
                        int e = errno;
                        ssize_t n = write(execfd[1], &e, sizeof(e));
                        (void)n;
                }
                _exit(127);
        }

        close(outfd[1]);
        close(errfd[1]);
        close(execfd[1]);

        {
                /* Check whether execvp succeeded. Blocks until the child
                 * execs (write end closes) or reports errno; retried on
                 * EINTR so a caught signal cannot skip the check. */
                int e = 0;
                ssize_t n;

                do {
                        n = read(execfd[0], &e, sizeof(e));
                } while (n < 0 && errno == EINTR);

                close(execfd[0]);
                if (n == (ssize_t)sizeof(e)) {
                        int saved = errno;

                        kill(pid, SIGKILL);
                        while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
                                ;
                        errno = saved;

                        res = shj_alloc(sizeof(*res));
                        res->exit = -1;
                        res->spawn_errno = e;
                        res->out = shj_strdup("");
                        res->err = shj_strdup("");
                        close(outfd[0]);
                        close(errfd[0]);
                        return res;
                }
        }

        pb_init(&ob);
        pb_init(&eb);

        {
                int timed_out = drain_streams(outfd[0], &ob, errfd[0], &eb, deadline_ms);

                close(outfd[0]);
                close(errfd[0]);

                if (timed_out != 0) {
                        kill(pid, SIGKILL);
                        while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
                                ;
                        res = shj_alloc(sizeof(*res));
                        res->exit = -2;
                        res->spawn_errno = ETIMEDOUT;
                        res->out = ob.data;
                        res->err = eb.data;
                        return res;
                }
        }

        while (waitpid(pid, &status, 0) < 0) {
                if (errno != EINTR)
                        break;
        }

        res = shj_alloc(sizeof(*res));
        res->spawn_errno = 0;
        if (WIFEXITED(status))
                res->exit = WEXITSTATUS(status);
        else if (WIFSIGNALED(status))
                res->exit = 128 + WTERMSIG(status);
        else
                res->exit = -1;
        res->out = ob.data;
        res->err = eb.data;
        return res;
}

void shj_proc_result_free(struct shj_proc_result *r)
{
        if (!r)
                return;
        free(r->out);
        free(r->err);
        free(r);
}
