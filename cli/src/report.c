#define _POSIX_C_SOURCE 200809L

#include "report.h"
#include "dispatch.h"
#include "exitcodes.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* JSON helpers                                                        */
/* ------------------------------------------------------------------ */

static void json_escaped(struct shj_sbuf *b, const char *s)
{
	if (!s)
		s = "";
	shj_sbuf_addch(b, '"');
	for (; *s; s++) {
		switch (*s) {
		case '"': shj_sbuf_add(b, "\\\""); break;
		case '\\': shj_sbuf_add(b, "\\\\"); break;
		case '\n': shj_sbuf_add(b, "\\n"); break;
		case '\r': shj_sbuf_add(b, "\\r"); break;
		case '\t': shj_sbuf_add(b, "\\t"); break;
		default:
			if ((unsigned char)*s < 0x20)
				shj_sbuf_addf(b, "\\u%04x", (unsigned char)*s);
			else
				shj_sbuf_addch(b, *s);
		}
	}
	shj_sbuf_addch(b, '"');
}

/* Emit one instance as a JSON object and close it. `ipc_accessible` is a
 * tri-state: -1 omits the property (statuses where no probe ran), 0/1 emit
 * the JSON boolean false/true. Closing the object here keeps every caller's
 * output exactly one valid JSON object. */
static void json_instance(struct shj_sbuf *b, const struct shoji_instance *inst,
                          int matches_expected, int store_known, int ipc_accessible)
{
	shj_sbuf_add(b, "{\"id\":");
	json_escaped(b, inst->id);
	shj_sbuf_addf(b, ",\"pid\":%ld,\"alive\":%s", inst->pid,
	              inst->dead ? "false" : "true");
	shj_sbuf_add(b, ",\"shell_id\":");
	json_escaped(b, inst->shell_id);
	shj_sbuf_add(b, ",\"config_path\":");
	json_escaped(b, inst->config_path);
	shj_sbuf_add(b, ",\"launch_time\":");
	json_escaped(b, inst->launch_time);
	if (store_known)
		shj_sbuf_addf(b, ",\"matches_expected\":%s",
		              matches_expected ? "true" : "false");
	else
		shj_sbuf_add(b, ",\"matches_expected\":null");
	if (ipc_accessible >= 0)
		shj_sbuf_addf(b, ",\"ipc_accessible\":%s",
		              ipc_accessible ? "true" : "false");
	shj_sbuf_addch(b, '}');
}

/* ------------------------------------------------------------------ */
/* shared helpers                                                      */
/* ------------------------------------------------------------------ */

static int instance_matches(const struct shoji_context *ctx, const struct shoji_instance *inst)
{
	if (!ctx->have_store || !inst)
		return 0;
	/* 1 = the configuration identity is established; 0/-1 (uncertain)
	 * count as not matching: an unestablishable generation must never
	 * look like a match in status or list output. */
	return shoji_instance_matches_config(inst, ctx->store.shell_qml) == 1;
}

static const char *verdict_for(const struct shoji_context *ctx,
                               const struct shoji_pipeline *pl)
{
	if (!pl->list)
		return "discovery-failed";
	if (!pl->have_store)
		return "unknown-store";
	switch (pl->sel.status) {
	case SHOJI_SELECT_OK:
		if (!pl->sel.selected)
			return "unknown";
		if (pl->sel.selected->dead)
			return "selected-instance-dead";
		if (!instance_matches(ctx, pl->sel.selected))
			return "override-mismatch";
		return "match";
	case SHOJI_SELECT_NONE:
		return pl->sel.dead_match_count > 0 ? "no-instance-dead-only" : "no-match";
	case SHOJI_SELECT_AMBIGUOUS:
		return "ambiguous";
	case SHOJI_SELECT_ERROR:
		return "discovery-failed";
	}
	return "unknown";
}

