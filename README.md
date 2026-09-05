# home-settings

Workstation setup automation, prompt themes, developer toolchains, and dotfiles for modern Unix environments:
- **Debian-based Linux** (Ubuntu 22.04+ / 24.04+ LTS, Debian 12+, Pop!_OS, Linux Mint)
- **RHEL-based Linux** (Fedora 38+ / 40+, RHEL 9+, CentOS Stream, Rocky Linux, AlmaLinux)
- **macOS** (Sonoma, Sequoia; Apple Silicon & Intel)

---

## Architecture Overview

```text
home-settings/
├── setup.sh                         # Modular orchestrator CLI
├── Makefile                         # Lifecycle targets (install, system, uninstall, test, lint)
├── .mise.toml                       # Mise polyglot toolchains (Java LTS, Node LTS, latest Go, Python, etc.)
├── AGENTS.md                        # Architecture principles & agent directives
│
├── bin/                             # Standalone Unix utilities (symlinked to ~/.local/bin/)
│   ├── gen-passwd                   # Password generator with custom character sets
│   ├── mvn-release                  # Automated Maven release branching and tagging
│   ├── repeat-until-success         # Command retry loop with configurable delay
│   └── sum                          # High-performance AWK number summation & stats
│
├── dotfiles/                        # Declarative mirror of $HOME (auto-discovered and linked)
│   ├── .aliases                     # Full Git suite, Golang, Terraform shortcuts (+ auto-loads ~/.aliases.d/*.sh)
│   ├── .bashrc-addendum             # Bash integration hook & zoxide
│   ├── .environment-variables       # Environment, COLORTERM, PATH (+ auto-loads ~/.environment-variables.d/*.sh)
│   ├── .p10k.zsh                    # Powerlevel10k single-line prompt configuration
│   ├── .vimrc                       # Fallback Solarized Dark Vim configuration
│   ├── .zsh-completions             # Fpath completion registration
│   ├── .zsh-functions               # Git synchronization (gsync), search (fs) (+ auto-loads ~/.zsh-functions.d/*.zsh)
│   ├── .zshrc-addendum              # Zsh integration hook, zoxide, and plugin loader
│   ├── .dir-colors/dircolors        # Solarized Dark dircolors database
│   └── .config/
│       └── nvim/                    # Modern Lua Neovim (Lazy.nvim, Native LSP, Treesitter, Telescope)
│           ├── init.lua
│           └── lazy-lock.json
│
├── lib/                             # Shared helper libraries
│   ├── log.sh                       # Terminal logging & dry-run runner
│   ├── os.sh                        # Operating system & architecture detection
│   └── symlink.sh                   # Safe atomic symlinking with directory backup support
│
├── modules/                         # Stage-based single-responsibility modules
│   ├── 00-packages.sh               # System packages, database servers, and desktop apps
│   ├── 10-dotfiles.sh               # Declarative dotfile auto-discovery and mirroring
│   ├── 20-bin.sh                    # User binaries & Debian shims (fd, bat)
│   ├── 30-fonts.sh                  # MesloLGS NF font downloader with disk cache
│   ├── 40-mise.sh                   # Mise runtime manager & polyglot toolchains
│   ├── 50-vim.sh                    # Legacy Vim Pathogen & plugin bundles
│   ├── 60-shell.sh                  # Oh-My-Zsh, plugins, shellrc hooks, completions
│   └── 99-uninstall.sh              # Clean uninstallation of managed components
│
├── colors/                          # 24-bit TrueColor TextMate themes
│   └── Solarized-Dark-TrueColor.tmTheme  # Canonical Solarized Dark theme for bat
│
└── tests/                           # Automated test suites (160+ tests across 8 modules)
    ├── test-helper.sh               # Shared assertion library (pass, fail, assert_*, test_summary)
    ├── test-system-setup.sh         # Cross-platform CLI validation, bootstrap & dry-run tests
    ├── test-dotfiles.sh             # Declarative dotfiles auto-discovery, backup, & drop-ins
    ├── test-bin.sh                  # User binaries symlinking & compatibility shims
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
- `sudo` (or Administrator privileges for system-level package provisioning)

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

### 2. Standard Workflows (Makefile)

```bash
git clone https://github.com/lock14/home-settings.git
cd home-settings

