# shoji-cli -- Makefile
#
# Build:   make            (or: make build)
# Test:    make test       (unit tests + e2e against a mock quickshell)
# Install: make install PREFIX=/usr/local

CC      ?= cc
CFLAGS  ?= -O2
CFLAGS  += -std=c11 -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE -Wall -Wextra -Wshadow -Wno-unused-parameter
# Packaging hook (Lumina / Alice): bake the exact Shoji store path in so the
# resolver can use it as the build-time source:
#   CFLAGS += -DSHOJI_DEFAULT_STORE='"$(shojiStorePath)"'
LDFLAGS ?=
AR      ?= ar

SRC_DIR := src
TEST_DIR := tests
BUILD   := obj

LIB_OBJS := $(BUILD)/util.o $(BUILD)/json.o $(BUILD)/proc.o $(BUILD)/resolver.o \
            $(BUILD)/instances.o $(BUILD)/ipctable.o $(BUILD)/dispatch.o \
            $(BUILD)/report.o $(BUILD)/cli.o

CLI_OBJS := $(LIB_OBJS) $(BUILD)/main.o

UNIT_OBJS := $(BUILD)/testmain.o $(BUILD)/test_parser.o $(BUILD)/test_commands.o \
             $(BUILD)/test_resolver.o $(BUILD)/test_instances.o $(BUILD)/test_json.o \
             $(BUILD)/test_exitcodes.o

CLI_BIN := $(BUILD)/shoji
TEST_BIN := $(BUILD)/shoji-tests

.PHONY: all build test unit e2e clean install check-qml
all: build

build: $(CLI_BIN)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: $(SRC_DIR)/%.c $(wildcard $(SRC_DIR)/*.h) | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(CLI_BIN): $(CLI_OBJS)
	$(CC) $(CFLAGS) -o $@ $(CLI_OBJS) $(LDFLAGS)

$(TEST_BIN): $(UNIT_OBJS) $(LIB_OBJS)
	$(CC) $(CFLAGS) -o $@ $(UNIT_OBJS) $(LIB_OBJS) $(LDFLAGS)

$(BUILD)/test%.o: $(TEST_DIR)/test%.c | $(BUILD)
	$(CC) $(CFLAGS) -I$(SRC_DIR) -c -o $@ $<

unit: $(TEST_BIN)
	$(TEST_BIN)

e2e: $(CLI_BIN)
	$(TEST_DIR)/run_e2e.sh $(CLI_BIN)

check-qml:
	$(TEST_DIR)/run_e2e.sh --qml-only $(CLI_BIN)

test: unit e2e check-qml

clean:
	rm -rf $(BUILD)

install: $(CLI_BIN)
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(CLI_BIN) $(DESTDIR)$(PREFIX)/bin/shoji