static void status_json(struct shoji_context *ctx, const struct shoji_pipeline *pl,
                        const char *qs_resolved, const char *qs_version)
{
	struct shj_sbuf b;

	shj_sbuf_init(&b);
	shj_sbuf_add(&b, "{\"cli\":");
	json_escaped(&b, "shoji-cli " SHOJI_CLI_VERSION);
	shj_sbuf_add(&b, ",\"quickshell\":{\"bin\":");
	json_escaped(&b, ctx->qs_bin);
	shj_sbuf_add(&b, ",\"resolved\":");
	json_escaped(&b, qs_resolved);
	shj_sbuf_add(&b, ",\"version\":");
	json_escaped(&b, qs_version);
	shj_sbuf_add(&b, "},\"store\":{\"resolved\":");
	shj_sbuf_add(&b, pl->have_store ? "true" : "false");
	shj_sbuf_add(&b, ",\"source\":");
	json_escaped(&b, pl->have_store ? ctx->store.source_name : NULL);
	shj_sbuf_add(&b, ",\"detail\":");
	json_escaped(&b, pl->have_store ? ctx->store.source_detail : NULL);
	shj_sbuf_add(&b, ",\"dir\":");
	json_escaped(&b, pl->have_store ? ctx->store.dir : NULL);
	shj_sbuf_add(&b, ",\"shell_qml\":");
	json_escaped(&b, pl->have_store ? ctx->store.shell_qml : NULL);
	shj_sbuf_add(&b, "},\"instances\":[");
	if (pl->list) {
		for (int i = 0; i < pl->list->count; i++) {
			struct shoji_instance *inst = &pl->list->items[i];

			if (i)
				shj_sbuf_addch(&b, ',');
			json_instance(&b, inst, instance_matches(ctx, inst), pl->have_store, -1);
		}
	}
	shj_sbuf_add(&b, "],\"verdict\":");
	json_escaped(&b, verdict_for(ctx, pl));
	shj_sbuf_add(&b, "}\n");
	fputs(b.s, stdout);
	shj_sbuf_free(&b);
}

/* ------------------------------------------------------------------ */
/* status                                                              */
/* ------------------------------------------------------------------ */

int shoji_cmd_status(struct shoji_context *ctx, const struct shoji_options *opts)
{
	struct shoji_pipeline pl;
	char *qs_resolved = shj_find_in_path(ctx->qs_bin, NULL);
	char *qs_version = shoji_qs_version(ctx);
	int code;

	shoji_context_resolve_store(ctx, opts);
	shoji_pipeline_run(ctx, opts, 0, &pl);
	code = !pl.list ? (pl.exit_code ? pl.exit_code : SHOJI_EXIT_FAILED) : SHOJI_EXIT_OK;

	if (opts->json) {
		status_json(ctx, &pl, qs_resolved, qs_version);
		shoji_pipeline_release(&pl);
		free(qs_resolved);
		free(qs_version);
		return code;
	}

	printf("shoji-cli %s\n", SHOJI_CLI_VERSION);
	printf("quickshell: %s -> %s (%s)\n", ctx->qs_bin,
	       qs_resolved ? qs_resolved : "not found on $PATH",
	       qs_version ? qs_version : "version unknown");

	if (ctx->have_store) {
		printf("store path: %s\n", ctx->store.shell_qml);
		printf("  directory: %s\n", ctx->store.dir);
		printf("  source: %s (%s)\n", ctx->store.source_name,
		       ctx->store.source_detail ? ctx->store.source_detail : "-");
	} else {
		printf("store path: unresolved\n");
		printf("  set --store or SHOJI_STORE_PATH; see `shoji doctor`\n");
	}

	if (!pl.list) {
		printf("instances: discovery failed\n");
		shoji_pipeline_release(&pl);
		free(qs_resolved);
		free(qs_version);
		return code;
	}

	printf("instances: %d running, %d dead total\n",
	       shoji_live_count(pl.list), pl.list->count - shoji_live_count(pl.list));
	for (int i = 0; i < pl.list->count; i++) {
		struct shoji_instance *inst = &pl.list->items[i];
		int match = instance_matches(ctx, inst);

		printf("  %s %-20s pid %-8s %-13s %s (launched %s)\n",
		       match ? "*" : " ", inst->id,
		       inst->dead ? "(dead)" : "",
		       match ? "MATCH" : "other config",
		       inst->config_path ? inst->config_path : "?",
		       inst->launch_time ? inst->launch_time : "?");
	}
	printf("verdict: %s\n", verdict_for(ctx, &pl));

	shoji_pipeline_release(&pl);
	free(qs_resolved);
	free(qs_version);
	return code;
}

/* ------------------------------------------------------------------ */
/* doctor                                                              */
/* ------------------------------------------------------------------ */

static void doctor_check(int failed, int warned, const char *name, const char *detail)
{
	printf("  [%s] %s%s%s\n", failed ? "fail" : warned ? "warn" : "ok",
	       name, detail && *detail ? ": " : "", detail ? detail : "");
}

