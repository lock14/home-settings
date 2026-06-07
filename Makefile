REPO_DIR := $(shell pwd)

.PHONY: install uninstall

## install: Symlink all dotfiles into $HOME so edits in the repo are live immediately.
install:
	@echo "Symlinking dotfiles from $(REPO_DIR) into $(HOME)..."
	ln -sf "$(REPO_DIR)/.vimrc"               "$(HOME)/.vimrc"
	ln -sf "$(REPO_DIR)/.vim"                 "$(HOME)/.vim"
	ln -sf "$(REPO_DIR)/zsh_aliases"          "$(HOME)/.zsh_aliases"
	ln -sf "$(REPO_DIR)/zsh_functions"        "$(HOME)/.zsh_functions"
	ln -sf "$(REPO_DIR)/zshrc_addendum"       "$(HOME)/.zshrc_addendum"
	ln -sf "$(REPO_DIR)/bashrc-addendum"      "$(HOME)/.bashrc-addendum"
	ln -sf "$(REPO_DIR)/environment_variables" "$(HOME)/.environment_variables"
	ln -sf "$(REPO_DIR)/LS_COLORS"            "$(HOME)/.dir_colors/dircolors"
	@# Append zshrc_addendum source line to ~/.zshrc if not already present
	@grep -qxF 'source ~/.zshrc_addendum' "$(HOME)/.zshrc" 2>/dev/null || \
	    echo '\n# home-settings\n[ -f ~/.zshrc_addendum ] && source ~/.zshrc_addendum' >> "$(HOME)/.zshrc"
	@# Append bashrc-addendum source line to ~/.bashrc if not already present
	@grep -qxF 'source ~/.bashrc-addendum' "$(HOME)/.bashrc" 2>/dev/null || \
	    echo '\n# home-settings\n[ -f ~/.bashrc-addendum ] && source ~/.bashrc-addendum' >> "$(HOME)/.bashrc"
	@echo "Done. Restart your shell or run: exec zsh"

## uninstall: Remove the symlinks created by 'make install'.
uninstall:
	@echo "Removing dotfile symlinks..."
	rm -f "$(HOME)/.vimrc"
	rm -f "$(HOME)/.vim"
	rm -f "$(HOME)/.zsh_aliases"
	rm -f "$(HOME)/.zsh_functions"
	rm -f "$(HOME)/.zshrc_addendum"
	rm -f "$(HOME)/.bashrc-addendum"
	rm -f "$(HOME)/.environment_variables"
	rm -f "$(HOME)/.dir_colors/dircolors"
	@echo "Done."

## help: Show available make targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
