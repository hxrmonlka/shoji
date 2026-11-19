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

        test_section("proc: exec failure errno classes");

        if (!dir) {
                test_fail("non-executable file: fixture setup failed");
                return;
        }
        nos = shj_path_join(dir, "not-executable");
        {
                FILE *f = fopen(nos, "w");

                fputs("#!/bin/sh\nexit 0\n", f);
                fclose(f);
        }
        chmod(nos, 0600); /* never executable, for root and non-root alike */

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
        test_spawn_failure();
        test_spawn_failure_eacces();
        test_timeout_lifecycle();
        test_truncation();
        test_reap_hygiene();

        shj_proc_set_timeout_ms(saved);
}