int shoji_cmd_doctor(struct shoji_context *ctx, const struct shoji_options *opts)
{
	struct shoji_pipeline pl;
	int failures = 0;
	char *qs_resolved = NULL;
	char *qs_version = NULL;

	printf("shoji doctor\n");

	/* 1. quickshell executable */
	qs_resolved = shj_find_in_path(ctx->qs_bin, NULL);
	qs_version = shoji_qs_version(ctx);
	doctor_check(!qs_resolved, 0, "quickshell executable",
	             qs_resolved ? qs_resolved
	                         : "not found; install quickshell or set --qs / SHOJI_QS_BIN");
	if (!qs_resolved)
		failures++;
	doctor_check(!qs_version, 0, "quickshell version",
	             qs_version ? qs_version : "`qs --version` failed");
	if (!qs_version)
		failures++;
	free(qs_resolved);
	free(qs_version);

	/* 2. store path */
	shoji_context_resolve_store(ctx, opts);
	if (!ctx->have_store) {
		doctor_check(1, 0, "shoji store path", "unresolved");
		shj_hint("try --store /path/to/shoji (a directory or shell.qml), or set "
		         "SHOJI_STORE_PATH; when packaged, shoji-cli gets SHOJI_DEFAULT_STORE "
		         "baked in");
		failures++;
	} else {
		struct shj_sbuf b;

		shj_sbuf_init(&b);
		shj_sbuf_addf(&b, "%s (source: %s", ctx->store.shell_qml,
		              ctx->store.source_name);
		if (ctx->store.source_detail)
			shj_sbuf_addf(&b, ": %s", ctx->store.source_detail);
		shj_sbuf_add(&b, ")");
		doctor_check(0, 0, "shoji store path", b.s);
		shj_sbuf_free(&b);
	}

	/* 3. instance discovery */
	shoji_pipeline_run(ctx, opts, 0, &pl);
	if (!pl.list) {
		doctor_check(1, 0, "instance discovery",
		             "`qs list -a -j` failed; is quickshell running and is "
		             "XDG_RUNTIME_DIR set?");
		failures++;
	} else {
		struct shj_sbuf b;

		shj_sbuf_init(&b);
		shj_sbuf_addf(&b, "%d running, %d dead",
		              shoji_live_count(pl.list),
		              pl.list->count - shoji_live_count(pl.list));
		doctor_check(0, 0, "instance discovery", b.s);
		shj_sbuf_free(&b);

		/* 4. expected configuration running */
		if (!ctx->have_store) {
			doctor_check(1, 0, "expected configuration running",
			             "store path unresolved, instances cannot be matched");
			failures++;
		} else if (pl.sel.status == SHOJI_SELECT_OK && pl.sel.selected &&
		           !pl.sel.selected->dead) {
			doctor_check(0, 0, "expected configuration running",
			             pl.sel.selected->id);
		} else if (pl.sel.status == SHOJI_SELECT_AMBIGUOUS) {
			doctor_check(0, 1, "expected configuration running",
			             "multiple instances match; dispatch requires --instance-id");
		} else {
			struct shj_sbuf b2;

			shj_sbuf_init(&b2);
			if (pl.sel.dead_match_count > 0)
				shj_sbuf_addf(&b2, "no live instance of %s (but %d dead instance(s) "
				                    "exist; the shell may have crashed or been replaced)",
				              ctx->store.shell_qml, pl.sel.dead_match_count);
			else if (pl.sel.uncertain_matches > 0)
				shj_sbuf_addf(&b2, "%d running instance(s) of %s cannot be selected "
				                    "automatically (the recorded path's launch-time target "
				                    "cannot be established); dispatch explicitly with --instance-id",
				              pl.sel.uncertain_matches, ctx->store.shell_qml);
			else
				shj_sbuf_addf(&b2, "no live instance of %s; start it with "
				                    "`qs -p %s`",
				              ctx->store.shell_qml, ctx->store.shell_qml);
			doctor_check(1, 0, "expected configuration running", b2.s);
			shj_sbuf_free(&b2);
			failures++;
		}

		/* 5. IPC accessibility */
		if (pl.sel.status == SHOJI_SELECT_OK && pl.sel.selected &&
		    !pl.sel.selected->dead) {
			if (shoji_ipc_probe(ctx, pl.sel.selected) == 0)
				doctor_check(0, 0, "IPC accessibility", pl.sel.selected->id);
			else {
				doctor_check(1, 0, "IPC accessibility",
				             "`qs ipc show` failed for the selected instance; check "
				             "WAYLAND_DISPLAY (systemd/keybind contexts) and restart "
				             "the shell if it just crashed");
				failures++;
			}
		}
	}

	shoji_pipeline_release(&pl);
	return failures ? SHOJI_EXIT_FAILED : SHOJI_EXIT_OK;
}

/* ------------------------------------------------------------------ */
/* instance commands                                                   */
/* ------------------------------------------------------------------ */

