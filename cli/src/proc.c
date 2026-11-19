#define _POSIX_C_SOURCE 200809L

#include "exitcodes.h"
#include "proc.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define SHOJI_PROC_MAX_OUTPUT (4u * 1024u * 1024u) /* 4 MiB per stream */

/* Result exit classes below zero (see proc.h): -1 spawn, -2 timeout,
 * -3 internal stream/wait failure. */
#define PROC_EXIT_SPAWN (-1)
#define PROC_EXIT_TIMEOUT (-2)
#define PROC_EXIT_INTERNAL (-3)

/* Pace of the WNOHANG reap loop: short enough not to delay normal runs
 * noticeably, long enough not to spin the CPU while a child lingers. */
#define PROC_REAP_POLL_MS 10

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

static long mono_ms(void)
{
        struct timespec ts;

        clock_gettime(CLOCK_MONOTONIC, &ts);
        return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

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

static unsigned trunc_bits(const struct pipebuf *ob, const struct pipebuf *eb)
{
        return (unsigned)(ob->truncated ? SHOJI_TRUNC_OUT : 0) |
               (eb->truncated ? SHOJI_TRUNC_ERR : 0);
}

/* Kill the child and collect it. SIGKILL cannot be caught or ignored, so
 * under normal assumptions the wait returns promptly; EINTR is retried so
 * a caught signal cannot orphan the child as a zombie. ESRCH means the
 * child is already absent and only the reap remains; any other kill()
 * failure is reported instead of being discarded but never changes the
 * outcome. Returns 0, or -1 if waitpid failed unexpectedly (errno set). */
static int kill_and_reap(pid_t pid, int *status)
{
        pid_t w;

        for (;;) {
                if (kill(pid, SIGKILL) == 0)
                        break;
                if (errno == ESRCH)
                        break; /* already absent: nothing to signal, reap still needed */
                if (errno == EINTR)
                        continue; /* interrupted kill: retry */
                shj_msg("kill(%ld, SIGKILL): %s", (long)pid, strerror(errno));
                break;
        }
        do {
                w = waitpid(pid, status, 0);
        } while (w < 0 && errno == EINTR);
        return w == pid ? 0 : -1;
}

/* Wait for a child that has already closed its capture pipes but may not
 * have exited yet. The same deadline budget applies: on expiry the child
 * is killed and reaped instead of blocking the caller indefinitely.
 * Returns 0 when reaped, -1 when the deadline forced a kill+reap (status
 * reflects the kill), -2 when waitpid failed unexpectedly (errno set). */
static int reap_within(pid_t pid, int *status, long deadline_ms)
{
        for (;;) {
                pid_t w = waitpid(pid, status, WNOHANG);

                if (w == pid)
                        return 0;
                if (w < 0) {
                        if (errno == EINTR)
                                continue;
                        return -2;
                }
                /* w == 0: still running. */
                if (deadline_ms > 0 && mono_ms() >= deadline_ms) {
                        if (kill_and_reap(pid, status) != 0)
                                return -2;
                        return -1;
                }
                poll(NULL, 0, PROC_REAP_POLL_MS); /* bounded, interruptible sleep */
        }
}

/* Pump both capture pipes concurrently so a child blocked writing one
 * stream cannot deadlock us on the other. Both streams keep draining past
 * the 4 MiB capture cap (excess is discarded) so the child can never wedge
 * on a full pipe. Returns 0 when both streams reached EOF, -1 when the
 * deadline expired, -2 on an unexpected poll/read failure (errno set).
 * The caller must treat a -2 as an internal error, never as success with
 * partially captured output. */
static int drain_streams(int out_fd, struct pipebuf *ob, int err_fd, struct pipebuf *eb,
                         long deadline_ms)
{
        int open_out = 1, open_err = 1;

        while (open_out || open_err) {
                struct pollfd fds[2];
                nfds_t n = 0;
                int timeout;
                int r;

                if (deadline_ms > 0) {
                        long left = deadline_ms - mono_ms();

                        if (left <= 0)
                                return -1;
                        timeout = left > INT_MAX ? INT_MAX : (int)left;
                } else {
                        timeout = -1; /* timeout disabled */
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
                                continue; /* interrupted wait: retry unchanged */
                        return -2; /* unexpected poll failure: propagate */
                }
                if (r == 0)
                        return -1; /* deadline expired, streams still open */

                for (nfds_t i = 0; i < n; i++) {
                        char chunk[8192];
                        ssize_t got;
                        struct pipebuf *b;

                        if (fds[i].revents & POLLNVAL) {
                                errno = EBADF; /* invalid descriptor: internal error, not EOF */
                                return -2;
                        }
                        if (!(fds[i].revents & (POLLIN | POLLHUP | POLLERR)))
                                continue;
                        b = (fds[i].fd == out_fd) ? ob : eb;
                        got = read(fds[i].fd, chunk, sizeof(chunk));
                        if (got == 0) {
                                /* Write end closed: this stream is complete. */
                                if (fds[i].fd == out_fd)
                                        open_out = 0;
                                else
                                        open_err = 0;
                                continue;
                        }
                        if (got < 0) {
                                if (errno == EINTR || errno == EAGAIN)
                                        continue; /* spurious wake or signal: retry */
                                return -2; /* real read error: propagate */
                        }
                        pb_add(b, chunk, got);
                }
        }
        return 0;
}

/* Wait for the exec attempt to resolve through the CLOEXEC handshake pipe.
 * The handshake is part of the timeout budget: a child that never execs
 * and never reports failure cannot wedge the CLI past the deadline.
 * Returns 0 when exec succeeded (write end closed by CLOEXEC), 1 when the
 * child reported an exec failure (*exec_errno set), -1 when the deadline
 * expired before the handshake completed, -2 on an unexpected poll/read
 * failure (errno set). */
static int await_exec(int execfd, long deadline_ms, int *exec_errno)
{
        int e = 0;
        ssize_t n = 0;

        for (;;) {
                struct pollfd pfd;
                int timeout;
                int r;

                if (deadline_ms > 0) {
                        long left = deadline_ms - mono_ms();

                        if (left <= 0)
                                return -1;
                        timeout = left > INT_MAX ? INT_MAX : (int)left;
                } else {
                        timeout = -1; /* timeout disabled */
                }

                pfd.fd = execfd;
                pfd.events = POLLIN;
                pfd.revents = 0;
                r = poll(&pfd, 1, timeout);
                if (r < 0) {
                        if (errno == EINTR)
                                continue; /* retry with the remaining budget */
                        return -2;
                }
                if (r == 0)
                        return -1; /* deadline expired before the handshake resolved */

                if (pfd.revents & POLLNVAL) {
                        errno = EBADF; /* bad descriptor: internal error, not exec success */
                        return -2;
                }
                if (!(pfd.revents & (POLLIN | POLLHUP | POLLERR)))
                        continue; /* no handshake event: poll again */

                /* The exec-failure write is one 4-byte write to a pipe, atomic
                 * against PIPE_BUF, so the read cannot split it. A failed exec
                 * writes the errno and then exits, so data and EOF can arrive
                 * in one wakeup: any error bytes are read before EOF is
                 * interpreted as success. */
                do {
                        n = read(execfd, &e, sizeof(e));
                } while (n < 0 && errno == EINTR);
                if (n < 0 && errno == EAGAIN)
                        continue; /* stale readiness: poll again */
                break;
        }
        if (n < 0)
                return -2; /* read failed despite poll readiness: propagate */
        if (n == 0)
                return 0; /* write end closed by exec (or child death): proceed */
        if (n != (ssize_t)sizeof(e))
                e = EIO; /* defensive: handshake cannot really be partial */
        *exec_errno = e;
        return 1;
}

static int cloexec_pipe(int fds[2])
{
        fds[0] = -1;
        fds[1] = -1;
        if (pipe(fds) != 0)
                return -1;
        if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) != 0 ||
            fcntl(fds[1], F_SETFD, FD_CLOEXEC) != 0) {
                int saved = errno;

                close(fds[0]);
                close(fds[1]);
                errno = saved;
                return -1;
        }
        return 0;
}

