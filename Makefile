.DEFAULT_GOAL := help
.PHONY: setup bootstrap install system uninstall test test-system-setup test-dotfiles test-bin test-theme test-ide-fleet test-env test-zsh test-completions test-vim test-fonts lint check all help

# Force 24-bit TrueColor and isolate tests from any caller tmux or IDE Editor RPC session
unexport TMUX TMUX_PANE NVIM_IDE_SOCKET NVIM_IDE_PANE IDE_SESSION
export COLORTERM ?= truecolor
ifeq ($(COLORTERM),)
export COLORTERM := truecolor
endif

## setup: Run full machine setup (packages, apps, dotfiles, tools).
setup:
	@./setup.sh --system

## system: Full machine provisioning with native OS packages (requires sudo).
system:
	@./setup.sh --system

## bootstrap: Alias for system setup (full machine bootstrap).
bootstrap: setup

## install: Install dotfiles, bin utilities, fonts, plugins, and user tools (user-space, no sudo).
install:
	@./setup.sh --dotfiles-only

## uninstall: Uninstall all managed dotfiles, fonts, and user tools.
uninstall:
	@./setup.sh --uninstall

## test: Run unit and integration test suites in parallel.
test:
	@tmpdir="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmpdir"' EXIT INT TERM; \
	suites="system-setup:bash:tests/test-system-setup.sh dotfiles:bash:tests/test-dotfiles.sh bin:bash:tests/test-bin.sh theme:bash:tests/test-theme.sh ide-fleet:bash:tests/test-ide-fleet.sh env:bash:tests/test-env.sh zsh:zsh:tests/test-zsh.zsh completions:bash:tests/test-completions.sh vim:bash:tests/test-vim.sh fonts:bash:tests/test-fonts.sh"; \
	pids=""; \
	for spec in $$suites; do \
		name="$${spec%%:*}"; rest="$${spec#*:}"; runner="$${rest%%:*}"; script="$${rest#*:}"; \
		( "$$runner" "$$script" > "$$tmpdir/$$name.out" 2>&1; echo $$? > "$$tmpdir/$$name.rc" ) & \
		pids="$$pids $$!"; \
	done; \
	for pid in $$pids; do wait "$$pid" || true; done; \
	failed=0; \
	for spec in $$suites; do \
		name="$${spec%%:*}"; \
		cat "$$tmpdir/$$name.out"; \
		rc="$$(cat "$$tmpdir/$$name.rc" 2>/dev/null || echo 1)"; \
		if [ "$$rc" -ne 0 ]; then failed=1; fi; \
	done; \
	if [ "$$failed" -ne 0 ]; then exit 1; fi; \
	echo "All tests passed successfully."

test-system-setup:
	@bash tests/test-system-setup.sh

test-dotfiles:
	@bash tests/test-dotfiles.sh

test-bin:
	@bash tests/test-bin.sh

test-theme:
	@bash tests/test-theme.sh

test-ide-fleet:
	@bash tests/test-ide-fleet.sh

test-env:
	@bash tests/test-env.sh

test-zsh:
	@zsh tests/test-zsh.zsh

test-completions:
	@bash tests/test-completions.sh

test-vim:
	@bash tests/test-vim.sh

test-fonts:
	@bash tests/test-fonts.sh

## lint: Run syntax validation, shellcheck, and documentation hygiene checks.
lint:
	@echo "Checking zsh syntax..."
	@zsh -n dotfiles/.aliases dotfiles/.zsh-functions dotfiles/.zshrc-addendum dotfiles/.zsh-completions dotfiles/.p10k.zsh tests/test-zsh.zsh
	@echo "Checking bash script syntax with 'bash -n'..."
	@bash -n dotfiles/.aliases dotfiles/.bashrc-addendum dotfiles/.environment-variables setup.sh bin/* lib/*.sh modules/*.sh tests/*.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck on bash/sh scripts..."; \
		jobs=$$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4); \
		case "$$jobs" in ''|*[!0-9]*|0) jobs=4 ;; esac; \
		[ "$$jobs" -gt 8 ] && jobs=8; \
		printf '%s\0' dotfiles/.bashrc-addendum tests/*.sh bin/* setup.sh modules/*.sh lib/*.sh dotfiles/.aliases dotfiles/.environment-variables \
			| xargs -0 -n 1 -P "$$jobs" shellcheck --severity=warning -e SC2148,SC2154; \
	else \
		echo "shellcheck not found in PATH (skipped shellcheck static analysis)."; \
	fi
	@echo "Checking embedded Python AST syntax..."
	@bash -c '. tests/test-helper.sh && lint_python_embeds .'
	@echo "Checking documentation hygiene and links..."
	@bash -c '. tests/test-helper.sh && lint_documentation .'
	@echo "All lint checks passed."

## check: Run both lint and test suites.
check: lint test

## all: Alias for check (lint and test).
all: check

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
