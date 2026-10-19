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
├── syntaxes/                        # Enhanced Sublime syntax packages for bat (36 languages)
│   ├── Bash.sublime-syntax          # Bash / POSIX shell syntax
│   ├── C.sublime-syntax             # Modern C23 syntax with granular declaration scopes
│   ├── C++.sublime-syntax           # Modern C++20/23 syntax with concept/template support
│   ├── CSharp.sublime-syntax        # Modern C# 12/13 syntax (records, primary constructors, LINQ)
│   ├── CSS.sublime-syntax           # Modern CSS3 / Container Queries syntax
│   ├── Clojure.sublime-syntax       # Clojure syntax (namespaces, macros, protocols, keywords)
│   ├── Diff.sublime-syntax          # Standalone Git & Unified Diff syntax for bat
│   ├── Dockerfile.sublime-syntax    # Multi-stage Dockerfile / Containerfile syntax
│   ├── Elixir.sublime-syntax        # Elixir syntax (GenServer, @spec/@doc, pipe operators, atoms)
│   ├── Go.sublime-syntax            # Go syntax with calm Base0 qualifiers & struct tags
│   ├── GraphQL.sublime-syntax       # Declarative GraphQL schema & query syntax
│   ├── HTML.sublime-syntax          # HTML5 syntax with attribute-guarded script injections
│   ├── Haskell.sublime-syntax       # GHC2021 Haskell syntax (pragmas, typeclasses, GADTs, do)
│   ├── JSON.sublime-syntax          # JSON / JSONC declarative hierarchy syntax
│   ├── Java.sublime-syntax          # Modern Java 25 LTS (records, pattern matching, annotations)
│   ├── JavaProperties.sublime-syntax# Java .properties configuration syntax
│   ├── Kotlin.sublime-syntax        # Modern Kotlin 2.x (value classes, coroutines, annotations)
│   ├── Lua.sublime-syntax           # Modern Lua 5.4 / LuaJIT syntax (<const>, metamethods)
│   ├── Makefile.sublime-syntax      # GNU Make syntax (directives, targets, automatic variables)
│   ├── Markdown.sublime-syntax      # Semantic Architecture Markdown syntax
│   ├── OCaml.sublime-syntax         # OCaml 5 syntax (modules, functors, polymorphic variants)
│   ├── Protobuf.sublime-syntax      # Protocol Buffers (.proto) schema syntax
│   ├── ProtobufText.sublime-syntax  # Protocol Buffers Text Format (.textproto / .pbtxt) syntax
│   ├── Python.sublime-syntax        # Modern Python 3.12+ syntax (type statements, match/case)
│   ├── Rego.sublime-syntax          # Open Policy Agent (OPA Rego v1) policy syntax
│   ├── Ruby.sublime-syntax          # Modern Ruby 3.3+ syntax (Data.define, pattern matching)
│   ├── Rust.sublime-syntax          # Rust syntax with unified attributes & lifetimes
│   ├── SQL.sublime-syntax           # ANSI / PostgreSQL / MySQL declarative syntax
│   ├── Scala.sublime-syntax         # Scala 3 LTS syntax (enums, given/using, extensions)
│   ├── Starlark.sublime-syntax      # Open-source Bazel / Starlark (.bzl, BUILD.bazel) syntax
│   ├── Swift.sublime-syntax         # Modern Swift 6 (actors, structured concurrency, directives)
│   ├── TOML.sublime-syntax          # TOML syntax with Blue table headers & Green keys
│   ├── Terraform.sublime-syntax     # Terraform / HCL2 infrastructure syntax
│   ├── TypeScript.sublime-syntax    # TypeScript / JavaScript ES2024+ syntax
│   ├── XML.sublime-syntax           # XML syntax with namespaces, directives & CDATA
│   └── Zig.sublime-syntax           # Modern Zig syntax (comptime, error sets, @builtins)
│
└── tests/                           # Automated test suites (500+ tests across 8 modules)
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

