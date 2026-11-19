/*
 * shoji-cli -- exit codes.
 *
 * Keep this table stable: MangoWM and other compositor integrations rely on
 * it. Diagnostics go to stderr, command output to stdout.
 */
#ifndef SHOJI_EXITCODES_H
#define SHOJI_EXITCODES_H

enum shoji_exit {
	SHOJI_EXIT_OK = 0,        /* success */
	SHOJI_EXIT_FAILED = 1,    /* quickshell process failed or unspecified error */
	SHOJI_EXIT_USAGE = 64,    /* invalid command or argument */
	SHOJI_EXIT_BADIPC = 65,   /* invalid IPC target, function or argument */
	SHOJI_EXIT_NOSTORE = 66,  /* shoji store path unresolved, missing or invalid */
	SHOJI_EXIT_NOINSTANCE = 67, /* no matching running instance */
	SHOJI_EXIT_AMBIGUOUS = 68,  /* multiple matching instances */
	SHOJI_EXIT_NOQS = 69,     /* quickshell not installed or unavailable */
	SHOJI_EXIT_INTERNAL = 70, /* internal error */
};

#endif /* SHOJI_EXITCODES_H */
