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
	ln -sf "$(REPO_DIR)/dotfiles/.environment-variables" "$(HOME)/.environment-variables"
	ln -sf "$(REPO_DIR)/dotfiles/.bashrc-addendum"       "$(HOME)/.bashrc-addendum"
	ln -sf "$(REPO_DIR)/dotfiles/.zshrc-addendum"        "$(HOME)/.zshrc-addendum"
	ln -sf "$(REPO_DIR)/dotfiles/.zsh-aliases"           "$(HOME)/.zsh-aliases"
	ln -sf "$(REPO_DIR)/dotfiles/.zsh-functions"         "$(HOME)/.zsh-functions"
	ln -sf "$(REPO_DIR)/dotfiles/.zsh-completions"       "$(HOME)/.zsh-completions"
	ln -sf "$(REPO_DIR)/dotfiles/.p10k.zsh"              "$(HOME)/.p10k.zsh"
	ln -sf "$(REPO_DIR)/dotfiles/.vimrc"                "$(HOME)/.vimrc"
	mkdir -p "$(HOME)/.dir-colors"
	ln -sf "$(REPO_DIR)/dotfiles/.dir-colors/dircolors"  "$(HOME)/.dir-colors/dircolors"
	mkdir -p "$${XDG_CONFIG_HOME:-$(HOME)/.config}"
	@if [ -d "$${XDG_CONFIG_HOME:-$(HOME)/.config}/nvim" ] && [ ! -L "$${XDG_CONFIG_HOME:-$(HOME)/.config}/nvim" ]; then \
		mv "$${XDG_CONFIG_HOME:-$(HOME)/.config}/nvim" "$${XDG_CONFIG_HOME:-$(HOME)/.config}/nvim.bak.$$(date +%s)"; \
	fi
	ln -sfn "$(REPO_DIR)/dotfiles/.config/nvim"          "$${XDG_CONFIG_HOME:-$(HOME)/.config}/nvim"
	mkdir -p "$${XDG_CONFIG_HOME:-$(HOME)/.config}/bat/themes"
	ln -sf "$(REPO_DIR)/colors/Solarized-Dark-TrueColor.tmTheme" "$${XDG_CONFIG_HOME:-$(HOME)/.config}/bat/themes/Solarized-Dark-TrueColor.tmTheme"
	@if command -v bat >/dev/null 2>&1; then bat cache --build >/dev/null 2>&1 || true; fi
	@if command -v batcat >/dev/null 2>&1; then batcat cache --build >/dev/null 2>&1 || true; fi

## uninstall-dotfiles: Remove managed dotfile symlinks.
uninstall-dotfiles:
	@echo "Removing dotfile symlinks..."
	rm -f "$(HOME)/.environment-variables"
	rm -f "$(HOME)/.bashrc-addendum"
	rm -f "$(HOME)/.zshrc-addendum"
	rm -f "$(HOME)/.zsh-aliases"
	rm -f "$(HOME)/.zsh-functions"
	rm -f "$(HOME)/.zsh-completions"
	rm -f "$(HOME)/.p10k.zsh"
	rm -f "$(HOME)/.vimrc"
	rm -f "$(HOME)/.dir-colors/dircolors"
	rm -f "$${XDG_CONFIG_HOME:-$(HOME)/.config}/nvim"
	rm -f "$${XDG_CONFIG_HOME:-$(HOME)/.config}/bat/themes/Solarized-Dark-TrueColor.tmTheme"

## install-fonts: Install MesloLGS NF Powerlevel10k patched fonts.
install-fonts:
	@./setup.sh --dotfiles-only --skip-tools --skip-nvim --skip-vim --skip-zsh --skip-bash --skip-bin --skip-completions

## uninstall-fonts: Remove MesloLGS NF fonts.
uninstall-fonts:
	@echo "Removing MesloLGS NF fonts..."
	@rm -f "$(HOME)/Library/Fonts/MesloLGS NF"*.ttf 2>/dev/null || true
	@rm -f "$${XDG_DATA_HOME:-$(HOME)/.local/share}/fonts/MesloLGS NF"*.ttf 2>/dev/null || true
	@if command -v fc-cache >/dev/null 2>&1; then \
	    fc-cache -f "$${XDG_DATA_HOME:-$(HOME)/.local/share}/fonts" >/dev/null 2>&1 || true; \
	fi

## install-bin: Symlink common-bin utilities to ~/.local/bin.
install-bin:
	@echo "Symlinking common-bin utilities to $(HOME)/.local/bin..."
	@mkdir -p "$(HOME)/.local/bin"
	@for f in $(REPO_DIR)/common-bin/*; do \
	    if [ -f "$$f" ]; then \
	        chmod +x "$$f"; \
	        ln -sf "$$f" "$(HOME)/.local/bin/$$(basename "$$f")"; \
	    fi; \
	done

## uninstall-bin: Remove installed common-bin utilities from ~/.local/bin.
uninstall-bin:
	@echo "Removing common-bin utilities from $(HOME)/.local/bin..."
	@if [ -d "$(HOME)/.local/bin" ]; then \
	    for f in $(REPO_DIR)/common-bin/*; do \
	        rm -f "$(HOME)/.local/bin/$$(basename "$$f")"; \
	    done; \
	fi

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
	@zsh -n dotfiles/.zsh-aliases dotfiles/.zsh-functions dotfiles/.zshrc-addendum dotfiles/.zsh-completions dotfiles/.p10k.zsh
	@echo "Checking bash script syntax with 'bash -n'..."
	@bash -n setup.sh bootstrap.sh common-bin/* tests/*.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck on bash/sh scripts..."; \
		shellcheck --severity=warning setup.sh bootstrap.sh common-bin/* tests/*.sh; \
	else \
		echo "shellcheck not found in PATH (skipped shellcheck static analysis)."; \
	fi
	@echo "All lint checks passed."

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
