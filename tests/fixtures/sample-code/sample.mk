# Solarized Dark TrueColor Showcase: Modern GNU Make Build System
# Demonstrates pattern rules, conditionals, automatic variables, and recipes.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all

PROJECT_NAME := solarized-gateway
VERSION ?= 1.4.0
BUILD_DIR := build
SRC_DIR := src
PORT ?= 8080
DEBUG ?= 0

CC ?= clang
CFLAGS := -std=c17 -O2 -Wall -Wextra
LDFLAGS := -pthread

SRCS := $(wildcard $(SRC_DIR)/*.c)
OBJS := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SRCS))
GIT_COMMIT := $(shell git rev-parse --short HEAD)

export PROJECT_NAME VERSION PORT

-include config.local.mk

ifeq ($(DEBUG),1)
    CFLAGS += -g3 -O0 -DSOLARIZED_DEBUG=1
else
    CFLAGS += -DNDEBUG=1
endif

ifdef EXTRA_LDFLAGS
    LDFLAGS += $(EXTRA_LDFLAGS)
endif

ifndef PREFIX
    PREFIX := /usr/local
endif

.PHONY: all build test install clean
.DELETE_ON_ERROR:
.ONESHELL:

all: build test

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	@printf "[CC] %s -> %s\n" "$*" "$@"
	$(CC) $(CFLAGS) -c $< -o $@

build: $(OBJS)
	@mkdir -p $(BUILD_DIR)/bin
	$(CC) $(CFLAGS) $^ $(LDFLAGS) -o $(BUILD_DIR)/bin/$(PROJECT_NAME)

test: build
	@if [ ! -x "$(BUILD_DIR)/bin/$(PROJECT_NAME)" ]; then \
		echo "missing binary: $(BUILD_DIR)/bin/$(PROJECT_NAME)" >&2; \
		exit 1; \
	fi
	+$(BUILD_DIR)/bin/$(PROJECT_NAME) --self-test --port $(PORT)

install: build
	@install -d "$(DESTDIR)$(PREFIX)/bin"
	@install -m 0755 "$(BUILD_DIR)/bin/$(PROJECT_NAME)" "$(DESTDIR)$(PREFIX)/bin/$(PROJECT_NAME)"

clean:
	-rm -rf $(BUILD_DIR)
