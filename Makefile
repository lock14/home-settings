.DEFAULT_GOAL := help
.PHONY: install system uninstall lint test test-system-setup test-dotfiles test-bin test-theme test-ide-fleet test-env test-zsh test-completions test-vim test-fonts check help

## install: Install dotfiles, bin utilities, fonts, plugins, and user tools (user-space, no sudo).
install:
	@./setup.sh --user

## system: Full machine provisioning with native OS packages (requires sudo).
system:
	@./setup.sh --system

## uninstall: Uninstall all managed dotfiles, fonts, and user tools.
uninstall:
	@./setup.sh --uninstall

## lint: Run syntax validation, ShellCheck, Python AST, and documentation hygiene checks.
lint:
	@./tests/lint.sh

## test: Run unit and integration test suites in parallel.
test:
	@./tests/run.sh

test-system-setup test-dotfiles test-bin test-theme test-ide-fleet test-env test-zsh test-completions test-vim test-fonts:
	@./tests/run.sh $(@:test-%=%)

## check: Run both lint and test suites.
check: lint test

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
