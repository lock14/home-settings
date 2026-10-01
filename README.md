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
│   ├── gnome-terminal-solarized     # GNOME Terminal Solarized Dark profile provisioner
│   ├── ide                          # Tmux + Neovim + AI Agent (agy/claude/codex) IDE workspace launcher
│   ├── macos-terminal-solarized     # macOS Terminal.app Solarized Dark profile provisioner
│   ├── repeat-until-success         # Command retry loop with configurable delay
│   ├── sum                          # High-performance AWK number summation & stats
│   └── update-system                # Cross-platform system package, Snap, Flatpak & toolchain updater
│
├── dotfiles/                        # Declarative mirror of $HOME (auto-discovered and linked)
│   ├── .aliases                     # Full Git suite, CLI & Terraform shortcuts (+ auto-loads ~/.aliases.d/*.sh)
│   ├── .bashrc-addendum             # Bash integration hook & zoxide
│   ├── .environment-variables       # Environment, COLORTERM, PATH (+ auto-loads ~/.environment-variables.d/*.sh)
│   ├── .p10k.zsh                    # Powerlevel10k single-line prompt configuration
│   ├── .tmux.conf                   # Solarized Dark TrueColor Tmux multiplexer & IDE pane bindings
│   ├── .vimrc                       # Fallback Solarized Dark Vim configuration
│   ├── .zsh-completions             # Fpath completion registration
│   ├── .zsh-functions               # Git synchronization (gsync), search (fs), IDE opener/cd (v, icd) (+ auto-loads ~/.zsh-functions.d/*.zsh)
│   ├── .zshrc-addendum              # Zsh integration hook, zoxide, and plugin loader
│   ├── .dir-colors/dircolors        # Solarized Dark dircolors database
│   └── .config/
│       ├── btop/                    # Btop++ system monitor configuration & Solarized Dark theme
│       │   ├── btop.conf
│       │   └── themes/solarized_dark.theme
│       ├── clangd/config.yaml       # Modern C23 / C++20 fallback compiler flags for clangd
│       ├── fontconfig/conf.d/       # Fontconfig alias mapping MesloLGS NF -> MesloLGS Nerd Font Mono
│       ├── ghostty/                 # Ghostty terminal configuration & Solarized Dark theme
│       ├── git/config               # XDG Git configuration with Delta Solarized Dark diff pager
│       ├── nvim/                    # Modern Lua Neovim (Lazy.nvim, Native LSP, Treesitter, Telescope)
│       │   ├── init.lua
│       │   ├── lazy-lock.json
│       │   ├── ftplugin/java.lua
│       │   ├── queries/
│       │   └── after/queries/
│       └── tealdeer/config.toml     # Tealdeer tldr cheatsheet viewer with Solarized Dark styling
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
│   ├── 30-fonts.sh                  # MesloLGS Nerd Font Mono (v3) downloader with disk cache
│   ├── 40-mise.sh                   # Mise runtime manager & polyglot toolchains
│   ├── 60-shell.sh                  # Oh-My-Zsh, plugins, shellrc hooks, completions
│   ├── 70-terminal.sh               # Terminal emulator profile provisioning (GNOME Terminal & macOS)
│   └── 99-uninstall.sh              # Clean uninstallation of managed components
│
├── colors/                          # 24-bit TrueColor themes & terminal profiles
│   ├── Solarized-Dark-TrueColor.tmTheme  # Canonical Solarized Dark theme for bat
│   ├── Solarized-Dark.terminal           # macOS Terminal.app Solarized Dark profile
│   └── gnome-terminal-solarized.dconf    # GNOME Terminal Solarized Dark dconf profile
│
├── syntaxes/                        # Enhanced Sublime syntax packages for bat (18 languages)
│   ├── Bash.sublime-syntax          # Bash / POSIX shell syntax
│   ├── C.sublime-syntax             # Modern C syntax with granular declaration scopes
│   ├── C++.sublime-syntax           # Modern C++ syntax with concept/template support
│   ├── CSS.sublime-syntax           # Modern CSS3 / Container Queries syntax
│   ├── Diff.sublime-syntax          # Standalone Git & Unified Diff syntax for bat
│   ├── Go.sublime-syntax            # Go syntax with calm Base0 qualifiers & struct tags
│   ├── HTML.sublime-syntax          # HTML5 syntax with attribute-guarded script injections
│   ├── JSON.sublime-syntax          # JSON / JSONC declarative hierarchy syntax
│   ├── Java.sublime-syntax          # Modern Java (records, pattern matching, annotations)
│   ├── JavaProperties.sublime-syntax# Java .properties configuration syntax
│   ├── Markdown.sublime-syntax      # Semantic Architecture Markdown syntax
│   ├── Python.sublime-syntax        # Modern Python 3 syntax with type annotations
│   ├── Rust.sublime-syntax          # Rust syntax with unified attributes & lifetimes
│   ├── SQL.sublime-syntax           # ANSI / PostgreSQL / MySQL declarative syntax
│   ├── TOML.sublime-syntax          # TOML syntax with Blue table headers & Green keys
│   ├── Terraform.sublime-syntax     # Terraform / HCL2 infrastructure syntax
│   ├── TypeScript.sublime-syntax    # TypeScript / JavaScript ES2024+ syntax
│   └── XML.sublime-syntax           # XML syntax with namespaces, directives & CDATA
│
└── tests/                           # Automated test suites (350+ tests across 8 modules)
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

