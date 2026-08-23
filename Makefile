REPO_DIR := $(shell pwd)

.PHONY: install uninstall \
        install-env uninstall-env \
        install-fonts uninstall-fonts \
        install-completions uninstall-completions \
        install-zsh uninstall-zsh \
        install-bash uninstall-bash \
        install-vim uninstall-vim \
        install-bin uninstall-bin \
        test lint help

## test: Run unit and integration tests for shell and editor configurations.
test:
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


## lint: Run shellcheck and shell syntax validation.
lint:
	@echo "Checking zsh syntax..."
	@zsh -n zsh_aliases zsh_functions zshrc_addendum zsh_completions p10k.zsh
	@echo "Running shellcheck on bash/sh scripts..."
	@shellcheck zsh-setup.sh bash-setup.sh bin-setup.sh font-setup.sh completions-setup.sh gnome-terminal-setup.sh user-setup.sh vim-setup.sh
	@echo "All lint checks passed."

## install: Install all dotfiles, shell configs, vim settings, and user bin tools.
install: install-env install-fonts install-completions install-zsh install-bash install-vim install-bin
	@echo "All home settings installed. Restart your shell or run: exec zsh"

## uninstall: Uninstall all dotfiles, shell configs, vim settings, and user bin tools.
uninstall: uninstall-bin uninstall-vim uninstall-bash uninstall-zsh uninstall-completions uninstall-fonts uninstall-env
	@echo "All home settings uninstalled."

## install-env: Symlink environment variables and LS_COLORS/dircolors.
install-env:
	@echo "Installing environment and color settings..."
	ln -sf "$(REPO_DIR)/environment_variables" "$(HOME)/.environment_variables"
	mkdir -p "$(HOME)/.dir_colors"
	ln -sf "$(REPO_DIR)/LS_COLORS"            "$(HOME)/.dir_colors/dircolors"

## uninstall-env: Remove environment variables and dircolors symlinks.
uninstall-env:
	@echo "Removing environment and color symlinks..."
	rm -f "$(HOME)/.environment_variables"
	rm -f "$(HOME)/.dir_colors/dircolors"

## install-fonts: Install MesloLGS NF Powerlevel10k patched fonts.
install-fonts:
	@echo "Installing MesloLGS NF fonts..."
	./font-setup.sh

## uninstall-fonts: Remove MesloLGS NF fonts from ~/.local/share/fonts.
uninstall-fonts:
	@echo "Removing MesloLGS NF fonts..."
	rm -f "$(HOME)/.local/share/fonts/MesloLGS NF"*.ttf
	@if command -v fc-cache >/dev/null 2>&1; then \
	    fc-cache -f "$(HOME)/.local/share/fonts" >/dev/null 2>&1 || true; \
	fi

## install-completions: Symlink completions and generate CLI completions for gh, kubectl, helm.
install-completions:
	@echo "Installing Zsh completions..."
	./completions-setup.sh

## uninstall-completions: Remove generated completions and symlinks.
uninstall-completions:
	@echo "Removing Zsh completions..."
	rm -f "$(HOME)/.zsh_completions"
	rm -rf "$(HOME)/.zsh/completions"

## install-zsh: Symlink Zsh dotfiles and provision Oh-My-Zsh themes & plugins.
install-zsh:
	@echo "Installing Zsh configuration and plugins..."
	./zsh-setup.sh


## uninstall-zsh: Remove Zsh symlinks.
uninstall-zsh:
	@echo "Removing Zsh symlinks..."
	rm -f "$(HOME)/.zsh_aliases"
	rm -f "$(HOME)/.zsh_functions"
	rm -f "$(HOME)/.zshrc_addendum"
	rm -f "$(HOME)/.zsh_completions"
	rm -f "$(HOME)/.p10k.zsh"



## install-bash: Symlink Bash addendum and register source line in ~/.bashrc.
install-bash:
	@echo "Installing Bash configuration..."
	ln -sf "$(REPO_DIR)/bashrc-addendum"      "$(HOME)/.bashrc-addendum"
	@grep -qxF 'source ~/.bashrc-addendum' "$(HOME)/.bashrc" 2>/dev/null || \
	    echo '\n# home-settings\n[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum' >> "$(HOME)/.bashrc"

## uninstall-bash: Remove Bash addendum symlink.
uninstall-bash:
	@echo "Removing Bash symlinks..."
	rm -f "$(HOME)/.bashrc-addendum"

## install-vim: Symlink .vimrc, UltiSnips snippets, and provision Vim plugins.
install-vim:
	@echo "Installing Vim configuration and plugins..."
	./vim-setup.sh

## uninstall-vim: Remove Vim symlinks.
uninstall-vim:
	@echo "Removing Vim symlinks..."
	rm -f "$(HOME)/.vimrc"
	rm -f "$(HOME)/.vim/UltiSnips"


## install-bin: Populate ~/bin with common-bin utility scripts.
install-bin:
	@echo "Installing common-bin utilities to $(HOME)/bin..."
	./bin-setup.sh

## uninstall-bin: Remove installed common-bin utilities from ~/bin.
uninstall-bin:
	@echo "Removing common-bin utilities from $(HOME)/bin..."
	@if [ -d "$(HOME)/bin" ]; then \
	    for f in $(REPO_DIR)/common-bin/*; do \
	        rm -f "$(HOME)/bin/$$(basename "$$f")"; \
	    done; \
	fi

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'