struct shj_proc_result *shj_proc_run(const char *const argv[], void *user)
{
        int outfd[2], errfd[2], execfd[2];
        pid_t pid;
        int status = 0;
        long deadline_ms = 0;
        struct pipebuf ob, eb;
        struct shj_proc_result *res;

        (void)user;

        if (cloexec_pipe(outfd) != 0 || cloexec_pipe(errfd) != 0 ||
            cloexec_pipe(execfd) != 0) {
                int saved = errno;

                /* fds are -1-initialized, so closing all six is safe even
                 * when an earlier pipe failed to be created. */
                close(outfd[0]);
                close(outfd[1]);
                close(errfd[0]);
                close(errfd[1]);
                close(execfd[0]);
                close(execfd[1]);
                shj_die(SHOJI_EXIT_INTERNAL, "pipe: %s", strerror(saved));
        }

        if (g_timeout_ms > 0)
                deadline_ms = mono_ms() + g_timeout_ms;

        pid = fork();
        if (pid < 0) {
                shj_die(SHOJI_EXIT_INTERNAL, "fork: %s", strerror(errno));
        } else if (pid == 0) {
                /* Child: wire the capture pipes onto stdout/stderr, then exec
                 * with the argv vector untouched (dup2 clears CLOEXEC on the
                 * new descriptors). A failed dup2 reports through the same
                 * exec-error pipe as a failed exec; only async-signal-safe
                 * calls happen on this path. */
                if (dup2(outfd[1], STDOUT_FILENO) < 0 ||
                    dup2(errfd[1], STDERR_FILENO) < 0) {
                        int e = errno;
                        ssize_t n = write(execfd[1], &e, sizeof(e));

                        (void)n;
                        _exit(127);
                }
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
                int exec_errno = 0;
                int hs = await_exec(execfd[0], deadline_ms, &exec_errno);

                close(execfd[0]);
                if (hs == -1) {
                        /* Over budget before the handshake resolved: kill and
                         * reap so nothing survives, then report the timeout. */
                        if (kill_and_reap(pid, &status) != 0)
                                shj_msg("cleanup: waitpid: %s", strerror(errno));
                        res = shj_alloc(sizeof(*res));
                        res->exit = PROC_EXIT_TIMEOUT;
                        res->spawn_errno = ETIMEDOUT;
                        res->truncated = 0;
                        res->out = shj_strdup("");
                        res->err = shj_strdup("");
                        return res;
                }
                if (hs == -2) {
                        int saved = errno;

                        if (kill_and_reap(pid, &status) != 0)
                                shj_msg("cleanup: waitpid: %s", strerror(errno));
                        res = shj_alloc(sizeof(*res));
                        res->exit = PROC_EXIT_INTERNAL;
                        res->spawn_errno = saved;
                        res->truncated = 0;
                        res->out = shj_strdup("");
                        res->err = shj_strdup("");
                        return res;
                }
                if (hs == 1) {
                        /* The child failed to exec and reported its errno; it
                         * is already exiting (127), collect it. */
                        if (kill_and_reap(pid, &status) != 0)
                                shj_msg("cleanup: waitpid: %s", strerror(errno));
                        res = shj_alloc(sizeof(*res));
                        res->exit = PROC_EXIT_SPAWN;
                        res->spawn_errno = exec_errno;
                        res->truncated = 0;
                        res->out = shj_strdup("");
                        res->err = shj_strdup("");
                        return res;
                }
                /* hs == 0: exec succeeded, fall through to draining. */
        }

