REPO_DIR := $(shell pwd)

.PHONY: setup install uninstall \
        install-dotfiles uninstall-dotfiles \
        install-fonts uninstall-fonts \
        install-bin uninstall-bin \
        test lint help

## setup: Run full master setup (system packages, apps, dotfiles, vim, zsh, mise).
setup:
	@./setup.sh

## install: Install all dotfiles, fonts, plugins, and user bin tools (user-space, no sudo).
install:
	@./setup.sh --dotfiles-only

## uninstall: Uninstall all managed dotfiles, fonts, and user bin symlinks.
uninstall: uninstall-bin uninstall-fonts uninstall-dotfiles
	@echo "All home settings uninstalled."

## install-dotfiles: Symlink dotfiles into HOME directory.
install-dotfiles:
	@echo "Installing dotfiles..."
	ln -sf "$(REPO_DIR)/dotfiles/.environment_variables" "$(HOME)/.environment_variables"
	ln -sf "$(REPO_DIR)/dotfiles/.bashrc-addendum"       "$(HOME)/.bashrc-addendum"
	ln -sf "$(REPO_DIR)/dotfiles/.zshrc_addendum"       "$(HOME)/.zshrc_addendum"
	ln -sf "$(REPO_DIR)/dotfiles/.zsh_aliases"          "$(HOME)/.zsh_aliases"
	ln -sf "$(REPO_DIR)/dotfiles/.zsh_functions"        "$(HOME)/.zsh_functions"
	ln -sf "$(REPO_DIR)/dotfiles/.zsh_completions"      "$(HOME)/.zsh_completions"
	ln -sf "$(REPO_DIR)/dotfiles/.p10k.zsh"             "$(HOME)/.p10k.zsh"
	ln -sf "$(REPO_DIR)/dotfiles/.vimrc"                "$(HOME)/.vimrc"
	mkdir -p "$(HOME)/.dir_colors"
	ln -sf "$(REPO_DIR)/dotfiles/.dir_colors/dircolors" "$(HOME)/.dir_colors/dircolors"
	@if [ -d "$(REPO_DIR)/.vim/UltiSnips" ]; then \
	    mkdir -p "$(HOME)/.vim"; \
	    ln -sfn "$(REPO_DIR)/.vim/UltiSnips" "$(HOME)/.vim/UltiSnips"; \
	fi

## uninstall-dotfiles: Remove managed dotfile symlinks.
uninstall-dotfiles:
	@echo "Removing dotfile symlinks..."
	rm -f "$(HOME)/.environment_variables"
	rm -f "$(HOME)/.bashrc-addendum"
	rm -f "$(HOME)/.zshrc_addendum"
	rm -f "$(HOME)/.zsh_aliases"
	rm -f "$(HOME)/.zsh_functions"
	rm -f "$(HOME)/.zsh_completions"
	rm -f "$(HOME)/.p10k.zsh"
	rm -f "$(HOME)/.vimrc"
	rm -f "$(HOME)/.vim/UltiSnips"
	rm -f "$(HOME)/.dir_colors/dircolors"

## install-fonts: Install MesloLGS NF Powerlevel10k patched fonts.
install-fonts:
	@./setup.sh --dotfiles-only --skip-tools --skip-vim --skip-zsh --skip-bash --skip-bin --skip-completions

## uninstall-fonts: Remove MesloLGS NF fonts.
uninstall-fonts:
	@echo "Removing MesloLGS NF fonts..."
	@rm -f "$(HOME)/Library/Fonts/MesloLGS NF"*.ttf 2>/dev/null || true
	@rm -f "$${XDG_DATA_HOME:-$(HOME)/.local/share}/fonts/MesloLGS NF"*.ttf 2>/dev/null || true
	@if command -v fc-cache >/dev/null 2>&1; then \
	    fc-cache -f "$${XDG_DATA_HOME:-$(HOME)/.local/share}/fonts" >/dev/null 2>&1 || true; \
	fi

## install-bin: Symlink common-bin utilities to ~/bin.
install-bin:
	@echo "Symlinking common-bin utilities to $(HOME)/bin..."
	@mkdir -p "$(HOME)/bin"
	@for f in $(REPO_DIR)/common-bin/*; do \
	    if [ -f "$$f" ]; then \
	        chmod +x "$$f"; \
	        ln -sf "$$f" "$(HOME)/bin/$$(basename "$$f")"; \
	    fi; \
	done

## uninstall-bin: Remove installed common-bin utilities from ~/bin.
uninstall-bin:
	@echo "Removing common-bin utilities from $(HOME)/bin..."
	@if [ -d "$(HOME)/bin" ]; then \
	    for f in $(REPO_DIR)/common-bin/*; do \
	        rm -f "$(HOME)/bin/$$(basename "$$f")"; \
	    done; \
	fi

## test: Run unit and integration test suites.
test:
	@echo "Running System & Cross-Platform Engine tests..."
	@bash tests/test_system_setup.sh
	@echo "Running Environment & Bash tests..."
	@bash tests/test_env.sh
	@echo "Running Zsh tests..."
	@zsh tests/test_zsh.zsh
	@echo "Running Completions tests..."
	@bash tests/test_completions.sh
	@echo "Running Vim tests..."
	@bash tests/test_vim.sh
	@echo "Running Font tests..."
	@bash tests/test_fonts.sh
	@echo "All tests passed successfully."

## lint: Run syntax validation and shellcheck.
lint:
	@echo "Checking zsh syntax..."
	@zsh -n dotfiles/.zsh_aliases dotfiles/.zsh_functions dotfiles/.zshrc_addendum dotfiles/.zsh_completions dotfiles/.p10k.zsh
	@echo "Checking bash script syntax with 'bash -n'..."
	@bash -n setup.sh common-bin/* tests/*.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck on bash/sh scripts..."; \
		shellcheck setup.sh common-bin/* tests/*.sh; \
	else \
		echo "shellcheck not found in PATH (skipped shellcheck static analysis)."; \
	fi
	@echo "All lint checks passed."

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
