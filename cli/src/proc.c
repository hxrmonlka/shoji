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

extern char **environ;

#define SHOJI_PROC_MAX_OUTPUT (4u * 1024u * 1024u) /* 4 MiB per stream */

/* Result exit classes: see proc.h (SHJ_PROC_EXIT_*). */

/* Pace of the WNOHANG reap loop: short enough not to delay normal runs
 * noticeably, long enough not to spin the CPU while a child lingers. */
#define PROC_REAP_POLL_MS 10

/* Grace budget for reaping a child whose SIGKILL could not be delivered:
 * bounded, so an unexpected kill() failure can never turn into an
 * unbounded blocking wait. */
#define PROC_KILL_GRACE_MS 1000

/* Close one descriptor and mark it dead so it can never be closed twice
 * and never leaks a stale number into a later cleanup path. */
static void close_fd(int *fd)
{
        if (*fd >= 0) {
                close(*fd);
                *fd = -1;
        }
}

/* Close both ends of a pipe the parent owns (all -1 entries are skipped). */
static void close_pair(int fds[2])
{
        close_fd(&fds[0]);
        close_fd(&fds[1]);
}

/* Keep capture descriptors away from stdin/stdout/stderr. Otherwise a caller
 * that started with (for example) stderr closed can cause a later close()
 * in the child to close the descriptor just installed by dup2(). */
