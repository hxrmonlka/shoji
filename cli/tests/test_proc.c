/* shoji-cli -- shj_proc_run() regression tests.
 * Deterministic: every child is the spawn-helper fixture, so no real
 * Quickshell session is involved. Covers the timeout budget over the whole
 * subprocess lifecycle (handshake, draining, reaping), exec-failure
 * reporting, exit/signal propagation, 4 MiB truncation without deadlock,
 * partial capture on timeout, and zombie-free cleanup. */
#include "proc.h"
#include "testmain.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "util.h"

#define HELPER_ENV "SHOJI_SPAWN_HELPER"
#define CAP_BYTES (4L * 1024L * 1024L)

static long mono_ms(void)
{
        struct timespec ts;

        clock_gettime(CLOCK_MONOTONIC, &ts);
        return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static struct shj_proc_result *run_helper(const char *mode, const char *arg)
{
        const char *argv[4];
        int i = 0;

        argv[i++] = getenv(HELPER_ENV);
        argv[i++] = mode;
        if (arg)
                argv[i++] = arg;
        argv[i] = NULL;
        return shj_proc_run(argv, NULL);
}

static int process_is_running(pid_t pid)
{
        char path[64];
        char line[512];
        char *state;
        FILE *f;

        snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
        f = fopen(path, "r");
        if (!f)
                return 0;
        if (!fgets(line, sizeof(line), f)) {
                fclose(f);
                return 0;
        }
        fclose(f);
        state = strrchr(line, ')');
        if (!state || state[1] != ' ' || state[2] == '\0')
                return 0;
        return state[2] != 'Z' && state[2] != 'X';
}

static int reap_or_confirm_gone(pid_t pid)
{
        struct timespec pause = { .tv_sec = 0, .tv_nsec = 10000000L };
        int i;

        for (i = 0; i < 100; i++) {
                int status;
                pid_t r = waitpid(pid, &status, WNOHANG);

                if (r == pid)
                        return 1;
                if (r < 0 && errno == ECHILD)
                        return !process_is_running(pid);
                if (!process_is_running(pid)) {
                        (void)waitpid(pid, &status, WNOHANG);
                        return 1;
                }
                nanosleep(&pause, NULL);
        }
        return 0;
}

/* Count our children still in Z state (reaped children are gone entirely). */
static int count_zombie_children(void)
{
        DIR *d;
        struct dirent *de;
        pid_t self = getpid();
        int zombies = 0;

        d = opendir("/proc");
        if (!d)
                return -1;
        while ((de = readdir(d)) != NULL) {
                char path[6 + 256 + 6]; /* "/proc/" + NAME_MAX + "/stat" + NUL */
                FILE *f;
                char line[512];
                const char *rp;
                char state = '?';
                int ppid = 0;

                if (de->d_name[0] < '0' || de->d_name[0] > '9')
                        continue;
                snprintf(path, sizeof(path), "/proc/%s/stat", de->d_name);
                f = fopen(path, "r");
                if (!f)
                        continue;
                if (fgets(line, sizeof(line), f)) {
                        rp = strrchr(line, ')');
                        if (rp && sscanf(rp + 1, " %c %d", &state, &ppid) == 2 &&
                            state == 'Z' && ppid == (int)self)
                                zombies++;
                }
                fclose(f);
        }
        closedir(d);
        return zombies;
}

/* Count our open descriptors via /proc/self/fd (-1 when unavailable). */
static int count_open_fds(void)
{
        DIR *d;
        struct dirent *de;
        int n = 0;

        d = opendir("/proc/self/fd");
        if (!d)
                return -1;
        while ((de = readdir(d)) != NULL) {
                if (de->d_name[0] >= '0' && de->d_name[0] <= '9')
                        n++;
        }
        closedir(d);
        return n;
}

static void test_capture_and_exit(void)
{
        struct shj_proc_result *r;

        test_section("proc: capture and exit propagation");

        shj_proc_set_timeout_ms(5000);
        r = run_helper("echo", "hello from helper");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "echo: child exit status is 0");
                CHECK_STR_EQ(r->out, "hello from helper\n", "echo: stdout captured verbatim");
                CHECK_STR_EQ(r->err, "", "echo: stderr empty");
                CHECK_INT_EQ(r->truncated, 0, "echo: not flagged truncated");
                shj_proc_result_free(r);
        }

        r = run_helper("echo-err", "to stderr");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "echo-err: child exit status is 0");
                CHECK_STR_EQ(r->err, "to stderr\n", "echo-err: stderr captured verbatim");
                CHECK_STR_EQ(r->out, "", "echo-err: stdout empty");
                shj_proc_result_free(r);
        }

        r = run_helper("exit", "7");
        if (r) {
                CHECK_INT_EQ(r->exit, 7, "exit: status 7 propagated");
                CHECK_INT_EQ(r->spawn_errno, 0, "exit: spawn_errno cleared");
                shj_proc_result_free(r);
        }

        r = run_helper("sig", "15");
        if (r) {
                CHECK_INT_EQ(r->exit, 128 + 15, "sig: SIGTERM reported as 128+15");
                shj_proc_result_free(r);
        }
}