        pb_init(&ob);
        pb_init(&eb);

        {
                int drained = drain_streams(outfd[0], &ob, errfd[0], &eb, deadline_ms);

                close(outfd[0]);
                close(errfd[0]);

                if (drained != 0) {
                        int saved = drained == -2 ? errno : 0;

                        /* Capture cannot continue (budget exhausted or stream
                         * error): kill and reap so no child or zombie is left
                         * behind, preserving whatever was captured. */
                        if (kill_and_reap(pid, &status) != 0)
                                shj_msg("cleanup: waitpid: %s", strerror(errno));
                        res = shj_alloc(sizeof(*res));
                        if (drained == -1) {
                                res->exit = PROC_EXIT_TIMEOUT;
                                res->spawn_errno = ETIMEDOUT;
                        } else {
                                res->exit = PROC_EXIT_INTERNAL;
                                res->spawn_errno = saved;
                        }
                        res->truncated = trunc_bits(&ob, &eb);
                        res->out = ob.data;
                        res->err = eb.data;
                        return res;
                }
        }

        /* Both capture streams are at EOF but the child may still be winding
         * down; bound this wait by the same deadline budget. */
        {
                int reaped = reap_within(pid, &status, deadline_ms);

                if (reaped != 0) {
                        int saved = reaped == -2 ? errno : 0;

                        res = shj_alloc(sizeof(*res));
                        if (reaped == -1) {
                                res->exit = PROC_EXIT_TIMEOUT;
                                res->spawn_errno = ETIMEDOUT;
                        } else {
                                res->exit = PROC_EXIT_INTERNAL;
                                res->spawn_errno = saved;
                        }
                        res->truncated = trunc_bits(&ob, &eb);
                        res->out = ob.data;
                        res->err = eb.data;
                        return res;
                }
        }

        res = shj_alloc(sizeof(*res));
        res->spawn_errno = 0;
        if (WIFEXITED(status))
                res->exit = WEXITSTATUS(status);
        else if (WIFSIGNALED(status))
                res->exit = 128 + WTERMSIG(status);
        else
                res->exit = -1;
        res->truncated = trunc_bits(&ob, &eb);
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
