.DEFAULT_GOAL := help
.PHONY: setup bootstrap install uninstall test lint check all help

## setup: Run full machine setup (packages, apps, dotfiles, tools).
setup:
	@./setup.sh

## bootstrap: Alias for setup (full machine bootstrap).
bootstrap: setup

## install: Install dotfiles, fonts, plugins, and user tools (user-space, no sudo).
install:
	@./setup.sh --dotfiles-only

## uninstall: Uninstall all managed dotfiles, fonts, and user tools.
uninstall:
	@./setup.sh --uninstall

## test: Run unit and integration test suites.
test:
	@echo "Running System & Cross-Platform Engine tests..."
	@bash tests/test-system-setup.sh
	@echo "Running Environment & Bash tests..."
	@bash tests/test-env.sh
	@echo "Running Zsh tests..."
	@zsh tests/test-zsh.zsh
	@echo "Running Completions tests..."
	@bash tests/test-completions.sh
	@echo "Running Vim & Neovim tests..."
	@bash tests/test-vim.sh
	@echo "Running Font tests..."
	@bash tests/test-fonts.sh
	@echo "All tests passed successfully."

## lint: Run syntax validation and shellcheck.
lint:
	@echo "Checking zsh syntax..."
	@zsh -n dotfiles/.aliases dotfiles/.zsh-functions dotfiles/.zshrc-addendum dotfiles/.zsh-completions dotfiles/.p10k.zsh tests/test-zsh.zsh
	@echo "Checking bash script syntax with 'bash -n'..."
	@bash -n dotfiles/.aliases dotfiles/.bashrc-addendum dotfiles/.environment-variables setup.sh common-bin/* tests/*.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck on bash/sh scripts..."; \
		shellcheck --severity=warning dotfiles/.bashrc-addendum dotfiles/.environment-variables setup.sh common-bin/* tests/*.sh; \
	else \
		echo "shellcheck not found in PATH (skipped shellcheck static analysis)."; \
	fi
	@echo "All lint checks passed."

## check: Run both lint and test suites.
check: lint test

## all: Alias for check (lint and test).
all: check

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
