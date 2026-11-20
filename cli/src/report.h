/* shoji-cli -- status, doctor and instance reporting commands. */
#ifndef SHOJI_REPORT_H
#define SHOJI_REPORT_H

#include "dispatch.h"
#include "cli.h"

int shoji_cmd_status(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_doctor(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_kill(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_instance_list(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_instance_current(struct shoji_context *ctx, const struct shoji_options *opts);
int shoji_cmd_instance_inspect(struct shoji_context *ctx, const struct shoji_options *opts);

#endif /* SHOJI_REPORT_H */
