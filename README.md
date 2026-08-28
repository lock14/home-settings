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

### Single-Command Setup (Recommended for new machines)

On a fresh Linux or macOS machine:

```bash
git clone https://github.com/lock14/home-settings.git
cd home-settings
./bootstrap.sh
```

`./bootstrap.sh` will:
1. Request sudo privileges once up front.
2. Refresh package manager indexes and install missing prerequisites (`make`, `git`, `curl`, `zsh`, `fzf`, `vim`, `fontconfig`).
3. Set your default login shell to Zsh.
4. Symlink all dotfiles, install MesloLGS NF fonts, and set up Oh-My-Zsh plugins and themes via `make install`.

### Dotfiles only (if base packages are already installed)

```bash
make install    # symlinks all dotfiles into $HOME
```

---

## File & Directory Overview

| Path | Description |
|------|-------------|
| `bootstrap.sh` | Turnkey setup script: installs base packages, sets default shell, runs `make install` |
| `Makefile` | Symlink-based dotfile installer (`make install`) |
| `user-setup.sh` | User-level orchestrator: runs `make install` and GNOME terminal setup |
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

1. Clone this repository:
   ```bash
   git clone https://github.com/lock14/home-settings.git && cd home-settings
   ```
2. Run `./bootstrap.sh` to install base packages, set default shell, and configure dotfiles.
3. (Optional) Run the distro-specific script (e.g. `./ubuntu/ubuntu_18+_setup.sh`) if you wish to install desktop IDEs and dev tools.
4. Restart your shell or run `exec zsh`.

---

## Development

- Use `bash_script_template.sh` as a starting point for any new scripts.
- All scripts use `set -euo pipefail` — fail fast, fail loudly.
- Line endings are enforced as LF via `.gitattributes`.