## Supported Platforms & Prerequisites

The workstation environment and provisioning pipeline are tested across:
- **Debian-based Linux**: Ubuntu 22.04+ / 24.04+ LTS (Jammy, Noble), Debian 12+, Pop!_OS
- **RHEL-based Linux**: Fedora 38+ / 40+, RHEL 9+, CentOS Stream, Rocky Linux, AlmaLinux
- **macOS**: Modern macOS releases (Sonoma, Sequoia; Apple Silicon & Intel)

Host machines require `bash` (4+), `git`, `curl`, and `sudo` (for system packages). Polyglot toolchains and CLI utilities are managed declaratively in user-space via [**`mise`**](https://mise.jdx.dev/) (`.mise.toml`).

---

## Integrated Development Environment & AI Workspace

The repository provides a unified terminal-based IDE orchestrated across **Tmux** (`dotfiles/.tmux.conf`), **Neovim** (`dotfiles/.config/nvim/init.lua`), and AI CLIs (`agy`, `claude`, `codex`) via `bin/ide`.

- **Spatial Window Architecture (`bin/ide`, `dotfiles/.tmux.conf`)**:
  - **Single-Window Geometry**: Built around an AI-first inverted-T layout in a single Tmux window (`ide`) with zero secondary Neovim servers or hidden `_swap` parking windows.
    - `ide` / `ide3` (`--3pane`, default): Top-Left AI Agent (50%×75%, `agy` / `claude` / `codex`, focused on launch), Top-Right Main Editor (50%×75%, single Neovim server listening on `$NVIM_IDE_SOCKET`), and Bottom Full-Width Interactive Shell (100%×25% for unconstrained Powerlevel10k prompts and wide CLI output).
    - `ide2` (`--2pane`): Side-by-side 50% AI Agent | 50% Full-Height Main Editor.
  - **Interactive Top Status Shelf & Contextual Mode Bar**:
    - **Left Shelf (`status-left`)**: Anchors the session badge (` #S `) at fixed width so mode transitions never shift the center switcher horizontally; clicking `status-left` opens `choose-tree -Zs`.
    - **Center 3-State Role Switcher (`window-status-current-format`)**: Renders `@ide_tab_ai`, `@ide_tab_ed`, and `@ide_tab_term` with distinct visual states: focused (`▸` + semantic accent icon + `Base1` `#93A1A1` label), visible unfocused (`Base0` `#839496` with `(Alt+a/e/t)` focus hint), and parked (`Base01` `#586E75` with `[Alt+E/T]` restore hint), plus an Orange `󰁌 ZOOM (Alt+z)` badge when zoomed. Left-clicking any center badge invokes `ide --status-click` to focus, unpark, or unzoom; right-clicking opens a workspace context menu (`display-menu`).
    - **Mode-Contextual Right Shelf (`status-right`)**: Surfaces inline key hints during `PREFIX` (`Ctrl+b`: `HJKL resize · |/- split · b bar · ? keys`) and `COPY` (`Alt+c copy · Alt+v paste · Esc clear`) modes, and stays minimal in normal mode—showing `󰉋 <subdir>` only when `@ide_workdir` differs from `@ide_initial_root`, followed by `󰋖 Help (Alt+?)`.
  - **Non-Destructive Pane Parking & Swapping**:
    - Park and restore panes dynamically without killing running processes (`Alt+Shift+E` / `ide --toggle-editor`, `Alt+Shift+T` / `ide --toggle-term`, `ide --toggle-ai` via hidden windows `_ide_park_<role>`).
    - Directionally swap active panes on the fly (`Alt+Shift+H/J/K/L` / `ide --swap left|down|up|right`, wrapping horizontally across the top split).
  - **Mouse & Keyboard Resizing**:
    - Drag any split border with the mouse or use `Alt+Left/Down/Up/Right` (`Prefix + H/J/K/L`).
    - Custom pane dimensions persist across focus switches, parking/unparking, and full-screen zoom (`Alt+z`).
  - **Safe Session Isolation & Quitting**:
    - Every IDE command targets its exact session (`=NAME`) to prevent prefix collisions or cascading shutdowns.
    - Standard Neovim `:q`, `:wq`, `:qa`, and `:wqa` work natively on buffers, splits, and the Editor process, while `:Q`, `:Quit`, `Space q`, `Alt+q`, `ide quit`, or `qide` terminate the entire IDE workspace session, prompting if unsaved buffers exist (`:Q!` / `Alt+Shift+Q` / `ide quit --force`).

- **First-Principles 4-Layer Keybinding Architecture**:
  - **Layer 1: App-Local (`Ctrl`)**: Root Tmux `Ctrl+h/j/k/l` bindings are strictly omitted, preserving native `Ctrl+L` (clear), `Ctrl+J` (newline), `Ctrl+K` (kill line), and `Ctrl+H` (backspace) in Zsh, Bash, and AI CLIs (`agy`, `claude`, `codex`). `<C-j>/<C-k>` navigate Telescope pickers, while `<C-h/j/k/l>` navigate internal Neovim Normal-mode splits.
  - **Layer 2: Spatial Navigation, Workspace & Help (`Alt`)**:
    - `Alt+h/j/k/l` move focus seamlessly across Neovim splits and Tmux panes from any mode (`n/i/v/t`).
    - `Alt+a`, `Alt+e`, and `Alt+t` focus or unpark the AI Agent, Editor, or Shell pane, bouncing back to the previous pane on a second press while preserving zoom state.
    - `Alt+Shift+E` and `Alt+Shift+T` toggle Editor and Shell pane visibility from anywhere.
    - `Alt+Shift+H/J/K/L` directionally swap panes; `Alt+z` toggles full-window zoom; `Alt+q` (`Alt+Shift+Q`) quits the workspace.
    - `Alt+?` (`Prefix + ?`, `Space ?`, or `ide --keys`) opens a 2-column Solarized Dark keybinding cheatsheet popup (`tmux display-popup`).
  - **Layer 3: Editor, File Explorer & Live Auto-Reload (`Space` Leader & `mini.files`)**:
    - `Space e` opens the `mini.files` columnar file explorer anchored at the current buffer's directory (`Space E` opens at the current working directory), falling back to `:Lexplore` when offline. Inside `mini.files`, `h`/`l` navigate parent/child directories or open files, `j`/`k` move across entries, `=` synchronizes buffer edits (create, rename, move, delete) to disk, `g?` shows explorer help, and `q`/`<Esc>` closes.
    - `Space gs` opens Telescope `git_status` to review and jump to AI-modified files.
    - `opt.autoread` and `SolarizedAutoRead` (`FocusGained`, `BufEnter`, `CursorHold`, `CursorHoldI` -> `silent! checktime`) automatically reload buffers modified on disk by AI agents.
    - `H`/`L` cycle listed buffers; `<Home>` jumps to the first non-blank character; `:IdeCd` (`Space cd`) synchronizes the workspace directory across Editor and Shell.
  - **Layer 4: Clickable Links & Unified Clipboard**:
    - Native terminal OSC 8 hyperlinks pass through Tmux (`terminal-features '*:hyperlinks'`) for browser links, while `Ctrl+Click` on compiler output (`file:line[:col]`), `file:///` URLs, markdown `[label](file:///...#L10)` links, or custom `~/.config/ide/links.sh` rules opens the target at that line in the Editor.
    - Selecting text with the mouse in Tmux or Neovim copies immediately via `copy-pipe-no-clear` / `"+ygv` while keeping the highlight visible (`Alt+c` copies and clears, `Escape` or single click clears, `Alt+v` pastes from the system/OSC 52 clipboard).
    - SSH sessions strictly avoid probing local `/tmp/.X11-unix/X0` sockets so Neovim's built-in OSC 52 provider and `tmux load-buffer -w` route clipboard yanks back to the remote SSH client.

- **Polyglot LSP, Treesitter & Neovim Toolchains**:
  - **Native LSP (`mason.nvim` + `nvim-lspconfig` / `vim.lsp.config`)**: Polyglot code intelligence auto-managing C/C++ (`clangd`), Rust (`rust_analyzer`), Go (`gopls`), Python (`pyright`), Lua (`lua_ls`), Bash (`bashls`), Terraform (`terraformls`), YAML (`yamlls`), JSON (`jsonls`), and Java via on-demand `nvim-jdtls` (`dotfiles/.config/nvim/ftplugin/java.lua`).
  - **Treesitter**: AST-based syntax highlighting with 1:1 parity matching `bat`.
  - **Telescope**: Fuzzy file finding (`<leader>ff`, `<leader>fg`, `<leader>fb`, `<leader>gs`) with `<C-j>` / `<C-k>` selection movement.
  - **Solarized Dark**: Seamless `#002B36` terminal background matching.
  - **Editor Aliases**: `vi`, `vim`, `v` mapped to `nvim` (with automatic fallback to legacy `vim` and `+line` support over RPC).

### IDE Workspace Keybindings & Navigation

| Keybinding / Action | Context | Description |
| :--- | :--- | :--- |
| `Alt+h` / `j` / `k` / `l` | Universal (`n/i/v/t`) | Navigate focus across Neovim splits and Tmux panes seamlessly |
| `Alt+a` (`Space a`) | Universal | Focus AI Agent pane (or unpark); bounce back to Editor on second press (zoom-preserving) |
| `Alt+e` | Universal | Focus Editor pane (or unpark); bounce back to previous pane on second press |
| `Alt+t` | Universal | Focus Shell pane (or unpark); bounce back to Editor on second press |
| `Alt+Shift+E` | Universal | Toggle Editor pane visibility (park to / restore from `_ide_park_editor`) |
| `Alt+Shift+T` | Universal | Toggle Shell pane visibility (park to / restore from `_ide_park_term`) |
| `Alt+Shift+H` / `J` / `K` / `L` | Tmux | Directionally swap active pane left, down, up, or right (wraps horizontally across top panes) |
| `Alt+z` | Tmux | Toggle full-window pane zoom (preserves zoom state across pane switches) |
| `Alt+Left` / `Down` / `Up` / `Right` | Tmux | Resize active pane by 5 cells in direction (or drag borders with mouse) |
| `Alt+?` / `Space ?` / `Prefix + ?` | Universal | Open interactive 2-column Solarized Dark keybinding cheatsheet popup (`ide --keys`) |
| `Click Status Bar` | Tmux Mouse | Left-click session (`choose-tree`), center role/zoom badges (`ide --status-click`), or `Help` (`ide --keys`); right-click for menu |
| `Alt+c` / `Alt+v` | Universal | Copy active selection to system/OSC 52 clipboard and clear highlight / paste from clipboard |
| `Ctrl+Click` | Shell / AI | Open file path, compiler warning (`file:line:col`), `file:///` link, or `~/.config/ide/links.sh` rule in Editor |
| `Alt+q` (`Alt+Shift+Q`) / `Space q` | Universal | Gracefully quit (`ide quit`) or force-quit (`ide --quit --force`) current IDE workspace |
| `Space e` / `Space E` | Neovim Normal | Toggle `mini.files` explorer at buffer dir (`Space e`) or cwd (`Space E`); `h`/`l` out/in, `=` apply edits, `g?` help, `q` close |
| `Space gs` | Neovim Normal | Open Telescope `git_status` to review AI-modified files |
| `Space cd` (`:IdeCd [dir]`) | Neovim Normal | Synchronize Editor and Tmux workspace directory (`@ide_workdir`) |
| `H` / `L` | Neovim Normal | Cycle previous / next listed buffer |
| `<Home>` | Neovim Normal | Jump to first non-blank character on line |
| `:q` / `:wq` / `:qa` / `:wqa` | Neovim Command | Native Neovim window/buffer/editor close (unmodified) |
| `:Q` / `:Q!` (`:Quit`) | Neovim Command | Quit entire IDE workspace session safely (or force-quit with `!`) |
| `icd [dir|--reset]` | Shell | Synchronize working directory across Editor and Shell without killing AI Agent |
| `v [+line] <file>` | Shell | Open file in the IDE Editor pane (with optional line jump) via RPC |

---

## Interactive Shell & Powerlevel10k Prompt

Interactive shell environments are provisioned with sub-10ms startup times, instant completion, and calibrated Solarized Dark styling:

- **Zsh Engine & Completion**: Instant interactive startup (<10ms), completion system (`fpath`), and drop-in configuration support (`~/.environment-variables.d/`, `~/.aliases.d/`, `~/.zsh-functions.d/`).
- **Powerlevel10k Solarized Dark**: Single-line prompt with zero-fork `.git/config` icon resolution and single-fork porcelain v2 Git status (100% `gitstatusd`-free, supporting SHA-256 and Git `reftable`).
- **Syntax Highlighting**: Authentic 24-bit TrueColor Solarized Dark command highlighting (`zsh-syntax-highlighting`): commands in Green (`#859900`), strings in Cyan (`#2AA198`), numbers in Magenta (`#D33682`), directories/paths in Blue (`#268BD2`), errors in Red (`#DC322F`), with parameters, options, and operators in calm Base0 (`#839496`).
- **Autosuggestions & Search**: Asynchronous history autosuggestions in subtle Base01 (`#586E75`), Base02 selection highlighting (`#073642`), and interactive fuzzy history search via `fzf` (`Ctrl+R`).
- **Frecency Directory Jumping**: Smart directory jumping via `zoxide` (`z <dir>` with destination echoing, `zi` with interactive `eza` previews).

---

## Developer Toolchains & Modern CLI Suite

Developer runtimes are managed declaratively in user-space via [**`mise`**](https://mise.jdx.dev/) (`.mise.toml`), providing LTS Java (17/21/25+), LTS Node.js, and the latest stable Go, Python, Rust, Terraform, and Maven toolchains alongside a curated suite of 24-bit TrueColor CLI utilities:

| Tool | Command / Shortcut | Role & Solarized Dark Integration |
| :--- | :--- | :--- |
| `bat` | `bat <file>`, `b <file>` | TrueColor syntax-highlighting pager with 18 custom syntaxes matching Neovim Treesitter (`cat` remains pure coreutils) |
| `delta` | `git diff`, `git log -p`, `git show` | TrueColor diff pager with word-level diff intra-line highlights, line numbers, and subtle Solarized tints |
| `dust` | `ds` | Graphical proportional disk space visualizer (Rust `du -sh` alternative) |
| `tealdeer` | `tldr <cmd>` | Fast offline cheatsheet viewer with Solarized Dark TrueColor styling |
| `zoxide` | `z <dir>`, `zi` | Frecency directory jumper with destination path echo and interactive `eza` previews |
| `fzf` | `Ctrl+R`, `Ctrl+T` | Fuzzy finder powering command history, file navigation, and Telescope pickers |
| `ripgrep` | `rg <pattern>` | Ultra-fast recursive regex search powering `fzf` file discovery and Neovim Telescope live grep |
| `fd` | `fd <query>`, `fs` | Lightning-fast file and directory tree search |
| `eza` | `e`, `el`, `et`, `elt` | Modern `ls` with Nerd Font icons, Git status, and directory tree views |
| `sd` | `sd 'find' 'replace' <file>` | Modern, intuitive regex find-and-replace CLI (escaping-free `sed` alternative) |
| `jq` | `jq <filter>` | CLI JSON processor with calibrated TrueColor `JQ_COLORS` matching Solarized Dark |
| `yq` | `yq <filter>` | Portable processor for YAML, JSON, XML, CSV, and Java Properties files |
| `btop` | `btop` | System resource monitor with custom TrueColor Solarized Dark gradients and Vim keys (`h/j/k/l`) |
| `gh` | `gh <cmd>` | Official GitHub CLI for pull requests, issues, and workflow inspection |
| `mise` | `mise <cmd>` | Polyglot runtime manager managing LTS Java, LTS Node, latest Go, Python, Rust, Terraform, etc. |
| `shellcheck` | `shellcheck <script>` | Static analysis linter for POSIX and Bash shell scripts |

---

## Terminal Emulators & System Monitoring

- **Ghostty (`dotfiles/.config/ghostty/config`)**:
  - **Theme**: Authentic 24-bit TrueColor Solarized Dark (`theme = "Solarized Dark"`) with 1:1 RGB palette matching Windows Terminal.
  - **Typography**: `MesloLGS Nerd Font Mono` (`font-family = "MesloLGS Nerd Font Mono"`, `font-size = 12`) with native Nerd Fonts v3 icons for `eza`.
  - **Window & Layout**: Flush edges (zero padding, unconstrained grid) and block cursor.
  - **Productivity**: Auto-split panes (`Ctrl+Shift+D`), navigation (`Ctrl+Shift+H/J/K/L`), and zoom toggle (`Ctrl+Shift+Enter`).
  - **Cross-Platform**: Automatically symlinked to `${XDG_CONFIG_HOME:-~/.config}/ghostty/config` and macOS `~/Library/Application Support/com.mitchellh.ghostty/config`.
- **GNOME Terminal (`colors/gnome-terminal-solarized.dconf` & `bin/gnome-terminal-solarized`)**:
  - **Theme**: Authentic 24-bit TrueColor Solarized Dark profile provisioned into dconf as default.
  - **Palette**: Corrects Color 8 to `base01` (`#586E75`), fixing the common invisible dim text / autosuggestions bug.
  - **Typography & UI**: `MesloLGS Nerd Font Mono 12` font, Solarized `base02` (`#073642`) text selection highlight, block cursor, and silent bell.
  - **CLI Management**: Provisioned automatically during setup (`modules/70-terminal.sh`) or manually via `gnome-terminal-solarized`.
- **macOS Terminal.app (`colors/Solarized-Dark.terminal` & `bin/macos-terminal-solarized`)**:
  - **Theme**: Authentic 24-bit TrueColor Solarized Dark profile configured in `com.apple.Terminal.plist` as default.
  - **Palette**: Corrects Color 8 to `base01` (`#586E75`), with `base02` selection highlight and `base03` background.
  - **Typography**: `MesloLGS Nerd Font Mono` 12 font (`MesloLGSNFM-Regular 12pt`), antialiasing enabled.
  - **CLI Management**: Provisioned automatically on macOS during setup (`modules/70-terminal.sh`) or manually via `macos-terminal-solarized`.
- **Btop++ System Monitor (`dotfiles/.config/btop/btop.conf`)**:
  - **Theme**: Authentic 24-bit TrueColor Solarized Dark (`themes/solarized_dark.theme`) with custom gradients for CPU, Memory, Disks, Network, and Processes.
  - **Layout & Typography**: High-resolution Braille glyphs (`graph_symbol = "braille"`), rounded corners (`rounded_corners = true`), and Solarized Base01 (`#586E75`) split frames matching Ghostty, Tmux, and Neovim.
  - **Navigation**: Full Vim navigation keys enabled (`vim_keys = true` for `h, j, k, l, g, G`).
  - **Cross-Platform**: Automatically symlinked into `${XDG_CONFIG_HOME:-~/.config}/btop/`.

---

## Quick Start & Installation

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

# Run complete test suite (350+ tests across 8 modules)
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
| `--uninstall-fonts` | *disabled* | Remove MesloLGS Nerd Font Mono fonts only |
| `--uninstall-bin` | *disabled* | Remove symlinked user utilities from `~/.local/bin` only |
| `--os <distro>` | *auto* | Target OS family override: `ubuntu` (Debian/apt), `fedora` (RHEL/dnf), `macos` (Homebrew) |
| `--db <engine>` | `none` | Database server engine to install: `postgres`, `mariadb`, `all`, `none` |
| `--with-postgres`, `--with-postgresql` | *disabled* | Install PostgreSQL server and client tools |
| `--with-mariadb` | *disabled* | Install MariaDB server and client tools |
| `--skip-db` | *disabled* | Skip all database client and server installations |
| `--with-gui` | *disabled* | Install all GUI desktop applications (Chrome, Ghostty, IDE/VS Code) |
| `--with-ghostty` | *disabled* | Install Ghostty terminal emulator (macOS cask, Snap on Ubuntu, COPR on Fedora) |
| `--skip-ghostty` | *disabled* | Skip Ghostty terminal emulator installation |
| `--with-chrome` | *disabled* | Install Google Chrome |
| `--skip-chrome` | *disabled* | Skip Google Chrome installation |
| `--with-apps` | *disabled* | Install desktop apps (VS Code / IDE) |
| `--skip-apps` | *disabled* | Skip desktop apps installation (VS Code / IDE) |
| `-i, --ide <name>` | `none` | IDE to install: `intellij`, `intellij-ultimate`, `code`, `none` |
| `--skip-system` | *disabled* | Skip OS package updates and system provisioning |
| `--skip-packages` | *disabled* | Skip core system package manager installs |
| `--skip-user` | *disabled* | Skip user dotfiles and environment configuration |
| `--skip-fonts` | *disabled* | Skip MesloLGS Nerd Font Mono installation |
| `--skip-tools` | *disabled* | Skip Mise polyglot toolchain runtime installation |
| `--skip-nvim` | *disabled* | Skip Neovim configuration and plugins |
| `--skip-vim` | *disabled* | Skip Vim configuration and plugins |
| `--skip-zsh` | *disabled* | Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k |
| `--skip-bash` | *disabled* | Skip Bash configuration and environment variables |
| `--skip-bin` | *disabled* | Skip `~/.local/bin` user utilities synchronization |
| `--skip-completions`| *disabled* | Skip CLI tab completions generation |
| `--skip-terminal` | *disabled* | Skip terminal emulator profile configuration (GNOME Terminal & macOS Terminal.app) |

---

## Extensibility & Customization

The redesigned repository is built for frictionless extension:

1. **Add a Dotfile**: Drop any file or directory into `dotfiles/`. It is automatically discovered and mirrored to `$HOME` (e.g. `dotfiles/.gitconfig` -> `~/.gitconfig`). Pre-existing physical directories are backed up safely (`.bak.<timestamp>`) to prevent nested symlinks.
2. **Add a CLI Utility**: Drop any script into `bin/` and make it executable. It is automatically symlinked into `~/.local/bin/`.
3. **Drop-in Shell Extensions (`.d/`)**: Keep machine-specific or sensitive configurations in local drop-in directories without committing them to the repository:
   - `~/.environment-variables.d/*.sh`: Custom exports and paths (sourced by `.environment-variables`).
   - `~/.aliases.d/*.sh`: Custom aliases (sourced by `.aliases`).
   - `~/.zsh-functions.d/*.zsh`: Custom Zsh functions (sourced by `.zsh-functions`).
   - `~/.config/ide/links.sh` (or `$IDE_LINK_RULES`): Private Ctrl+click link rules and workspace session naming for `ide`. Define `ide_resolve_link WORD CWD` to print a URL for a clicked word (e.g. an internal ticket ID or short link) and return 0; return non-zero to fall through to the default file handling. Optionally define `ide_session_name DIR` to print a custom tmux session name for a workspace directory (e.g. extracting a parent workspace identifier when `basename "$DIR"` is shared across multiple checkouts).
   - `~/.config/zsh/p10k.local.zsh`: Machine-local Powerlevel10k overrides (sourced by `.p10k.zsh` before reload), e.g. extra anchors appended to `POWERLEVEL9K_SHORTEN_FOLDER_MARKER`, or `POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN="${POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN}|/slow/network/fs/*"` to skip Git status on slow filesystems.
4. **Add a Provisioning Stage**: Drop a new numbered script into `modules/` (e.g. `modules/70-docker.sh`).


## Git & Shell Shortcuts

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Interactive fuzzy search command history via `fzf` |
| `z <dir>` | Smart jump to directory with destination path echo via `zoxide` |
| `zi` | Interactive fuzzy directory jump with live `eza` preview via `zoxide` + `fzf` |
| `sd <find> <replace> <file>` | Fast, intuitive regex find-and-replace via `sd` |
| `b <file>` / `bat` | Syntax-highlighted file viewing via `bat` with TrueColor Solarized Dark (`cat` remains pure coreutils) |
| `vi` / `vim` / `v` | Modern Lua Neovim (with automatic fallback to `vim`; inside an `ide` session, `v [+line] <file>` opens in the main editor pane) |
| `ide` / `ide3` / `ide2` | Launch or attach to a 3-pane (`ide`, `ide3`) or 2-pane (`ide2`) Tmux + Neovim + AI Agent IDE workspace |
| `qide` / `idek` | Gracefully quit (`ide quit`) or force-kill (`ide --kill`) the current IDE workspace session (only that exact `ide`-managed session: other tmux sessions are never touched) |
| `icd [dir\|--reset]` | Non-destructively synchronize the active directory across IDE `Editor` and `Shell` panes without respawning the AI Agent |
| `ds` | Graphical proportional disk space analysis via `dust` |
| `tldr <cmd>` | Fast, practical syntax-highlighted command cheat sheet via `tealdeer` |
| `update` | Run cross-platform system and toolchain maintenance (`update-system`) |
| `ls` | Standard directory listing with color (`ls --color=auto`) |
| `ll` | Standard long directory listing with hidden files (`ls -alF`) |
| `la` | List almost all files (`ls -A`) |
| `l` | Compact column listing (`ls -CF`) |
| `e` | Modern grid listing with Nerd Font icons (`eza --icons=auto --group-directories-first`) |
| `el` | Detailed eza listing with headers, Git status, group, and ISO timestamps (`eza -la --icons=auto --git --header --group --time-style=long-iso`) |
| `elm` | Detailed eza listing sorted by modification time with newest files at bottom (`eza -la ... --sort=modified`) |
| `et` | Safe 2-level directory tree view with icons (`eza --tree --level=2 --icons=auto`) |
| `elt` | Detailed eza tree view with Git status, group, and ISO timestamps (`eza -la --tree --level=2 ...`) |
| `elx` | Extended forensic listing with hard links, inodes, blocks, and extended attributes (`-H -i -S --extended`) |
| `fs` | Fast recursive directory tree search (`fd` + `tree --fromfile`) |
| `gcommit` | `git add -A && git commit` |
| `gamend` | `git add -A && git commit --amend --no-edit` |
| `gpush` / `gpushf` | `git push origin HEAD` / `--force-with-lease` |
| `gpull` | `git pull --rebase --autostash` |
| `gup` | `git pull --rebase --autostash --prune` |
| `gprune` | Safely delete merged local branches |
| `gpurge` | Nuclear force-delete (`-D`) local branches except `main`/`master` |
| `gsync` | Rebase current branch onto latest `main`/`master` |
| `guser-branch` | Prefix branch with `$USER/` (refusing `main`/`master`) |
| `tf` | `terraform` |

---

## Standalone Utilities (`bin/`)

| Script | Description |
|---|---|
| `gen-passwd` | Generate random passwords with configurable character sets (`-u`, `-l`, `-n`, `-s`) and lengths |
| `gnome-terminal-solarized` | Provision or verify the Solarized Dark TrueColor profile in GNOME Terminal (`dconf`) |
| `ide` | Launch and manage multi-pane Tmux + Neovim + AI Agent (`agy`, `claude`, `codex`) IDE workspaces |
| `macos-terminal-solarized` | Provision or verify the Solarized Dark TrueColor profile in macOS `Terminal.app` |
| `sum` | Sum numbers from stdin/args with CSV parsing, column filtering (`-k`), human byte units (`-H`), averages (`-a`), and stats (`-s`) |
| `repeat-until-success` | Retry a command up to N times with a configurable sleep interval |
| `update-system` | Cross-platform system package & toolchain updater (APT, DNF, Homebrew, Pacman, Snap, Flatpak, Mise) |

---

## Development & Testing

All scripts enforce `set -euo pipefail` for fail-fast safety.

```bash
# Run full automated test suite (350+ tests across 8 test modules)
make test

# Run syntax & lint validation
make lint
```
