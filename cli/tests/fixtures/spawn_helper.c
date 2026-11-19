/* spawn-helper -- deterministic child for shoji-cli unit tests.
 * Executes nothing but its own modes, so proc tests never need a shell or
 * a real Quickshell session.
 *
 * Usage: spawn-helper <mode> [arg ...]
 *   echo <text>      write <text> + newline to stdout, exit 0
 *   echo-err <text>  write <text> + newline to stderr, exit 0
 *   exit <code>      exit with <code>
 *   sig <signum>     raise <signum> (default termination, reported 128+n)
 *   hang             sleep forever (timeout paths)
 *   emit <kib>       write <kib> KiB to stdout AND stderr in alternating
 *                    64 KiB chunks, exit 0 (truncation + concurrent drain)
 *   emit-hang <kib>  emit, then sleep forever (partial capture on timeout)
 *   slow-exit <ms>   sleep <ms>, exit 0 (timeout-disabled mode)
 *   fork-marker <p> <pid-file> leave a child that writes marker <p> after 500 ms
 *   close-pipes-sleep <ms> close stdout/stderr, sleep, then exit 0
 */
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void hang(void)
{
        for (;;)
                pause(); /* returns only on caught signals; loop anyway */
}

static void emit(long kib)
{
        static char chunk[65536];
        long total = kib * 1024;
        long written = 0;

        memset(chunk, 'x', sizeof(chunk));
        while (written < total) {
                size_t take = (size_t)(total - written) < sizeof(chunk)
                                  ? (size_t)(total - written)
                                  : sizeof(chunk);

                fwrite(chunk, 1, take, stdout);
                fflush(stdout);
                fwrite(chunk, 1, take, stderr);
                fflush(stderr);
                written += (long)take;
        }
}

int main(int argc, char **argv)
{
        if (argc < 2)
                return 2;

        if (strcmp(argv[1], "qs-env") == 0) {
                if (getenv("QS_CONFIG_PATH") || getenv("QS_CONFIG_NAME") ||
                    getenv("QS_MANIFEST"))
                        return 3;
                puts("clean");
                return 0;
        }
        if (strcmp(argv[1], "echo") == 0 && argc >= 3) {
                printf("%s\n", argv[2]);
                return 0;
        }
        if (strcmp(argv[1], "echo-err") == 0 && argc >= 3) {
                fprintf(stderr, "%s\n", argv[2]);
                return 0;
        }
        if (strcmp(argv[1], "exit") == 0 && argc >= 3)
                return atoi(argv[2]);
        if (strcmp(argv[1], "sig") == 0 && argc >= 3) {
                kill(getpid(), atoi(argv[2]));
                hang();
                return 3;
        }
        if (strcmp(argv[1], "hang") == 0) {
                hang();
                return 4;
        }
        if (strcmp(argv[1], "emit") == 0 && argc >= 3) {
                emit(atol(argv[2]));
                return 0;
        }
        if (strcmp(argv[1], "emit-hang") == 0 && argc >= 3) {
                emit(atol(argv[2]));
                hang();
                return 4;
        }
        if (strcmp(argv[1], "slow-exit") == 0 && argc >= 3) {
                int ms = atoi(argv[2]);
                struct timespec ts = { .tv_sec = ms / 1000,
                                       .tv_nsec = (long)(ms % 1000) * 1000000L };

                nanosleep(&ts, NULL);
                return 0;
        }
        if (strcmp(argv[1], "fork-marker") == 0 && argc >= 4) {
                pid_t child = fork();

                if (child < 0)
                        return 3;
                if (child == 0) {
                        struct timespec ts = { .tv_sec = 0, .tv_nsec = 500000000L };
                        char pid_text[32];
                        int fd;
                        int n = snprintf(pid_text, sizeof(pid_text), "%ld\n", (long)getpid());

                        fd = open(argv[3], O_WRONLY | O_CREAT | O_TRUNC, 0600);
                        if (fd >= 0) {
                                if (n > 0)
                                        (void)write(fd, pid_text, (size_t)n);
                                close(fd);
                        }

                        nanosleep(&ts, NULL);
                        fd = open(argv[2], O_WRONLY | O_CREAT | O_TRUNC, 0600);
                        if (fd >= 0) {
                                (void)write(fd, "survived\n", 9);
                                close(fd);
                        }
                        _exit(0);
                }
                return 0;
        }
        if (strcmp(argv[1], "close-pipes-sleep") == 0 && argc >= 3) {
                int ms = atoi(argv[2]);
                struct timespec ts = { .tv_sec = ms / 1000,
                                       .tv_nsec = (long)(ms % 1000) * 1000000L };

                close(STDOUT_FILENO);
                close(STDERR_FILENO);
                nanosleep(&ts, NULL);
                return 0;
        }
        return 2;
}
