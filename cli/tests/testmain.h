/* shoji-cli -- tiny test harness (no external dependencies). */
#ifndef SHOJI_TESTMAIN_H
#define SHOJI_TESTMAIN_H

/* Record one passing assertion. */
void test_ok(const char *name);
/* Record one failing assertion (prints the name). */
void test_fail(const char *name);
/* Print a section banner. */
void test_section(const char *name);
/* Print the summary and return the process exit code (0/1). */
int test_summary(void);
/* Assert helpers. */
#define CHECK(cond, name) do { if (cond) test_ok(name); else test_fail(name); } while (0)
#define CHECK_STR_EQ(a, b, name) do { \
	const char *_a = (a), *_b = (b); \
	if (_a && _b && strcmp(_a, _b) == 0) test_ok(name); \
	else test_fail(name); \
} while (0)
#define CHECK_INT_EQ(a, b, name) do { \
	long _a = (long)(a), _b = (long)(b); \
	if (_a == _b) test_ok(name); else test_fail(name); \
} while (0)

/* strcmp for tests (declared here so suites include only this header). */
#include <string.h>

#endif /* SHOJI_TESTMAIN_H */
