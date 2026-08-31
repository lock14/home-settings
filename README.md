# home-settings

Workstation setup automation, prompt themes, developer toolchains, and dotfiles for modern Unix systems (**Ubuntu 22.04+ / 24.04+ LTS**, **Fedora 38+ / 40+**, and **macOS** Apple Silicon / Intel).

---

## Architecture Overview

```text
home-settings/
├── setup.sh                         # Self-bootstrapping master setup & dotfiles engine
├── Makefile                         # Lifecycle targets (install, uninstall, test, lint)
├── .mise.toml                       # Mise polyglot toolchains (Java 21, Go, Python, Node, Terraform, Rust)
├── AGENTS.md                        # Architecture principles & agent directives
│
├── colors/                          # 24-bit TrueColor TextMate themes
│   └── Solarized-Dark-TrueColor.tmTheme  # Canonical Solarized Dark theme for bat
│
├── dotfiles/                        # Centralized, portable dotfile tree
│   ├── .environment-variables       # Sub-millisecond environment, COLORTERM, and PATH exports
│   ├── .bashrc-addendum             # Bash integration hook & zoxide
│   ├── .zshrc-addendum              # Zsh integration hook, zoxide, and plugin loader
│   ├── .aliases                     # Full Git suite, Golang, Terraform, and modern CLI shortcuts (Zsh & Bash)
│   ├── .zsh-functions               # Git synchronization (gsync) & tree search (fs)
│   ├── .zsh-completions             # Fpath completion registration
│   ├── .p10k.zsh                    # Powerlevel10k single-line prompt configuration
│   ├── .vimrc                       # Fallback Solarized Dark Vim configuration
│   ├── .dir-colors/dircolors        # Solarized Dark dircolors database
│   └── .config/
│       └── nvim/                    # Modern Lua Neovim (Lazy.nvim, Native LSP, Treesitter, Telescope)
│           └── init.lua
│
├── common-bin/                      # Standalone Unix utilities (symlinked to ~/.local/bin/)
│   ├── gen-passwd                   # Password generator with custom character sets
│   ├── sum                          # High-performance AWK number summation & stats
│   ├── repeat-until-success         # Command retry loop with configurable delay
│   └── mvn-release                  # Automated Maven release branching and tagging
│
├── .vim/                            # Pathogen autoload runtime (legacy Vim fallback)
│
└── tests/                           # Automated test suites (91+ tests across 6 modules)
    ├── test-system-setup.sh         # Cross-platform CLI validation, bootstrap & dry-run tests
    ├── test-env.sh                  # Environment variables, TrueColor, and bash tests
    ├── test-zsh.zsh                 # Zsh aliases, functions, live git integration tests
    ├── test-completions.sh          # Completion symlinks & generator tests
    ├── test-vim.sh                  # Vim & Neovim configuration & snippet tests
    └── test-fonts.sh                # Cross-platform font installation tests
```

---

## Prerequisites

The following tools should be available on the host machine:

- `bash` (4+)
- `git`
- `curl`
- `wget` (on Linux)
- `sudo` (or Administrator privileges for system provisioning)

---

## Supported Platforms & Toolchains

