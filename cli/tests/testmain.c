#include "testmain.h"

#include <stdio.h>

static int g_pass = 0;
static int g_fail = 0;

void test_ok(const char *name)
{
        g_pass++;
        printf("  ok   %s\n", name);
}

void test_fail(const char *name)
{
        g_fail++;
        printf("  FAIL %s\n", name);
}

void test_section(const char *name)
{
        printf("== %s ==\n", name);
}

int test_summary(void)
{
        printf("\n%d passed, %d failed\n", g_pass, g_fail);
        return g_fail ? 1 : 0;
}

/* Suite entry points. */
void test_json(void);
void test_parser(void);
void test_commands(void);
void test_resolver(void);
void test_instances(void);
void test_exitcodes(void);
void test_proc(void);

int main(void)
{
        test_exitcodes();
        test_json();
        test_parser();
        test_commands();
        test_resolver();
        test_instances();
        test_proc();
        return test_summary();
}