static void test_closed_standard_descriptor(void)
{
        struct shj_proc_result *r;
        int saved_stderr = dup(STDERR_FILENO);

        test_section("proc: descriptors below stdio are normalized");
        if (saved_stderr < 0) {
                test_fail("closed stderr: could not save stderr");
                return;
        }
        close(STDERR_FILENO);
        r = run_helper("echo-err", "stderr survives closed parent fd");
        (void)dup2(saved_stderr, STDERR_FILENO);
        close(saved_stderr);
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "closed stderr: helper exits successfully");
                CHECK_STR_EQ(r->err, "stderr survives closed parent fd\n",
                             "closed stderr: captured stderr survives descriptor reuse");
                shj_proc_result_free(r);
        }
}

static void test_timeout_kills_wrapper_descendants(void)
{
        const char *tpl = "/tmp/shoji-descendant-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));
        char marker[512];
        char pidfile[512];
        char pid_text[64];
        const char *argv[5];
        struct shj_proc_result *r;
        struct timespec pause = { .tv_sec = 0, .tv_nsec = 650000000L };
        FILE *f;
        long child_pid = -1;

        test_section("proc: timeout cancels wrapper descendants");
        if (!dir) {
                test_fail("descendant timeout: fixture directory created");
                return;
        }
        snprintf(marker, sizeof(marker), "%s/marker", dir);
        snprintf(pidfile, sizeof(pidfile), "%s/pid", dir);
        argv[0] = getenv(HELPER_ENV);
        argv[1] = "fork-marker";
        argv[2] = marker;
        argv[3] = pidfile;
        argv[4] = NULL;
        shj_proc_set_timeout_ms(150);
        r = shj_proc_run(argv, NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_TIMEOUT,
                             "descendant timeout: wrapper exceeds deadline");
                shj_proc_result_free(r);
        }
        f = fopen(pidfile, "r");
        if (f) {
                if (fgets(pid_text, sizeof(pid_text), f))
                        child_pid = strtol(pid_text, NULL, 10);
                fclose(f);
        }
        nanosleep(&pause, NULL);
        CHECK(access(marker, F_OK) != 0,
              "descendant timeout: child did not write marker after Shoji returned");
        CHECK_INT_EQ(child_pid > 0 && reap_or_confirm_gone((pid_t)child_pid), 1,
                     "descendant timeout: known child is terminated and reaped when adopted");
        unlink(marker);
        unlink(pidfile);
        rmdir(dir);
        free(dir);
        shj_proc_set_timeout_ms(5000);
}

static void test_timeout_overflow(void)
{
        struct shj_proc_result *r;

        test_section("proc: timeout deadline arithmetic");
        shj_proc_set_timeout_ms(LONG_MAX);
        r = run_helper("exit", "0");
        if (r) {
#if LONG_MAX > INT32_MAX
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_INTERNAL,
                             "LONG_MAX timeout returns internal error");
                CHECK_INT_EQ(r->spawn_errno, ERANGE,
                             "LONG_MAX timeout reports checked deadline overflow");
#else
                CHECK_INT_EQ(r->exit, 0,
                             "32-bit LONG_MAX timeout fits the wide deadline");
#endif
                shj_proc_result_free(r);
        }
        shj_proc_set_timeout_ms(-1);
        r = run_helper("exit", "0");
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_INTERNAL,
                             "negative timeout is rejected");
                CHECK_INT_EQ(r->spawn_errno, EINVAL,
                             "negative timeout reports EINVAL");
                shj_proc_result_free(r);
        }
        shj_proc_set_timeout_ms(5000);
}

