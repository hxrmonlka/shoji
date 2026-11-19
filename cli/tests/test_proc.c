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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
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
        const char *argv[4];
        struct shj_proc_result *r;
        struct timespec pause = { .tv_sec = 0, .tv_nsec = 650000000L };

        test_section("proc: timeout cancels wrapper descendants");
        if (!dir) {
                test_fail("descendant timeout: fixture directory created");
                return;
        }
        snprintf(marker, sizeof(marker), "%s/marker", dir);
        argv[0] = getenv(HELPER_ENV);
        argv[1] = "fork-marker";
        argv[2] = marker;
        argv[3] = NULL;
        shj_proc_set_timeout_ms(150);
        r = shj_proc_run(argv, NULL);
        if (r) {
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_TIMEOUT,
                             "descendant timeout: wrapper exceeds deadline");
                shj_proc_result_free(r);
        }
        nanosleep(&pause, NULL);
        CHECK(access(marker, F_OK) != 0,
              "descendant timeout: child did not write marker after Shoji returned");
        unlink(marker);
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
                CHECK_INT_EQ(r->exit, SHJ_PROC_EXIT_INTERNAL,
                             "LONG_MAX timeout returns internal error");
                CHECK_INT_EQ(r->spawn_errno, ERANGE,
                             "LONG_MAX timeout reports checked deadline overflow");
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
        shj_proc_set_timeout_ms(0);
        r = run_helper("slow-exit", "250");
        if (r) {
                CHECK_INT_EQ(r->exit, 0, "timeout 0: slow child not killed");
                shj_proc_result_free(r);
        }
        shj_proc_set_timeout_ms(5000);
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
        test_fd_hygiene();
        test_timeout_lifecycle();
        test_truncation();
        test_reap_hygiene();

        shj_proc_set_timeout_ms(saved);
}
