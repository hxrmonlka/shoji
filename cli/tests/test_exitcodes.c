/* shoji-cli tests -- exit code table stability. */
#include "testmain.h"
#include "exitcodes.h"

void test_exitcodes(void)
{
	test_section("exit codes");
	/* Compositor keybind integrations depend on these values; changing
	 * them is a breaking change. */
	CHECK_INT_EQ(SHOJI_EXIT_OK, 0, "ok is 0");
	CHECK_INT_EQ(SHOJI_EXIT_FAILED, 1, "quickshell failure is 1");
	CHECK_INT_EQ(SHOJI_EXIT_USAGE, 64, "usage is 64");
	CHECK_INT_EQ(SHOJI_EXIT_BADIPC, 65, "bad ipc target/function is 65");
	CHECK_INT_EQ(SHOJI_EXIT_NOSTORE, 66, "store unresolved/missing is 66");
	CHECK_INT_EQ(SHOJI_EXIT_NOINSTANCE, 67, "no matching instance is 67");
	CHECK_INT_EQ(SHOJI_EXIT_AMBIGUOUS, 68, "ambiguous instances is 68");
	CHECK_INT_EQ(SHOJI_EXIT_NOQS, 69, "quickshell unavailable is 69");
	CHECK_INT_EQ(SHOJI_EXIT_INTERNAL, 70, "internal is 70");
}