- **Ubuntu**: Ubuntu 22.04+ LTS (Jammy), Ubuntu 24.04+ LTS (Noble)
- **Fedora**: Fedora 38+ / 40+
- **macOS**: Modern macOS releases (Apple Silicon `arm64` and Intel `x86_64`)
- **Polyglot Toolchains**: Managed via [**`mise`**](https://mise.jdx.dev/) (`.mise.toml`):
  - **Java**: Active LTS releases (`java = "lts"`, non-EOL 17/21/25+)
  - **Node.js**: Active LTS releases (`node = "lts"`)
  - **Go**: Latest stable Go runtime (`go = "latest"`)
  - **Python**: Latest stable Python runtime (`python = "latest"`)
  - **Maven**: Modern Maven build toolchain (`maven = "latest"`)
  - **Terraform**: Latest Terraform binary (`terraform = "latest"`)
  - **Rust**: Latest Rust toolchain (`rust = "latest"`)

---

## Quick Start

### 1. Turnkey Bootstrap (New Machines)

Stream and run directly in Bash without pre-cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/lock14/home-settings/main/setup.sh | bash
```

### 2. Automated Master Setup (Existing Clone)

The master `setup.sh` orchestrator auto-detects your platform (**Ubuntu**, **Fedora**, or **macOS**) and provisions system packages, desktop tools, and user dotfiles:

```bash
git clone https://github.com/lock14/home-settings.git
cd home-settings

# Full automated bootstrap
./setup.sh --bootstrap

# User dotfiles only (no sudo required)
./setup.sh --dotfiles-only

# Preview changes without modifying the system
./setup.sh --dry-run
```

---

## Command-Line Options (`./setup.sh`)

| Option | Default | Description |
| :--- | :--- | :--- |
| `--bootstrap` | *disabled* | Full new machine bootstrap (base packages, shell, tools, dotfiles) |
| `--dotfiles-only` | *disabled* | Configure user dotfiles, fonts, and tools only (no sudo required) |
| `--system-only` | *disabled* | Provision OS packages and CLI runtimes only |
| `--dry-run` | *disabled* | Preview actions without modifying the system |
| `--uninstall` | *disabled* | Uninstall all managed dotfiles, fonts, and user binaries |
| `--uninstall-dotfiles` | *disabled* | Remove managed dotfile symlinks only |
| `--uninstall-fonts` | *disabled* | Remove MesloLGS NF fonts only |
| `--uninstall-bin` | *disabled* | Remove symlinked user utilities from `~/.local/bin` only |
| `--os <distro>` | *auto* | Target OS override: `ubuntu`, `fedora`, `macos` (auto-detected by default) |
| `-j, --jdk <ver>` | `21` | Active Java LTS version: `17`, `21` (default: 21) |
| `--db <engine>` | `none` | Database server engine to install: `postgres`, `mariadb`, `all`, `none` |
| `--with-postgres` | *disabled* | Install PostgreSQL server and client tools |
| `--with-mariadb` | *disabled* | Install MariaDB server and client tools |
| `--skip-db` | *disabled* | Skip all database client and server installations |
| `--with-gui` | *disabled* | Install all GUI desktop applications (Chrome, IDE/VS Code) |
| `--with-chrome` | *disabled* | Install Google Chrome |
| `--with-apps` | *disabled* | Install desktop apps (VS Code / IDE) |
| `-i, --ide <name>` | `none` | IDE to install: `intellij`, `intellij-ultimate`, `code`, `none` |
| `--skip-system` | *disabled* | Skip OS package updates and system provisioning |
| `--skip-packages` | *disabled* | Skip core system package manager installs |
| `--skip-user` | *disabled* | Skip user dotfiles and environment configuration |
| `--skip-fonts` | *disabled* | Skip MesloLGS NF font installation |
| `--skip-tools` | *disabled* | Skip Mise polyglot toolchain runtime installation |
| `--skip-nvim` | *disabled* | Skip Neovim configuration and plugins |
| `--skip-vim` | *disabled* | Skip Vim configuration and plugins |
| `--skip-zsh` | *disabled* | Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k |
| `--skip-bash` | *disabled* | Skip Bash configuration and environment variables |
| `--skip-bin` | *disabled* | Skip `~/.local/bin` user utilities synchronization |
| `--skip-completions`| *disabled* | Skip CLI tab completions generation |

---

## What's Included

### 1. High-Speed ZSH & Powerlevel10k Prompt
- **ZSH** as the primary interactive shell with instant startup (<10ms).
- **Powerlevel10k** single-line prompt with dynamic Git status indicators.
- **`zsh-autosuggestions`** with authentic Solarized Base01 (`fg=10`).
- **`fzf`** interactive fuzzy search (`Ctrl+R`) and tab completion.
- **`zoxide` (`z`)** frecency-based smart directory jumping.

### 2. Modern Rust Developer CLI Suite
- **`bat`**: 24-bit TrueColor syntax-highlighted file viewing with Git gutter markers (`cat <file>`).
- **`ls` / `ll`**: Standard, high-contrast Unix directory listing driven by authentic Solarized `dircolors`.
- **`eza`**: Available via dedicated modern shortcuts (`el` for Git status long-listing, `et` for tree views).
- **`COLORTERM=truecolor`**: Global 24-bit TrueColor export preventing color degradation.
- **`fd` / `fs`**: Lightning-fast file and directory tree search.

### 3. Modern Lua Neovim (`dotfiles/.config/nvim/init.lua`)
- **Native LSP (`mason.nvim` + `nvim-lspconfig` / `vim.lsp.config`)**: Auto-manages Go (`gopls`), Terraform (`terraformls`), Python (`pyright`), YAML (`yamlls`).
- **Treesitter**: AST-based syntax highlighting with 1:1 parity matching `bat`.
- **Telescope**: Fuzzy file finding (`<leader>ff`, `<leader>fg`, `<leader>fb`).
- **Solarized Dark**: Seamless `#002B36` terminal background matching.
- **Editor Aliases**: `vi`, `vim`, `v` mapped to `nvim` (with automatic fallback to legacy `vim`).

---

## Git & Developer Shortcuts

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Interactive fuzzy search command history via `fzf` |
| `z <dir>` | Smart jump to directory via `zoxide` |
| `cat <file>` | Syntax-highlighted file viewing via `bat` with TrueColor Solarized Dark |
| `vi` / `vim` / `v` | Modern Lua Neovim (with automatic fallback to `vim`) |
| `ls` | Standard directory listing with color (`ls --color=auto`) |
| `ll` | Standard long directory listing with hidden files (`ls -alF`) |
| `la` | List almost all files (`ls -A`) |
| `l` | Compact column listing (`ls -CF`) |
| `el` | Detailed eza listing with Git status (`eza -la --git`) |
| `et` | Eza tree view listing (`eza --tree --level=2`) |
| `ea` | Eza list all files (`eza -a`) |
| `fs` | Fast recursive directory tree search (`fd` + `tree --fromfile`) |
| `gcommit` | `git add -A && git commit` |
| `gamend` | `git add -A && git commit --amend --no-edit` |
| `gfetch` | `git fetch` |
| `gpush` / `gpushf` | `git push origin HEAD` / `--force-with-lease` |
| `gpull` | `git pull --rebase origin HEAD` |
| `gup` | `git fetch && git pull --rebase origin HEAD` |
| `gprune` | Delete local branches except `main`/`master` |
| `gsync` | Rebase current branch onto latest `main`/`master` |
| `guser-branch` | Prefix branch with `$USER/` (stripping redundant prefixes) |
| `go-testall` | `go test ./...` |
| `go-buildall` | `go build ./...` |
| `go-lint` | `golangci-lint run` |
| `tf` | `terraform` |
| `yaml-lint` | `yamllint -d relaxed` |

---

## Standalone Utilities (`common-bin/`)

| Script | Description |
|---|---|
| `gen-passwd` | Generate random passwords with configurable character sets (`-u`, `-l`, `-n`, `-s`) and lengths |
| `sum` | Sum numbers from stdin/args with CSV parsing, column filtering (`-k`), human byte units (`-H`), averages (`-a`), and stats (`-s`) |
| `repeat-until-success` | Retry a command up to N times with a configurable sleep interval |
| `mvn-release` | Cut a Maven release: branch, tag, deploy, bump `SNAPSHOT` |

---

## Development & Testing

All scripts enforce `set -euo pipefail` for fail-fast safety.

```bash
# Run full automated test suite (109 tests across 6 test modules)
make test

# Run syntax & lint validation
make lint
```