static void test_spawn_failure(void)
{
        const char *argv[] = { "shoji-nonexistent-helper-xyz", NULL };
        struct shj_proc_result *r;

        test_section("proc: exec failure handshake");

        shj_proc_set_timeout_ms(5000);
        r = shj_proc_run(argv, NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, -1, "missing binary: exit class -1");
                CHECK_INT_EQ(r->spawn_errno, ENOENT, "missing binary: spawn_errno is ENOENT");
                CHECK_STR_EQ(r->out, "", "missing binary: stdout empty");
                CHECK_STR_EQ(r->err, "", "missing binary: stderr empty");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "missing binary: no zombie left");
}

/* An exec failure other than ENOENT: a regular file without an execute
 * bit. Same handshake (errno bytes, then the child exits), a different
 * errno, and by the time the parent kills it the child is usually already
 * gone, which exercises the ESRCH-tolerant reap. */
static void test_spawn_failure_eacces(void)
{
        const char *tpl = "/tmp/shoji-eacces-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));
        char *nos;
        const char *argv[2];
        struct shj_proc_result *r;
        FILE *f;
        int w, c;

        test_section("proc: exec failure errno classes");

        if (!dir) {
                test_fail("non-executable file: fixture setup failed");
                return;
        }
        nos = shj_path_join(dir, "not-executable");
        f = fopen(nos, "w");
        if (!f) {
                test_fail("non-executable file: fixture fopen failed");
                unlink(nos);
                rmdir(dir);
                free(nos);
                free(dir);
                return;
        }
        w = fputs("#!/bin/sh\nexit 0\n", f);
        c = fclose(f);
        if (w == EOF || c != 0 || chmod(nos, 0600) != 0) {
                /* never executable, for root and non-root alike */
                test_fail("non-executable file: fixture write/chmod failed");
                unlink(nos);
                rmdir(dir);
                free(nos);
                free(dir);
                return;
        }

        argv[0] = nos;
        argv[1] = NULL;
        shj_proc_set_timeout_ms(5000);
        r = shj_proc_run(argv, NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, -1, "non-executable file: exit class -1");
                CHECK_INT_EQ(r->spawn_errno, EACCES, "non-executable file: spawn_errno is EACCES");
                CHECK_STR_EQ(r->out, "", "non-executable file: stdout empty");
                CHECK_STR_EQ(r->err, "", "non-executable file: stderr empty");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "non-executable file: no zombie left");

        unlink(nos);
        rmdir(dir);
        free(nos);
        free(dir);
}

static void test_spawn_failure_enoexec(void)
{
        const char *tpl = "/tmp/shoji-enoexec-XXXXXX";
        char *dir = mkdtemp(shj_strdup(tpl));
        char *bad_exec;
        const char *argv[2];
        struct shj_proc_result *r;
        FILE *f;

        test_section("proc: executable text without a shebang is not interpreted");
        if (!dir) {
                test_fail("ENOEXEC fixture directory created");
                return;
        }
        bad_exec = shj_path_join(dir, "no-shebang");
        f = fopen(bad_exec, "w");
        if (!f) {
                test_fail("ENOEXEC fixture opened");
                rmdir(dir);
                free(bad_exec);
                free(dir);
                return;
        }
        {
                int write_failed = fputs("exit 0\n", f) == EOF;
                int close_failed = fclose(f) != 0;

                if (write_failed || close_failed || chmod(bad_exec, 0700) != 0) {
                        test_fail("ENOEXEC fixture written and made executable");
                        unlink(bad_exec);
                        rmdir(dir);
                        free(bad_exec);
                        free(dir);
                        return;
                }
        }
        argv[0] = bad_exec;
        argv[1] = NULL;
        shj_proc_set_timeout_ms(5000);
        r = shj_proc_run(argv, NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_SPAWN,
                             "ENOEXEC: no implicit shell fallback");
                CHECK_INT_EQ(r->spawn_errno, ENOEXEC,
                             "ENOEXEC: executable text reports ENOEXEC");
                shj_proc_result_free(r);
        }
        unlink(bad_exec);
        rmdir(dir);
        free(bad_exec);
        free(dir);
}