static int move_fd_above_stdio(int *fd)
{
        int moved;

        if (*fd > STDERR_FILENO)
                return 0;
        moved = fcntl(*fd, F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
        if (moved < 0)
                return -1;
        close(*fd);
        *fd = moved;
        return 0;
}

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

static int64_t mono_ms(void)
{
        struct timespec ts;

        if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
                return -1;
        return (int64_t)ts.tv_sec * INT64_C(1000) + ts.tv_nsec / 1000000;
}

/* Convert the configured timeout to an absolute monotonic deadline using a
 * fixed-width type, even on targets where long is 32 bits. */
static int make_deadline(long timeout_ms, int64_t *deadline_ms)
{
        int64_t now;

        *deadline_ms = 0;
        if (timeout_ms < 0) {
                errno = EINVAL;
                return -1;
        }
        if (timeout_ms == 0)
                return 0;
        now = mono_ms();
        if (now < 0) {
                errno = EIO;
                return -1;
        }
        if ((int64_t)timeout_ms > INT64_MAX - now) {
                errno = ERANGE;
                return -1;
        }
        *deadline_ms = now + (int64_t)timeout_ms;
        return 0;
}

static struct shj_proc_result *proc_error_result(int exit_class, int error)
{
        struct shj_proc_result *res = shj_alloc(sizeof(*res));

        res->exit = exit_class;
        res->spawn_errno = error;
        res->truncated = 0;
        res->out = shj_strdup("");
        res->err = shj_strdup("");
        return res;
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

/* Non-blocking bounded reap: 0 when the child was reaped, 1 when it did
 * not exit within the budget (it may still be alive), -1 when waitpid
 * failed unexpectedly (errno set). */
static int reap_bounded(pid_t pid, int *status, int64_t budget_ms)
{
        int64_t now = mono_ms();
        int64_t end;

        if (now < 0 || budget_ms < 0 || budget_ms > INT64_MAX - now) {
                errno = ERANGE;
                return -1;
        }
        end = now + budget_ms;

        for (;;) {
                pid_t w = waitpid(pid, status, WNOHANG);

                if (w == pid)
                        return 0;
                if (w < 0) {
                        if (errno == EINTR)
                                continue;
                        return -1;
                }
                if (mono_ms() >= end)
                        return 1;
                poll(NULL, 0, PROC_REAP_POLL_MS);
        }
}

/* Kill the child and collect it. SIGKILL cannot be caught or ignored, so
 * under normal assumptions the wait returns promptly; EINTR is retried so
 * a caught signal cannot orphan the child as a zombie. ESRCH means the
 * child is already absent and only the reap remains. Any other kill()
 * failure is reported instead of being discarded, and the reap is then
 * BOUNDED: an unconditional blocking waitpid() could wait forever on a
 * child that never received the signal. Cleanup problems never change the
 * caller's result classification; they are reported here.
 * Returns 0 when the child was reaped; 1 when the kill failed and the
 * child did not exit within the grace budget (*kill_errno set; it may
 * still be running); -1 when waitpid failed unexpectedly (errno set). */
static int kill_and_reap(pid_t pid, int *status, int *kill_errno)
{
        *kill_errno = 0;
        for (;;) {
                if (kill(-pid, SIGKILL) == 0)
                        break; /* terminate the wrapper and its descendants */
                if (errno == EINTR)
                        continue;
                if (errno == ESRCH) {
                        /* Group creation may not have completed if timeout
                         * raced the child setup. Still try the direct child. */
                        if (kill(pid, SIGKILL) == 0 || errno == ESRCH)
                                break;
                        if (errno == EINTR)
                                continue;
                }
                *kill_errno = errno;
                shj_msg("kill(process group %ld, SIGKILL): %s",
                        (long)pid, strerror(errno));
                /* Best-effort direct-child fallback; keep the group error for
                 * diagnostics because descendants may not have been signaled. */
                (void)kill(pid, SIGKILL);
                break;
        }
        /* A successful SIGKILL only queues termination; it does not guarantee
         * the child is immediately waitable (e.g. uninterruptible sleep).
         * Never follow it with a blocking waitpid: cleanup must remain bounded
         * even when the kernel cannot promptly reap the child. */
        return reap_bounded(pid, status, PROC_KILL_GRACE_MS);
}

/* Shared kill+reap for cleanup paths: preserves the caller's failure
 * classification and reports cleanup problems separately. Returns what
 * kill_and_reap() returned. */
static int cleanup_child(pid_t pid, int *status)
{
        int kill_errno = 0;
        int r = kill_and_reap(pid, status, &kill_errno);

        if (r == -1)
                shj_msg("cleanup: waitpid: %s", strerror(errno));
        else if (r == 1) {
                if (kill_errno != 0)
                        shj_msg("cleanup: child %ld kill failed (%s) and it did not exit "
                                "within %d ms; it may still be running",
                                (long)pid, strerror(kill_errno), PROC_KILL_GRACE_MS);
                else
                        shj_msg("cleanup: child %ld received SIGKILL but was not reaped "
                                "within %d ms; it may still be running",
                                (long)pid, PROC_KILL_GRACE_MS);
        }
        return r;
}

/* Wait for a child that has already closed its capture pipes but may not
 * have exited yet. The same deadline budget applies: on expiry the child
 * is killed and reaped instead of blocking the caller indefinitely.
 * Returns 0 when reaped, -1 when the deadline forced a kill+reap (status
 * reflects the kill), -2 when waitpid failed unexpectedly (errno set). */
static int reap_within(pid_t pid, int *status, int64_t deadline_ms)
{
        for (;;) {
                pid_t w;

                if (deadline_ms > 0 && mono_ms() >= deadline_ms) {
                        if (cleanup_child(pid, status) == -1)
                                return -2;
                        return -1;
                }
                w = waitpid(pid, status, WNOHANG);
                if (w == pid)
                        return deadline_ms > 0 && mono_ms() >= deadline_ms ? -1 : 0;
                if (w < 0) {
                        if (errno == EINTR)
                                continue;
                        return -2;
                }
                /* w == 0: still running. */
                if (deadline_ms > 0 && mono_ms() >= deadline_ms) {
                        if (cleanup_child(pid, status) == -1)
                                return -2; /* waitpid failure: internal error */
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
                         int64_t deadline_ms)
{
        int open_out = 1, open_err = 1;

        while (open_out || open_err) {
                struct pollfd fds[2];
                nfds_t n = 0;
                int timeout;
                int r;

                if (deadline_ms > 0) {
                        int64_t left = deadline_ms - mono_ms();

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
                if (r == 0) {
                        if (mono_ms() >= deadline_ms)
                                return -1;
                        continue;
                }

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
static int await_exec(int execfd, int64_t deadline_ms, int *exec_errno)
{
        int e = 0;
        ssize_t n = 0;

        for (;;) {
                struct pollfd pfd;
                int timeout;
                int r;

                if (deadline_ms > 0) {
                        int64_t left = deadline_ms - mono_ms();

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
                if (r == 0) {
                        if (mono_ms() >= deadline_ms)
                                return -1;
                        continue;
                }

                if (pfd.revents & POLLNVAL) {
                        errno = EBADF; /* bad descriptor: internal error, not exec success */
                        return -2;
                }
                if (!(pfd.revents & (POLLIN | POLLHUP | POLLERR)))
                        continue; /* no handshake event: poll again */

                /* The child reports an exec failure as one complete 4-byte
                 * payload (its write loop retries EINTR and short writes),
                 * atomic against PIPE_BUF, so the read cannot split it. A
                 * failed exec writes the errno and then exits, so data and
                 * EOF can arrive in one wakeup: any error bytes are read
                 * before EOF is interpreted as success, and a short or
                 * damaged payload is still classified as a failed exec
                 * (EIO), never as a successful one. */
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
            fcntl(fds[1], F_SETFD, FD_CLOEXEC) != 0 ||
            move_fd_above_stdio(&fds[0]) != 0 ||
            move_fd_above_stdio(&fds[1]) != 0) {
                int saved = errno;

                close_pair(fds); /* leaves both entries at -1, never stale */
                errno = saved;
                return -1;
        }
        return 0;
}

/* Child side of the CLOEXEC handshake: report a failed dup2/execve by
 * writing the full errno to the handshake pipe. write() is retried on
 * EINTR and on partial writes so the parent can never read a truncated
 * payload; only async-signal-safe operations are used. A report that
 * cannot be delivered is ignored: nothing safer can be done here, and
 * the parent treats a short payload as a failed exec, never as success. */
static void write_exec_errno(int fd, int e)
{
        const char *p = (const char *)&e;
        size_t left = sizeof(e);

        while (left > 0) {
                ssize_t n = write(fd, p, left);

                if (n < 0) {
                        if (errno == EINTR)
                                continue;
                        return;
                }
                if (n == 0)
                        return; /* cannot happen on a pipe; defensive */
                p += n;
                left -= (size_t)n;
        }
}

struct shj_proc_result *shj_proc_run(const char *const argv[], void *user)
{
        /* All descriptors start at -1: every cleanup path closes only
         * initialized descriptors (close_fd skips -1) and can never close
         * an unrelated open file by accident. */
        int outfd[2] = { -1, -1 };
        int errfd[2] = { -1, -1 };
        int execfd[2] = { -1, -1 };
        pid_t pid;
        int status = 0;
        int64_t deadline_ms = 0;
        char *exec_path;
        struct pipebuf ob, eb;
        struct shj_proc_result *res;

        (void)user;

        if (make_deadline(g_timeout_ms, &deadline_ms) != 0)
                return proc_error_result(SHJ_PROC_EXIT_INTERNAL, errno);

        exec_path = shj_find_in_path(argv[0], NULL);
        if (!exec_path)
                return proc_error_result(SHJ_PROC_EXIT_SPAWN, errno ? errno : ENOENT);

        if (cloexec_pipe(outfd) != 0 || cloexec_pipe(errfd) != 0 ||
            cloexec_pipe(execfd) != 0) {
                int saved = errno;

                /* Close whatever was actually created; entries for pipes
                 * that were never opened are still -1. */
                close_pair(outfd);
                close_pair(errfd);
                close_pair(execfd);
                free(exec_path);
                return proc_error_result(SHJ_PROC_EXIT_INTERNAL, saved);
        }

        pid = fork();
        if (pid < 0) {
                int saved = errno;

                close_pair(outfd);
                close_pair(errfd);
                close_pair(execfd);
                free(exec_path);
                return proc_error_result(SHJ_PROC_EXIT_INTERNAL, saved);
        } else if (pid == 0) {
                /* Put the launched process in a dedicated group. Timeout
                 * cleanup signals this group; descendants that deliberately
                 * leave it are outside the cancellation guarantee. */
                if (setpgid(0, 0) != 0) {
                        write_exec_errno(execfd[1], errno);
                        _exit(127);
                }
                /* Child: wire the capture pipes onto stdout/stderr, then exec
                 * with the argv vector untouched (dup2 clears CLOEXEC on the
                 * new descriptors). A failed dup2 reports through the same
                 * exec-error pipe as a failed exec; only async-signal-safe
                 * calls happen on this path. */
                if (dup2(outfd[1], STDOUT_FILENO) < 0 ||
                    dup2(errfd[1], STDERR_FILENO) < 0) {
                        write_exec_errno(execfd[1], errno);
                        _exit(127);
                }
                close(outfd[0]);
                close(outfd[1]);
                close(errfd[0]);
                close(errfd[1]);
                execve(exec_path, (char *const *)(uintptr_t)argv, environ);
                /* Report the exec failure through the CLOEXEC pipe. */
                write_exec_errno(execfd[1], errno);
                _exit(127);
        }

        free(exec_path);

        /* The parent also establishes the group: either side may run first,
         * and EACCES means the child already exec'd after its own setpgid(). */
        if (setpgid(pid, pid) != 0 && errno != EACCES && errno != ESRCH) {
                int saved = errno;

                close_pair(outfd);
                close_pair(errfd);
                close_pair(execfd);
                cleanup_child(pid, &status);
                return proc_error_result(SHJ_PROC_EXIT_INTERNAL, saved);
        }

        /* Parent: drop the write ends it no longer owns. The child holds
         * its own copies; closing the parent's write ends is what makes the
         * capture pipes report EOF once the child exits. */
        close_fd(&outfd[1]);
        close_fd(&errfd[1]);
        close_fd(&execfd[1]);

        {
                int exec_errno = 0;
                int hs = await_exec(execfd[0], deadline_ms, &exec_errno);
                int hs_errno = hs == -2 ? errno : 0;

                close_pair(execfd);
                if (hs != 0) {
                        /* Exec never succeeded (or the handshake was lost):
                         * nothing can arrive on the capture pipes anymore, so
                         * the parent releases its ends here. Every early
                         * return below would otherwise leak them. */
                        close_pair(outfd);
                        close_pair(errfd);
                }
                if (hs == -1) {
                        /* Over budget before the handshake resolved: kill and
                         * reap so nothing survives, then report the timeout. */
                        cleanup_child(pid, &status);
                        res = shj_alloc(sizeof(*res));
                        res->exit = SHJ_PROC_EXIT_TIMEOUT;
                        res->spawn_errno = ETIMEDOUT;
                        res->truncated = 0;
                        res->out = shj_strdup("");
                        res->err = shj_strdup("");
                        return res;
                }
                if (hs == -2) {
                        cleanup_child(pid, &status);
                        return proc_error_result(SHJ_PROC_EXIT_INTERNAL, hs_errno);
                }
                if (hs == 1) {
                        /* The child failed to exec and reported its errno; it
                         * is already exiting (127), collect it. */
                        cleanup_child(pid, &status);
                        res = shj_alloc(sizeof(*res));
                        res->exit = SHJ_PROC_EXIT_SPAWN;
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
                int drain_errno = drained == -2 ? errno : 0;

                close_pair(outfd);
                close_pair(errfd);

                if (drained != 0) {
                        int saved = drain_errno;

                        /* Capture cannot continue (budget exhausted or stream
                         * error): kill and reap so no child or zombie is left
                         * behind, preserving whatever was captured. */
                        cleanup_child(pid, &status);
                        res = shj_alloc(sizeof(*res));
                        if (drained == -1) {
                                res->exit = SHJ_PROC_EXIT_TIMEOUT;
                                res->spawn_errno = ETIMEDOUT;
                        } else {
                                res->exit = SHJ_PROC_EXIT_INTERNAL;
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
                                res->exit = SHJ_PROC_EXIT_TIMEOUT;
                                res->spawn_errno = ETIMEDOUT;
                        } else {
                                res->exit = SHJ_PROC_EXIT_INTERNAL;
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