# User-space installation (dotfiles, bin, fonts, tools, shell) [No sudo]
make install

# Full machine provisioning with native OS packages (requires sudo)
make system

# Clean uninstallation of managed dotfiles, binaries, and fonts
make uninstall

# Run complete test suite (160+ tests across 8 modules)
make test

# Run ShellCheck and shell syntax checks
make lint
```

### 3. CLI Orchestrator (`./setup.sh`)

```bash
# Full machine provisioning
./setup.sh --system

# User-space only (equivalent to default or make install)
./setup.sh --dotfiles-only

# Preview changes without modifying the system
./setup.sh --dry-run
```

---

## Command-Line Options (`./setup.sh`)

| Option | Default | Description |
| :--- | :--- | :--- |
| `(default)` | *enabled* | Full machine setup: native OS packages via apt/dnf/brew + user environment (requires `sudo`) |
| `--dotfiles-only` | *disabled* | Configure user dotfiles, fonts, and tools only (no `sudo` required) |
| `--system` | *disabled* | Full turnkey setup with native packages (alias for default) |
| `--bootstrap` | *disabled* | Full new machine bootstrap (base packages, shell, tools, dotfiles) |
| `--system-only` | *disabled* | Provision OS packages and CLI runtimes only |
| `--dry-run` | *disabled* | Preview actions without modifying the system |
| `--uninstall` | *disabled* | Uninstall all managed dotfiles, fonts, and user binaries |
| `--uninstall-dotfiles` | *disabled* | Remove managed dotfile symlinks only |
| `--uninstall-fonts` | *disabled* | Remove MesloLGS NF fonts only |
| `--uninstall-bin` | *disabled* | Remove symlinked user utilities from `~/.local/bin` only |
| `--os <distro>` | *auto* | Target OS family override: `ubuntu` (Debian/apt), `fedora` (RHEL/dnf), `macos` (Homebrew) |
| `--db <engine>` | `none` | Database server engine to install: `postgres`, `mariadb`, `all`, `none` |
| `--with-postgres` | *disabled* | Install PostgreSQL server and client tools |
| `--with-mariadb` | *disabled* | Install MariaDB server and client tools |
| `--skip-db` | *disabled* | Skip all database client and server installations |
| `--with-gui` | *disabled* | Install all GUI desktop applications (Chrome, Ghostty, IDE/VS Code) |
| `--with-ghostty` | *disabled* | Install Ghostty terminal emulator (macOS cask, Snap on Ubuntu, COPR on Fedora) |
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

## Extensibility & Customization

The redesigned repository is built for frictionless extension:

1. **Add a Dotfile**: Drop any file or directory into `dotfiles/`. It is automatically discovered and mirrored to `$HOME` (e.g. `dotfiles/.gitconfig` -> `~/.gitconfig`). Pre-existing physical directories are backed up safely (`.bak.<timestamp>`) to prevent nested symlinks.
2. **Add a CLI Utility**: Drop any script into `bin/` and make it executable. It is automatically symlinked into `~/.local/bin/`.
3. **Drop-in Shell Extensions (`.d/`)**: Keep machine-specific or sensitive configurations in local drop-in directories without committing them to the repository:
   - `~/.environment-variables.d/*.sh`: Custom exports and paths (sourced by `.environment-variables`).
   - `~/.aliases.d/*.sh`: Custom aliases (sourced by `.aliases`).
   - `~/.zsh-functions.d/*.zsh`: Custom Zsh functions (sourced by `.zsh-functions`).
4. **Add a Provisioning Stage**: Drop a new numbered script into `modules/` (e.g. `modules/70-docker.sh`).

---

## What's Included

### 1. High-Speed ZSH & Powerlevel10k Prompt
- **ZSH** as the primary interactive shell with instant startup (<10ms).
- **Powerlevel10k** single-line prompt with dynamic Git status indicators.
- **`zsh-syntax-highlighting`**: Authentic 24-bit TrueColor Solarized Dark command highlighting (commands in green `#859900`, options/strings in cyan `#2AA198`, numbers in magenta `#D33682`, variables in yellow `#B58900`, errors in red `#DC322F`).
- **`zsh-autosuggestions`** with authentic Solarized Base01 (`fg=10`).
- **`ZLE`** selection (`#073642` Base02) and search highlighting.
- **`fzf`** interactive fuzzy search (`Ctrl+R`) and tab completion.
- **`zoxide` (`z`)** frecency-based smart directory jumping.

### 2. Modern Rust Developer CLI Suite
- **`bat`**: 24-bit TrueColor syntax-highlighted file viewing with Git gutter markers (`bat <file>` or `b <file>`; `cat` remains coreutils).
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

### 4. Ghostty GPU-Accelerated Terminal (`dotfiles/.config/ghostty/config`)
- **Theme**: Authentic 24-bit TrueColor Solarized Dark (`theme = "Solarized Dark"`) with 1:1 RGB palette matching Windows Terminal.
- **Typography**: MesloLGS NF font (`font-family = "MesloLGS NF"`, `font-size = 11`) supporting all Powerlevel10k and Git status glyphs.
- **Window & Layout**: 10px padding, balanced geometry, and block cursor.
- **Productivity**: Auto-split panes (`Ctrl+Shift+D`), navigation (`Ctrl+Shift+H/J/K/L`), and zoom toggle (`Ctrl+Shift+Enter`).
- **Cross-Platform**: Automatically symlinked to `${XDG_CONFIG_HOME:-~/.config}/ghostty/config` and macOS `~/Library/Application Support/com.mitchellh.ghostty/config`.

---

## Git & Developer Shortcuts

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Interactive fuzzy search command history via `fzf` |
| `z <dir>` | Smart jump to directory via `zoxide` |
| `b <file>` / `bat` | Syntax-highlighted file viewing via `bat` with TrueColor Solarized Dark (`cat` remains pure coreutils) |
| `vi` / `vim` / `v` | Modern Lua Neovim (with automatic fallback to `vim`) |
| `ls` | Standard directory listing with color (`ls --color=auto`) |
| `ll` | Standard long directory listing with hidden files (`ls -alF`) |
| `la` | List almost all files (`ls -A`) |
| `l` | Compact column listing (`ls -CF`) |
| `e` | Modern grid listing with Nerd Font icons (`eza --icons=auto`) |
| `el` | Detailed eza listing with table headers, Git status, and icons (`eza -la --icons=auto --git --header`) |
| `et` | Eza tree view listing with icons (`eza --tree --level=2 --icons=auto`) |
| `elt` | Detailed eza tree view with Git status and metadata (`eza -la --tree --level=2 --icons=auto --git`) |
| `fs` | Fast recursive directory tree search (`fd` + `tree --fromfile`) |
| `gcommit` | `git add -A && git commit` |
| `gamend` | `git add -A && git commit --amend --no-edit` |
| `gfetch` | `git fetch` |
| `gpush` / `gpushf` | `git push origin HEAD` / `--force-with-lease` |
| `gpull` | `git pull --rebase --autostash` |
| `gup` | `git fetch && git pull --rebase --autostash` |
| `gprune` | Safely delete merged local branches |
| `gpurge` | Nuclear force-delete (`-D`) local branches except `main`/`master` |
| `gsync` | Rebase current branch onto latest `main`/`master` |
| `guser-branch` | Prefix branch with `$USER/` (refusing `main`/`master`) |
| `go-testall` | `go test ./...` |
| `go-buildall` | `go build ./...` |
| `go-lint` | `golangci-lint run` |
| `tf` | `terraform` |
| `yaml-lint` | `yamllint -d relaxed` |

---

## Standalone Utilities (`bin/`)

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
# Run full automated test suite (160+ tests across 8 test modules)
make test

# Run syntax & lint validation
make lint
```
