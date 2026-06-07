# home-settings

Home directory configuration files and setup automation for \*nix systems (Ubuntu 18+, Fedora 30+).

---

## Prerequisites

The following tools must be available before running any setup scripts:

- `bash` (5+)
- `git`
- `curl`
- `wget`
- `sudo` access

---

## Quick Start

### Ubuntu 18+

```bash
git clone https://github.com/<you>/home-settings.git
cd home-settings
./ubuntu/ubuntu_18+_setup.sh          # install system packages & IDEs
./user-setup.sh                        # install dotfiles, vim, zsh
```

### Fedora 30+

```bash
git clone https://github.com/<you>/home-settings.git
cd home-settings
./fedora/fedora_30+_setup.sh          # install system packages & IDEs
./user-setup.sh                        # install dotfiles, vim, zsh
```

### Dotfiles only (any distro)

```bash
make install    # symlinks all dotfiles into $HOME
```

---

## File & Directory Overview

| Path | Description |
|------|-------------|
| `Makefile` | Symlink-based dotfile installer (`make install`) |
| `user-setup.sh` | Top-level orchestrator: runs bin, bash, zsh, vim, and gnome-terminal setup |
| `bash-setup.sh` | Appends `bashrc-addendum` to `~/.bashrc`, copies `environment_variables` |
| `zsh-setup.sh` | Installs zsh, oh-my-zsh, powerlevel10k, and plugins; detects apt/dnf |
| `vim-setup.sh` | Installs pathogen + solarized colorscheme, symlinks `.vimrc` |
| `bin-setup.sh` | Creates `~/bin` and syncs `common-bin/` scripts into it |
| `gnome-terminal-setup.sh` | Applies GNOME terminal color profile |
| `bashrc-addendum` | Appended to `~/.bashrc` — sources `environment_variables` and dircolors |
| `zshrc_addendum` | Appended to `~/.zshrc` — sources aliases, functions, env vars, dircolors |
| `zsh_aliases` | Zsh aliases for git, Go, Terraform, and misc tools |
| `zsh_functions` | Zsh functions: `fs` (fd+tree), `gsync` (rebase branch onto default) |
| `environment_variables` | Exported env vars: `EDITOR`, `PATH` additions for `~/software/bin`, Go SDK |
| `LS_COLORS` | Custom `LS_COLORS` / dircolors definition |
| `.vimrc` | Vim config: pathogen, UltiSnips, solarized, smart bracket/quote pairing |
| `.vim/` | Vim plugin directory (pathogen bundles, UltiSnips snippets) |
| `common-bin/` | Cross-distro utility scripts (see below) |
| `code-style/` | Eclipse Java formatter XML profiles (Google style, AOSP style, custom) |
| `ubuntu/` | Ubuntu-specific setup and bin scripts |
| `fedora/` | Fedora-specific setup and bin scripts |
| `bash_script_template.sh` | Template for new bash scripts with `set -euo pipefail` + getopts |

### `common-bin/` Scripts

| Script | Description |
|--------|-------------|
| `gen-passwd` | Generate random passwords; flags for char sets, length defaults to 16 |
| `install-go` | Download and install a specific Go version; detects amd64/arm64 |
| `switch-go` | Switch active Go version via symlink in `~/software/sdk/go` |
| `install-tf` | Download and install a specific Terraform version |
| `mvn-release` | Cut a Maven release: branch, tag, deploy, bump SNAPSHOT |
| `repeat-until-success` | Retry a command up to N times with a configurable sleep interval |
| `sum` | Sum numbers from stdin |

---

## Adding a New Machine

1. Clone this repo.
2. Run the distro-specific setup script for your OS.
3. Run `./user-setup.sh` (or `make install` for dotfiles only).
4. Log out and back in (or `exec zsh`) to pick up the new shell.

---

## Development

- Use `bash_script_template.sh` as a starting point for any new scripts.
- All scripts use `set -euo pipefail` — fail fast, fail loudly.
- Line endings are enforced as LF via `.gitattributes`.