int shoji_cmd_instance_list(struct shoji_context *ctx, const struct shoji_options *opts)
{
	struct shoji_pipeline pl;

	shoji_pipeline_run(ctx, opts, 0, &pl);
	if (!pl.list) {
		shoji_pipeline_release(&pl);
		return pl.exit_code ? pl.exit_code : SHOJI_EXIT_FAILED;
	}

	if (opts->json) {
		struct shj_sbuf b;

		shj_sbuf_init(&b);
		shj_sbuf_addch(&b, '[');
		for (int i = 0; i < pl.list->count; i++) {
			struct shoji_instance *inst = &pl.list->items[i];

			if (i)
				shj_sbuf_addch(&b, ',');
			json_instance(&b, inst, instance_matches(ctx, inst), pl.have_store, -1);
		}
		shj_sbuf_addch(&b, ']');
		shj_sbuf_addch(&b, '\n');
		fputs(b.s, stdout);
		shj_sbuf_free(&b);
	} else {
		printf("%-22s %-8s %-6s %-8s %s\n", "ID", "PID", "STATE", "MATCH", "CONFIG PATH");
		for (int i = 0; i < pl.list->count; i++) {
			struct shoji_instance *inst = &pl.list->items[i];
			int match = instance_matches(ctx, inst);

			printf("%-22s %-8s %-6s %-8s %s\n",
			       inst->id,
			       inst->dead ? "-" : "",
			       inst->dead ? "dead" : "live",
			       pl.have_store ? (match ? "yes" : "no") : "unknown",
			       inst->config_path ? inst->config_path : "?");
		}
	}

	shoji_pipeline_release(&pl);
	return SHOJI_EXIT_OK;
}

int shoji_cmd_instance_current(struct shoji_context *ctx, const struct shoji_options *opts)
{
	struct shoji_pipeline pl;
	int code = SHOJI_EXIT_OK;
	const struct shoji_instance *inst;

	shoji_pipeline_run(ctx, opts, 1, &pl);
	if (pl.exit_code != SHOJI_EXIT_OK) {
		code = pl.exit_code;
		goto out;
	}

	inst = pl.sel.selected;
	if (opts->json) {
		struct shj_sbuf b;

		shj_sbuf_init(&b);
		json_instance(&b, inst, instance_matches(ctx, inst), pl.have_store, -1);
		shj_sbuf_addch(&b, '\n');
		fputs(b.s, stdout);
		shj_sbuf_free(&b);
	} else {
		printf("instance: %s\n", inst->id);
		printf("pid: %ld\n", inst->pid);
		printf("config path: %s\n", inst->config_path ? inst->config_path : "?");
		printf("matches expected configuration: %s\n",
		       pl.have_store ? (instance_matches(ctx, inst) ? "yes" : "no") : "unknown");
	}

out:
	shoji_pipeline_release(&pl);
	return code;
}

int shoji_cmd_instance_inspect(struct shoji_context *ctx, const struct shoji_options *opts)
{
	struct shoji_pipeline pl;
	int code = SHOJI_EXIT_OK;
	const struct shoji_instance *inst;

	shoji_pipeline_run(ctx, opts, 1, &pl);
	if (pl.exit_code != SHOJI_EXIT_OK) {
		code = pl.exit_code;
		goto out;
	}

	inst = pl.sel.selected;
	if (opts->json) {
		struct shj_sbuf b;
		int probe = shoji_ipc_probe(ctx, inst);

		shj_sbuf_init(&b);
		json_instance(&b, inst, instance_matches(ctx, inst), pl.have_store,
		              probe == 0);
		shj_sbuf_addch(&b, '\n');
		fputs(b.s, stdout);
		shj_sbuf_free(&b);
	} else {
		int probe = shoji_ipc_probe(ctx, inst);

		printf("instance id:    %s\n", inst->id);
		printf("pid:            %ld (%s)\n", inst->pid, inst->dead ? "dead" : "alive");
		printf("shell id:       %s\n", inst->shell_id ? inst->shell_id : "?");
		printf("config path:    %s\n", inst->config_path ? inst->config_path : "?");
		printf("launched:       %s\n", inst->launch_time ? inst->launch_time : "?");
		if (pl.have_store) {
			int match = instance_matches(ctx, inst);

			printf("expected config:%s %s\n", match ? "" : " ",
			       ctx->store.shell_qml);
			printf("actual config:  %s%s\n", inst->config_path ? " " : "",
			       inst->config_path ? inst->config_path : "?");
			printf("match:          %s\n", match ? "yes" : "NO");
		} else {
			printf("expected config: unresolved store path; match unknown\n");
		}
		printf("ipc accessible: %s\n", probe == 0 ? "yes" : "no");
	}

out:
	shoji_pipeline_release(&pl);
	return code;
}