/* Repeated exec failures and timeout kills must not leak the parent's
 * descriptors: every early return after pipe creation releases the ends it
 * owns. */
static void test_fd_hygiene(void)
{
        const char *argv[] = { "shoji-nonexistent-helper-xyz", NULL };
        int base, now, i;
        struct shj_proc_result *r;

        test_section("proc: descriptor hygiene across early returns");

        shj_proc_set_timeout_ms(300);
        base = count_open_fds();
        CHECK(base >= 0, "fd scan available");
        if (base < 0)
                return;

        /* nonexistent executables: the exec handshake fails and every
         * branch returns early */
        for (i = 0; i < 5; i++) {
                r = shj_proc_run(argv, NULL);
                if (r)
                        shj_proc_result_free(r);
        }
        /* permission failures: a different exec errno through the same
         * handshake */
        {
                const char *tpl = "/tmp/shoji-fdhyg-XXXXXX";
                char *dir = mkdtemp(shj_strdup(tpl));
                char *nos;
                const char *argv2[2];

                if (!dir) {
                        test_fail("fd hygiene: fixture setup failed");
                        return;
                }
                nos = shj_path_join(dir, "not-executable");
                {
                        FILE *f = fopen(nos, "w");
                        int w, c;

                        if (!f) {
                                test_fail("fd hygiene: fixture fopen failed");
                        } else {
                                w = fputs("#!/bin/sh\nexit 0\n", f);
                                c = fclose(f);
                                if (w == EOF || c != 0 || chmod(nos, 0600) != 0)
                                        test_fail("fd hygiene: fixture write/chmod failed");
                        }
                }
                argv2[0] = nos;
                argv2[1] = NULL;
                for (i = 0; i < 3; i++) {
                        r = shj_proc_run(argv2, NULL);
                        if (r)
                                shj_proc_result_free(r);
                }
                unlink(nos);
                rmdir(dir);
                free(nos);
                free(dir);
        }
        /* timeout kills: the handshake succeeds, the drain times out, and
         * the SIGKILL cleanup path releases the capture ends */
        {
                const char *argv3[3];
                const char *helper = getenv("SHOJI_SPAWN_HELPER");

                if (helper && *helper) {
                        argv3[0] = helper;
                        argv3[1] = "hang";
                        argv3[2] = NULL;
                        for (i = 0; i < 3; i++) {
                                r = shj_proc_run(argv3, NULL);
                                if (r)
                                        shj_proc_result_free(r);
                        }
                } else {
                        test_ok("fd hygiene: helper unset, timeout legs skipped");
                }
        }
        now = count_open_fds();
        CHECK_INT_EQ(now, base, "no descriptors leaked across spawn failures and timeouts");
        shj_proc_set_timeout_ms(5000);
}