Host machines require `bash` (4+), `git`, `curl`, and `sudo` (for system packages). Polyglot toolchains and CLI utilities are managed declaratively in user-space via [mise](https://mise.jdx.dev/) (`.mise.toml`).

---

## Integrated Development Environment & AI Workspace

The repository provides a terminal-based IDE (`bin/ide`) combining **Tmux**, **Neovim**, and AI CLIs (`agy`, `claude`, `codex`).

- **Spatial Window Architecture (`bin/ide`, `dotfiles/.tmux.conf`)**:
  - **Single-Window Geometry**: Runs inside a single Tmux window (`ide`) using an AI-first inverted-T layout:
    - **3-Pane Layout (`ide` or `ide3`, default)**: Top-left AI Agent (50%×75%, focused on launch), top-right Main Editor (50%×75%, single Neovim server), and a full-width bottom Interactive Shell (100%×25%). Also selectable via `ide --3pane`.
    - **2-Pane Layout (`ide2`)**: Side-by-side 50% AI Agent and 50% full-height Main Editor (`ide --2pane`).
  - **Interactive Top Status Bar**:
    - **Left (Session Badge)**: Displays the session name at a fixed width; click to switch sessions.
    - **Center (Role Switcher)**: Shows the **AI**, **Editor**, and **Shell** panes with visual states for focused, unfocused, parked, and zoomed (`Alt+z`). Left-click any badge to focus, restore, or unzoom; right-click for the workspace menu.
    - **Right (Contextual Hints & Status)**: Shows inline key hints during Tmux prefix (`Ctrl+b`) and copy modes. In normal mode, it displays conditional indicators for synchronized panes (`SYNC`), remote SSH hosts, active subdirectories, and the `Help` cheatsheet button (`Alt+?`).
  - **Pane Parking, Swapping & Resizing**:
    - Hide and restore the Editor (`Alt+Shift+E`) or Shell (`Alt+Shift+T`) without stopping running processes.
    - Swap panes directionally with `Alt+Shift+H/J/K/L`, and resize by dragging borders with the mouse or pressing `Alt+Left/Down/Up/Right`. Custom pane sizes persist across focus changes, parking, and zoom (`Alt+z`).
  - **Session Isolation & Quitting**:
    - IDE commands target only the active workspace session so other Tmux sessions are unaffected.
    - Standard Neovim quit commands (`:q`, `:wq`, `:qa`, `:wqa`) close only editor buffers and splits.
    - Workspace quit commands (`:Q`, `:Quit`, `Space q`, `Alt+q`, or `qide`) close the entire IDE session after checking for unsaved changes, while `:Q!`, `Alt+Shift+Q`, and `idek` force-quit immediately.

- **4-Layer Keybinding Architecture**:
  - **Layer 1 — App-Local (`Ctrl`)**: Tmux never binds root `Ctrl+h/j/k/l`, keeping standard terminal shortcuts (clear screen, newline, kill line, backspace) intact in shells and AI CLIs. Inside Neovim, `Ctrl+h/j/k/l` navigate editor splits and `Ctrl+j/k` move through Telescope results.
  - **Layer 2 — Workspace Navigation (`Alt`)**:
    - `Alt+h/j/k/l` move focus across Neovim splits and Tmux panes from any mode.
    - `Alt+a` (or `Space a`), `Alt+e`, and `Alt+t` jump directly to the AI Agent, Editor, or Shell pane; pressing the same key again bounces back to the previous pane.
    - `Alt+?`, `Space ?`, or `Prefix + ?` opens the interactive keybinding cheatsheet popup (`ide --keys`).
  - **Layer 3 — Editor, File Explorer & Live Reload (`Space` Leader)**:
    - `Space e` opens the left-anchored `mini.files` column explorer at the current buffer's directory (`Space E` opens at the working directory) with a full-width preview pane on the right. Inside the explorer, navigate with `h/j/k/l` or arrow keys, press `=` to apply file changes to disk, `g?` for help, and `q` to close.
    - `Space m` toggles in-buffer Markdown rendering (`render-markdown.nvim`) with word-boundary soft wrapping.
    - `Space gs` opens Telescope `git_status` to review modified files, while `autoread` automatically reloads buffers edited on disk by AI agents.
    - `H` and `L` cycle open buffers, `Home` jumps to the first non-blank character on the line, and `Space cd` (`:IdeCd` in Neovim, or `icd` in the shell) synchronizes the working directory across panes.
  - **Layer 4 — Clickable Links, Jumplist & Clipboard**:
    - **Terminal Links (`Ctrl+Click` / `Alt+Click`)**: Clicking URLs or prompt PR/MR badges in the Shell or AI panes opens them in the browser. Clicking file paths, compiler errors (`file:line:col`), Markdown file links, or custom `~/.config/ide/links.sh` matches opens the target file and line in the Editor.
    - **In-Buffer Navigation**: Inside Neovim, `Ctrl+Click`, `Alt+Click`, and `gx` follow concealed Markdown links, table-of-contents `#heading` anchors, relative file paths, and web URLs, falling back to LSP go-to-definition on code symbols. In Markdown buffers, `gd` and `Enter` also follow links under the cursor.
    - **Single-Step Jump Back**: Link jumps record a single context mark before switching files or lines, so mouse back and forward buttons (`Mouse4` and `Mouse5`) or `Ctrl+O` and `Ctrl+I` step cleanly backward and forward in the jumplist.
    - **Unified Clipboard**: Mouse selection copies immediately in both local and remote SSH sessions (via OSC 52) while keeping the selection highlighted. Press `Alt+c` to copy and clear, `Escape` to clear, or `Alt+v` to paste.

- **LSP, Treesitter & Neovim Toolchains**:
  - **Native LSP**: Automatic language server provisioning (`mason.nvim` and `nvim-lspconfig`) for C/C++, Rust, Go, Python, Java (`nvim-jdtls`), Lua, Bash, Terraform, YAML, and JSON.
  - **Treesitter & Markdown Rendering**: Solarized Dark syntax highlighting aligned with `bat`, plus live in-buffer Markdown formatting (`Space m`) for headings, tables, callouts, checkboxes, and code blocks.
  - **Telescope**: Fuzzy finders for files (`Space ff`), live grep (`Space fg`), open buffers (`Space fb`), and Git status (`Space gs`).
  - **Editor Aliases**: `vi`, `vim`, and `v` launch `nvim` (with fallback to `vim`); inside an IDE session, `v [+line] <file>` opens the file directly in the main Editor pane.

### IDE Workspace Keybindings & Navigation

| Keybinding / Action | Context | Description |
| :--- | :--- | :--- |
| `Alt+h/j/k/l` | Universal | Move focus across Neovim splits and Tmux panes |
| `Ctrl+h/j/k/l` | Neovim Normal | Move focus across internal Neovim splits (`Ctrl+j/k` move through Telescope results) |
| `Alt+a` / `Space a` | Universal | Focus or unpark AI Agent pane; press again to bounce back |
| `Alt+e` | Universal | Focus or unpark Editor pane; press again to bounce back |
| `Alt+t` | Universal | Focus or unpark Shell pane; press again to bounce back |
| `Alt+Shift+E` | Universal | Hide or restore the Editor pane |
| `Alt+Shift+T` | Universal | Hide or restore the Shell pane |
| `Alt+Shift+H/J/K/L` | Tmux | Swap active pane left, down, up, or right |
| `Alt+z` | Tmux | Toggle full-window pane zoom |
| `Alt+Left/Down/Up/Right` | Tmux | Resize active pane by 5 cells (or drag borders with the mouse) |
| `Alt+?` / `Space ?` / `Prefix + ?` | Universal | Open interactive keybinding cheatsheet popup (`ide --keys`) |
| `Click Status Bar` | Tmux Mouse | Left-click session badge, pane badges, or `Help`; right-click for workspace menu |
| `Alt+c` / `Alt+v` | Universal | Copy selection to clipboard and clear highlight (`Escape` clears) / paste from clipboard |
| `Ctrl+Click` / `Alt+Click` | Shell / AI / Editor | Open terminal paths, compiler locations, or URLs; follow Markdown links, `#anchors`, or LSP definitions in Neovim |
| `gx` | Neovim Normal | Open link under cursor (`#anchor`, file path, or URL), falling back to LSP definition |
| `gd` / `Enter` | Neovim Markdown | Follow Markdown link under cursor, falling back to LSP definition (`gd`) or newline (`Enter`) |
| `Mouse4` / `Mouse5` | Universal / Editor | Jump backward (`Ctrl+O`) or forward (`Ctrl+I`) in the Editor jumplist |
| `Alt+q` / `Space q` | Universal | Quit the IDE workspace after checking for unsaved changes (`Alt+Shift+Q` forces quit) |
| `Space e` / `Space E` | Neovim Normal | Open `mini.files` explorer at buffer directory or working directory (`h/j/k/l` navigate, `=` apply edits, `g?` help, `q` close) |
| `Space ff` / `Space fg` / `Space fb` | Neovim Normal | Find files (`Space ff`), live grep (`Space fg`), or switch buffers (`Space fb`) via Telescope |
| `Space gs` | Neovim Normal | Open Telescope `git_status` picker to review modified files |
| `Space m` | Neovim Normal | Toggle in-buffer Markdown rendering (`:RenderMarkdown toggle`) |
| `Space cd` / `:IdeCd [dir]` | Neovim Normal | Synchronize Editor and Shell working directory |
| `H` / `L` | Neovim Normal | Cycle previous / next buffer |
| `Home` | Neovim Normal | Jump to first non-blank character on the line |
| `:q` / `:wq` / `:qa` / `:wqa` | Neovim Command | Close Neovim window, buffer, or editor normally |
| `:Q` / `:Q!` | Neovim Command | Quit entire IDE workspace session (`:Quit`; `!` forces quit) |
| `icd [dir\|--reset]` | Shell | Synchronize working directory across Editor and Shell panes |
| `v [+line] <file>` | Shell | Open file in the IDE Editor pane at optional line number |

---

## Interactive Shell & Powerlevel10k Prompt

Interactive shells are configured for sub-10ms startup times, fast tab completion, and Solarized Dark styling:

- **Zsh Engine & Completion**: Fast interactive startup with `fpath` tab completions and support for untracked local `*.d/` drop-in directories.
- **Powerlevel10k & Bash Git Prompts (`.p10k.zsh`, `.bashrc-addendum`)**:
  - **Single-Line Shelf Prompt**: Solarized Dark Base02 shelf displaying the OS icon, working directory, Git host icon, branch status, and execution telemetry in both Zsh and Bash.
  - **Daemon-Free Git Status**: Queries `git status --porcelain=v2` directly without `gitstatusd`, supporting standard, SHA-256, and `reftable` repositories.
  - **Clickable PR/MR Badges**: Renders `<branch>@<N>` as a clickable link to the active pull or merge request on **GitHub**, **GitLab**, **Bitbucket**, and **Gitea / Forgejo / Codeberg**. PR numbers are resolved and cached in the background via forge CLIs or `git ls-remote` so the prompt never blocks.
- **Syntax Highlighting**: 24-bit Solarized Dark command highlighting (`zsh-syntax-highlighting`) that colors valid commands in Green, strings in Cyan, numbers in Magenta, paths in Blue, and errors in Red while keeping flags and operators in neutral Base0 grey.
- **Autosuggestions & History Search**: Asynchronous inline history suggestions (`zsh-autosuggestions`) paired with interactive `Ctrl+R` fuzzy history search via `fzf`.
- **Smart Directory Jumping**: Frecency-based directory jumping via `zoxide` (`z <dir>`) with interactive tree previews (`zi`).

---

## Developer Toolchains & Modern CLI Suite

Developer runtimes are managed declaratively in user-space via [mise](https://mise.jdx.dev/) (`.mise.toml`), providing LTS Java (17/21/25+), LTS Node.js, and the latest stable Go, Python, Rust, Terraform, and Maven toolchains alongside a curated suite of 24-bit TrueColor CLI utilities:

| Tool | Command / Shortcut | Role & Solarized Dark Integration |
| :--- | :--- | :--- |
| `bat` | `bat <file>`, `b <file>` | TrueColor syntax-highlighting pager with 36 custom syntaxes matching Neovim Treesitter (`cat` remains pure coreutils) |
| `delta` | `git diff`, `git show` | TrueColor diff pager with word-level intra-line highlights, line numbers, and subtle Solarized tints |
| `dust` | `ds` | Graphical proportional disk space visualizer (Rust `du -sh` alternative) |
| `tealdeer` | `tldr <cmd>` | Fast offline cheatsheet viewer with Solarized Dark TrueColor styling |
| `zoxide` | `z <dir>`, `zi` | Frecency directory jumper with destination path echo and interactive `eza` previews |
| `fzf` | `Ctrl+R`, `Ctrl+T` | Fuzzy finder powering command history, file navigation, and Telescope pickers |
| `ripgrep` | `rg <pattern>` | Recursive regex search powering `fzf` file discovery and Neovim Telescope live grep |
| `fd` | `fd <query>`, `fs` | Fast file and directory tree search |
| `eza` | `e`, `el`, `et` | Modern `ls` replacement with Nerd Font icons, Git status, and directory tree views |
| `sd` | `sd 'find' 'replace' <file>` | Intuitive regex find-and-replace CLI (escaping-free `sed` alternative) |
| `jq` | `jq <filter>` | CLI JSON processor with calibrated Solarized Dark syntax colors |
| `yq` | `yq <filter>` | Portable processor for YAML, JSON, XML, CSV, and Java Properties files |
| `btop` | `btop` | System resource monitor with custom TrueColor Solarized Dark gradients and Vim keys |
| `gh` | `gh <cmd>` | Official GitHub CLI for pull requests, issues, and workflow inspection |
| `mise` | `mise <cmd>` | Polyglot runtime manager for LTS Java, LTS Node, Go, Python, Rust, and Terraform |
| `shellcheck` | `shellcheck <script>` | Static analysis linter for POSIX and Bash shell scripts |

---

## Terminal Emulators & System Monitoring

- **Ghostty (`dotfiles/.config/ghostty/config`)**:
  - 24-bit Solarized Dark theme with `MesloLGS Nerd Font Mono` (12pt), block cursor, and flush window edges.
  - Built-in split management (`Ctrl+Shift+D`), pane navigation (`Ctrl+Shift+H/J/K/L`), and zoom toggle (`Ctrl+Shift+Enter`).
  - Automatically linked to `~/.config/ghostty/config` and macOS `Application Support`.
- **GNOME Terminal (`bin/gnome-terminal-solarized`)**:
  - Provisions the Solarized Dark TrueColor profile into `dconf` with `MesloLGS Nerd Font Mono 12`, block cursor, and silent bell.
  - Calibrates ANSI Color 8 to Solarized Base01 (`#586E75`) so dim text and shell autosuggestions remain clearly visible.
- **macOS Terminal.app (`bin/macos-terminal-solarized`)**:
  - Provisions `colors/Solarized-Dark.terminal` as the default profile with `MesloLGS Nerd Font Mono` (12pt) and calibrated dim-text and selection contrast.
- **Btop++ System Monitor (`dotfiles/.config/btop/btop.conf`)**:
  - Custom Solarized Dark theme (`themes/solarized_dark.theme`) with Braille graphs, rounded borders, and Vim navigation keys (`h/j/k/l` and `g/G`).

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

# Run complete test suite (500+ tests across 8 modules)
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

The repository is structured for local customization without modifying tracked files:

1. **Add a Dotfile**: Drop any file or directory into `dotfiles/`. It is automatically discovered and symlinked into `$HOME` (backing up any existing physical directory to `.bak.<timestamp>`).
2. **Add a CLI Utility**: Drop any executable script into `bin/` to symlink it automatically into `~/.local/bin/`.
3. **Local Drop-in Extensions**: Keep machine-specific or private settings in untracked local hooks:
   - `~/.environment-variables.d/*.sh`: Custom exports and `PATH` entries.
   - `~/.aliases.d/*.sh`: Custom shell aliases.
   - `~/.zsh-functions.d/*.zsh`: Custom Zsh functions.
   - `~/.config/ide/links.sh` (overridable via `$IDE_LINK_RULES`): Custom workspace hooks for `ide`:
     - Define `ide_resolve_link WORD CWD` to print a target URL for a clicked token and return `0`.
     - Define `ide_session_name DIR` to print a custom Tmux session name for a workspace directory.
   - `~/.config/zsh/p10k.local.zsh`: Local Powerlevel10k overrides sourced before prompt reload (such as custom folder markers or `POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN` for slow network mounts).
4. **Add a Provisioning Stage**: Drop a numbered script into `modules/` (e.g., `modules/80-custom.sh`).

---

## Git & Shell Shortcuts

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Fuzzy search command history via `fzf` |
| `z <dir>` | Jump to frecency-ranked directory via `zoxide` |
| `zi` | Interactive directory jump with live `eza` preview |
| `sd <find> <replace> <file>` | Regex find-and-replace via `sd` |
| `b <file>` / `bat` | Syntax-highlighted file viewer (`cat` remains standard coreutils) |
| `vi` / `vim` / `v` | Launch Neovim (inside `ide`, `v [+line] <file>` opens in the main Editor pane) |
| `ide` / `ide3` | Launch or attach to a 3-pane IDE workspace (`ide --3pane`) |
| `ide2` | Launch or attach to a 2-pane IDE workspace (`ide --2pane`) |
| `qide` | Gracefully quit the active IDE workspace session (`ide --quit`) |
| `idek` | Force-kill the active IDE workspace session (`ide --kill`) |
| `icd [dir\|--reset]` | Synchronize the working directory across IDE Editor and Shell panes |
| `ds` | Graphical disk space analyzer via `dust` |
| `tldr <cmd>` | Practical command cheatsheet viewer via `tealdeer` |
| `update` | Update system packages, Flatpaks, Snaps, and Mise toolchains (`update-system`) |
| `ls` | Standard directory listing with Solarized color (`ls --color=auto`) |
| `ll` | Long directory listing including hidden files (`ls -alF`) |
| `la` | Directory listing including hidden files except `.` and `..` (`ls -A`) |
| `l` | Compact column directory listing (`ls -CF`) |
| `e` | Grid directory listing with Nerd Font icons (`eza`) |
| `el` | Detailed `eza` listing with Git status, headers, and ISO timestamps |
| `elm` | Detailed `eza` listing sorted by modification time (newest last) |
| `et` | 2-level directory tree view with icons (`eza --tree`) |
| `elt` | Detailed 2-level directory tree view with Git status and timestamps |
| `elx` | Extended forensic listing with inodes, hard links, blocks, and extended attributes |
| `fs` | Recursive directory tree search (`fd` + `tree --fromfile`) |
| `gcommit` | Stage all changes and commit (`git add -A && git commit`) |
| `gamend` | Stage all changes and amend the previous commit without editing the message |
| `gpush` | Push current branch to `origin` (`git push origin HEAD`) |
| `gpushf` | Force-push current branch safely (`git push --force-with-lease origin HEAD`) |
| `gpull` | Pull with rebase and autostash (`git pull --rebase --autostash`) |
| `gup` | Pull with rebase, autostash, and remote branch pruning (`--prune`) |
| `gprune` | Delete local branches already merged into the default branch |
| `gpurge` | Force-delete (`-D`) all local branches except `main` or `master` |
| `gsync` | Fetch and rebase current branch onto latest `main` or `master` |
| `guser-branch` | Rename current branch with `$USER/` prefix (refuses `main` or `master`) |
| `tf` | Shorthand alias for `terraform` |

---

## Standalone Utilities (`bin/`)

| Script | Description |
| :--- | :--- |
| `gen-passwd` | Generate random passwords with configurable length and character sets (uppercase, lowercase, digits, symbols) |
| `gnome-terminal-solarized` | Provision or verify the Solarized Dark TrueColor profile in GNOME Terminal (`dconf`) |
| `ide` | Launch and manage multi-pane Tmux + Neovim + AI Agent (`agy`, `claude`, `codex`) IDE workspaces |
| `macos-terminal-solarized` | Provision or verify the Solarized Dark TrueColor profile in macOS `Terminal.app` |
| `sum` | Sum numbers from stdin or arguments with support for CSV columns, human byte units, averages, and min/max stats |
| `repeat-until-success` | Retry a command up to N times with a configurable sleep interval |
| `update-system` | Cross-platform system package and toolchain updater (APT, DNF, Homebrew, Pacman, Snap, Flatpak, Mise) |

---

## Development & Testing

All scripts enforce `set -euo pipefail` for fail-fast safety.

```bash
# Run full automated test suite (500+ tests across 8 test modules)
make test

# Run syntax & lint validation
make lint
```