static void test_timeout_lifecycle(void)
{
        struct shj_proc_result *r;
        long t0, elapsed;

        test_section("proc: timeout covers the whole lifecycle");

        /* A child that never exits must be killed and reaped within the
         * budget instead of blocking the caller. */
        shj_proc_set_timeout_ms(400);
        t0 = mono_ms();
        r = run_helper("hang", NULL);
        elapsed = mono_ms() - t0;
        if (r) {
                CHECK_INT_EQ(r->exit, -2, "hang: exit class -2 (timeout)");
                CHECK_INT_EQ(r->spawn_errno, ETIMEDOUT, "hang: spawn_errno is ETIMEDOUT");
                CHECK_STR_EQ(r->out, "", "hang: stdout empty");
                CHECK_INT_EQ(elapsed < 5000, 1, "hang: cleanup returned promptly");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "hang: killed child reaped, no zombie");

        /* Partial capture survives a timeout and stays under the cap. */
        r = run_helper("emit-hang", "1024");
        if (r) {
                CHECK_INT_EQ(r->exit, -2, "emit-hang: exit class -2 (timeout)");
                CHECK_INT_EQ((long)strlen(r->out), 1024L * 1024L,
                             "emit-hang: 1 MiB of stdout captured before the kill");
                CHECK_INT_EQ(r->truncated, 0, "emit-hang: not truncated, just cut by timeout");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "emit-hang: no zombie left");

        /* timeout 0 means disabled: a slow child completes normally. */
        shj_proc_set_timeout_ms(400);
        shj_proc_set_timeout_ms(0);
        r = run_helper("slow-exit", "650");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "timeout 0: slow child not killed");
                shj_proc_result_free(r);
        }

        /* The process exits after closing its output pipes, just beyond the
         * deadline. Reaping it after the budget must not become success. */
        shj_proc_set_timeout_ms(400);
        r = run_helper("close-pipes-sleep", "410");
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_TIMEOUT,
                             "late exit after pipe EOF remains a timeout");
                shj_proc_result_free(r);
        }

        /* Boundary condition: the child exits just INSIDE the deadline. A
         * polling wake-up that lands past the deadline must not turn the
         * completed exit into a timeout; the wait is bounded by the
         * remaining budget so the deadline itself is never overshot before
         * the reap is attempted. */
        shj_proc_set_timeout_ms(1000);
        r = run_helper("close-pipes-sleep", "900");
        if (r) {
                CHECK_INT_EQ(r->exit, 0,
                             "exit inside the deadline stays a success");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "boundary: no zombie left");
        shj_proc_set_timeout_ms(5000);
}

static void test_embedded_nul(void)
{
        struct shj_proc_result *r;

        test_section("proc: embedded NUL bytes in captured text");

        shj_proc_set_timeout_ms(5000);

        /* Valid JSON with no embedded NUL keeps working. */
        r = run_helper("emit-text", "[]");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "emit-text: [] passes through");
                CHECK_STR_EQ(r->out, "[]", "emit-text: captured verbatim");
                shj_proc_result_free(r);
        }

        /* A listing prefix followed by a NUL and more data must be rejected
         * instead of silently truncating to the prefix. */
        r = run_helper("emit-nul", NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_INTERNAL,
                             "stdout NUL: malformed output is rejected");
                CHECK_INT_EQ(r->spawn_errno, EILSEQ, "stdout NUL: spawn_errno is EILSEQ");
                CHECK_STR_EQ(r->out, "", "stdout NUL: no partial output is surfaced");
                shj_proc_result_free(r);
        }

        r = run_helper("emit-nul-err", NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_INTERNAL,
                             "stderr NUL: malformed output is rejected");
                CHECK_INT_EQ(r->spawn_errno, EILSEQ, "stderr NUL: spawn_errno is EILSEQ");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "NUL tests: no zombie left");
}

static void test_sigchld_disposition(void)
{
        struct sigaction saved, ign;
        struct shj_proc_result *r;

        test_section("proc: SIGCHLD disposition established before spawning");

        if (sigaction(SIGCHLD, NULL, &saved) != 0) {
                test_fail("sigchld: existing disposition could not be read");
                return;
        }
        memset(&ign, 0, sizeof(ign));
        ign.sa_handler = SIG_IGN;
        sigemptyset(&ign.sa_mask);
        if (sigaction(SIGCHLD, &ign, NULL) != 0) {
                test_fail("sigchld: SIG_IGN could not be installed");
                return;
        }

        /* With SIGCHLD ignored by the parent, children are auto-reaped and
         * waitpid() fails with ECHILD; shoji must re-establish SIG_DFL so
         * the spawn still completes normally instead of reporting an
         * internal error. */
        r = run_helper("echo", "reaped under ignored SIGCHLD");
        if (r) {
                CHECK_INT_EQ(r->exit, 0,
                             "ignored SIGCHLD: child reaped, not an internal error");
                CHECK_STR_EQ(r->out, "reaped under ignored SIGCHLD\n",
                             "ignored SIGCHLD: output captured");
                shj_proc_result_free(r);
        }
        CHECK_INT_EQ(count_zombie_children(), 0, "ignored SIGCHLD: no zombie left");

        (void)sigaction(SIGCHLD, &saved, NULL);
}

static void test_truncation(void)
{
        struct shj_proc_result *r;

        test_section("proc: 4 MiB truncation");

        /* 8 MiB on each stream: both caps must be hit, both streams must
         * keep draining past the cap (else the child wedges on a full pipe
         * and cannot exit 0), and the flags must say so. */
        shj_proc_set_timeout_ms(20000);
        r = run_helper("emit", "8192");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "emit 8 MiB: child exits 0 (no drain deadlock)");
                CHECK_INT_EQ((long)strlen(r->out), CAP_BYTES,
                             "emit 8 MiB: stdout capped at 4 MiB");
                CHECK_INT_EQ((long)strlen(r->err), CAP_BYTES,
                             "emit 8 MiB: stderr capped at 4 MiB");
                CHECK_INT_EQ(r->truncated, SHOJI_TRUNC_OUT | SHOJI_TRUNC_ERR,
                             "emit 8 MiB: both streams flagged truncated");
                shj_proc_result_free(r);
        }

        r = run_helper("emit", "64");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "emit 64 KiB: child exits 0");
                CHECK_INT_EQ((long)strlen(r->out), 64L * 1024L, "emit 64 KiB: stdout complete");
                CHECK_INT_EQ(r->truncated, 0, "emit 64 KiB: under cap, not truncated");
                shj_proc_result_free(r);
        }
}

static void test_reap_hygiene(void)
{
        struct shj_proc_result *r;
        int i, zombies;

        test_section("proc: cleanup hygiene");

        /* Several timeout kills in a row must not leave reaping behind. */
        shj_proc_set_timeout_ms(200);
        for (i = 0; i < 3; i++) {
                r = run_helper("hang", NULL);
                if (r)
                        shj_proc_result_free(r);
        }
        zombies = count_zombie_children();
        if (zombies >= 0)
                CHECK_INT_EQ(zombies, 0, "after 3 timeouts: no zombie children");
        else
                test_ok("zombie scan skipped (/proc unavailable)");
        shj_proc_set_timeout_ms(5000);
}

static void test_qs_environment(void)
{
        const char *names[] = { "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST" };
        char *saved[3] = { NULL, NULL, NULL };
        int had[3] = { 0, 0, 0 };
        const char *argv[] = { NULL, "qs-env", NULL };
        struct shj_proc_result *r;

        test_section("proc: Quickshell selector environment");
        argv[0] = getenv(HELPER_ENV);
        for (int i = 0; i < 3; i++) {
                const char *value = getenv(names[i]);

                if (value) {
                        saved[i] = shj_strdup(value);
                        had[i] = 1;
                }
                setenv(names[i], "inherited-config", 1);
        }

        r = shj_proc_run_qs(argv, NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "Quickshell selectors removed in child");
                CHECK_STR_EQ(r->out, "clean\n", "child receives sanitized environment");
                for (int i = 0; i < 3; i++)
                        CHECK_STR_EQ(getenv(names[i]), "inherited-config",
                                     "parent environment remains unchanged");
                shj_proc_result_free(r);
        } else {
                test_fail("Quickshell environment subprocess returned no result");
        }
        for (int i = 0; i < 3; i++) {
                if (had[i]) {
                        setenv(names[i], saved[i], 1);
                        free(saved[i]);
                } else {
                        unsetenv(names[i]);
                }
        }
}

void test_proc(void)
{
        long saved = shj_proc_get_timeout_ms();

        if (!getenv(HELPER_ENV) || !*getenv(HELPER_ENV)) {
                test_section("proc: subprocess lifecycle");
                test_fail("proc tests skipped: " HELPER_ENV " unset (run via make unit/test)");
                return;
        }

        test_capture_and_exit();
        test_closed_standard_descriptor();
        test_timeout_kills_wrapper_descendants();
        test_timeout_overflow();
        test_spawn_failure();
        test_spawn_failure_eacces();
        test_spawn_failure_enoexec();
        test_fd_hygiene();
        test_timeout_lifecycle();
        test_embedded_nul();
        test_sigchld_disposition();
        test_truncation();
        test_reap_hygiene();
        test_qs_environment();

        shj_proc_set_timeout_ms(saved);
}
