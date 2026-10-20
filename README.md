# home-settings

Workstation setup automation, prompt themes, developer toolchains, and dotfiles for modern Unix environments:
- **Debian-based Linux**: Ubuntu 22.04+ and 24.04+ LTS (Jammy, Noble), Debian 12+, Pop!_OS, and Linux Mint
- **RHEL-based Linux**: Fedora 38+ and 40+, RHEL 9+, CentOS Stream, Rocky Linux, and AlmaLinux
- **macOS**: Sonoma and Sequoia on Apple Silicon and Intel

Host machines require `bash` (4+), `git`, `curl`, and `sudo` (for system packages). Polyglot toolchains and CLI utilities are managed declaratively in user-space via [mise](https://mise.jdx.dev/) (`.mise.toml`).

## Table of contents

- [Quick start and installation](#quick-start-and-installation)
  - [Turnkey bootstrap (new machines)](#turnkey-bootstrap-new-machines)
  - [Standard workflows (Makefile)](#standard-workflows-makefile)
  - [CLI orchestrator (`./setup.sh`)](#cli-orchestrator-setupsh)
- [Command-line options (`./setup.sh`)](#command-line-options-setupsh)
- [Architecture overview](#architecture-overview)
- [Integrated development environment and AI workspace](#integrated-development-environment-and-ai-workspace)
  - [IDE workspace keybindings and navigation](#ide-workspace-keybindings-and-navigation)
- [Interactive shell and Powerlevel10k prompt](#interactive-shell-and-powerlevel10k-prompt)
- [Developer toolchains and modern CLI suite](#developer-toolchains-and-modern-cli-suite)
- [Terminal emulators and system monitoring](#terminal-emulators-and-system-monitoring)
- [Extensibility and customization](#extensibility-and-customization)
- [Git and shell shortcuts](#git-and-shell-shortcuts)
- [Standalone utilities (`bin/`)](#standalone-utilities-bin)
- [Development and testing](#development-and-testing)

## Quick start and installation

Provision a new machine via the single-command remote bootstrapper, run lifecycle targets through `make`, or invoke `./setup.sh` directly with custom component flags.

### Turnkey bootstrap (new machines)

Stream and run directly in Bash without pre-cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/lock14/home-settings/main/setup.sh | bash
```

### Standard workflows (Makefile)

After cloning the repository, use the `Makefile` targets to install user-space configurations, provision system packages, or run verification suites:

```bash
git clone https://github.com/lock14/home-settings.git
cd home-settings

# User-space installation (dotfiles, bin, fonts, tools, shell) without sudo (default: make or make all)
make install

# Full machine provisioning with native OS packages (requires sudo; alias: make setup)
make system

# Full turnkey bootstrap for a brand-new machine
make bootstrap

# Clean uninstallation of managed dotfiles, binaries, and fonts
make uninstall

# Run complete test suite (500+ tests across 8 modules)
make test

# Run ShellCheck, shell syntax, and documentation checks
make lint

# Run both lint and test suites
make check

# Display available Makefile targets
make help
```

### CLI orchestrator (`./setup.sh`)

Run `./setup.sh` directly to pass granular component flags or preview changes in dry-run mode:

```bash
# Full machine provisioning
./setup.sh --system

# User-space only (equivalent to make install)
./setup.sh --dotfiles-only

# Preview changes without modifying the system
./setup.sh --dry-run
```

## Command-line options (`./setup.sh`)

`./setup.sh` accepts modular flags to select operating system targets, opt into database daemons or desktop GUI applications, skip individual provisioning stages, or uninstall managed artifacts:

| Option | Default | Description |
| :--- | :--- | :--- |
| `(default)` | enabled | Full machine setup: native OS packages via `apt`, `dnf`, or `brew` plus user environment (requires `sudo`) |
| `--dotfiles-only` | disabled | Configure user dotfiles, fonts, and tools only (no `sudo` required) |
| `--system` | disabled | Full turnkey setup with native packages (alias for default) |
| `--bootstrap` | disabled | Full new machine bootstrap (base packages, shell, tools, and dotfiles) |
| `--system-only` | disabled | Provision OS packages and CLI runtimes only |
| `--dry-run` | disabled | Preview actions without modifying the system |
| `--uninstall` | disabled | Uninstall all managed dotfiles, fonts, and user binaries |
| `--uninstall-dotfiles` | disabled | Remove managed dotfile symlinks only |
| `--uninstall-fonts` | disabled | Remove MesloLGS Nerd Font Mono fonts only |
| `--uninstall-bin` | disabled | Remove symlinked user utilities from `~/.local/bin` only |
| `--os <distro>` | auto | Target OS family override: `ubuntu` (Debian and `apt`), `fedora` (RHEL and `dnf`), or `macos` (Homebrew) |
| `--db <engine>` | `none` | Database server engine to install: `postgres`, `mariadb`, `all`, or `none` |
| `--with-postgres`, `--with-postgresql` | disabled | Install PostgreSQL server and client tools |
| `--with-mariadb` | disabled | Install MariaDB server and client tools |
| `--skip-db` | disabled | Skip all database client and server installations |
| `--with-gui` | disabled | Install all GUI desktop applications (Chrome, Ghostty, and VS Code or IDE) |
| `--with-ghostty` | disabled | Install Ghostty terminal emulator (macOS cask, Snap on Ubuntu, COPR on Fedora) |
| `--skip-ghostty` | disabled | Skip Ghostty terminal emulator installation |
| `--with-chrome` | disabled | Install Google Chrome |
| `--skip-chrome` | disabled | Skip Google Chrome installation |
| `--with-apps` | disabled | Install desktop applications (VS Code or IDE) |
| `--skip-apps` | disabled | Skip desktop application installation |
| `-i, --ide <name>` | `none` | IDE to install: `intellij`, `intellij-ultimate`, `code`, or `none` |
| `--skip-system` | disabled | Skip OS package updates and system provisioning |
| `--skip-packages` | disabled | Skip core system package manager installs |
| `--skip-user` | disabled | Skip user dotfiles and environment configuration |
| `--skip-fonts` | disabled | Skip MesloLGS Nerd Font Mono installation |
| `--skip-tools` | disabled | Skip Mise polyglot toolchain runtime installation |
| `--skip-nvim` | disabled | Skip Neovim configuration and plugins |
| `--skip-vim` | disabled | Skip Vim configuration and plugins |
| `--skip-zsh` | disabled | Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k |
| `--skip-bash` | disabled | Skip Bash configuration and environment variables |
| `--skip-bin` | disabled | Skip `~/.local/bin` user utilities synchronization |
| `--skip-completions` | disabled | Skip CLI tab completions generation |
| `--skip-terminal` | disabled | Skip terminal emulator profile configuration (GNOME Terminal and macOS `Terminal.app`) |
| `-h, --help` | disabled | Display CLI help and usage information |

## Architecture overview

The repository is organized into a thin CLI orchestrator (`setup.sh`), stage-based provisioning modules (`modules/`), declaratively mirrored user configurations (`dotfiles/` and `bin/`), standalone syntax and color definitions (`syntaxes/` and `colors/`), and an automated verification suite (`tests/`):

```text
home-settings/
├── setup.sh                         # Modular orchestrator CLI
├── Makefile                         # Lifecycle targets (install, system, uninstall, test, lint)
├── .mise.toml                       # Mise polyglot toolchains (Java LTS, Node LTS, latest Go, Python, Rust, and Terraform)
├── AGENTS.md                        # Architecture principles and agent directives
│
├── bin/                             # Standalone Unix utilities (symlinked to ~/.local/bin/)
│   ├── gen-passwd                   # Password generator with custom character sets
│   ├── gnome-terminal-solarized     # GNOME Terminal Solarized Dark profile provisioner
│   ├── ide                          # Tmux, Neovim, and AI Agent (agy, claude, codex) IDE workspace launcher
│   ├── macos-terminal-solarized     # macOS Terminal.app Solarized Dark profile provisioner
│   ├── repeat-until-success         # Command retry loop with configurable delay
│   ├── sum                          # High-performance AWK number summation and stats
│   └── update-system                # Cross-platform system package, Snap, Flatpak, and toolchain updater
│
├── dotfiles/                        # Declarative mirror of $HOME (auto-discovered and linked)
│   ├── .aliases                     # Full Git suite, CLI, and Terraform shortcuts (also auto-loads ~/.aliases.d/*.sh)
│   ├── .bashrc-addendum             # Bash integration hook and zoxide
│   ├── .environment-variables       # Environment, COLORTERM, and PATH (also auto-loads ~/.environment-variables.d/*.sh)
│   ├── .p10k.zsh                    # Powerlevel10k single-line prompt configuration
│   ├── .tmux.conf                   # Solarized Dark TrueColor Tmux multiplexer and IDE pane bindings
│   ├── .vimrc                       # Fallback Solarized Dark Vim configuration
│   ├── .zsh-completions             # Fpath completion registration
│   ├── .zsh-functions               # Git synchronization (gsync), search (fs), and IDE opener (v, icd) (also auto-loads ~/.zsh-functions.d/*.zsh)
│   ├── .zshrc-addendum              # Zsh integration hook, zoxide, and plugin loader
│   ├── .dir-colors/dircolors        # Solarized Dark dircolors database
│   └── .config/
│       ├── btop/                    # Btop++ system monitor configuration and Solarized Dark theme
│       │   ├── btop.conf
│       │   └── themes/solarized_dark.theme
│       ├── clangd/config.yaml       # Modern C23 and C++20 fallback compiler flags for clangd
│       ├── fontconfig/conf.d/       # Fontconfig alias mapping MesloLGS NF to MesloLGS Nerd Font Mono
│       ├── ghostty/                 # Ghostty terminal configuration and Solarized Dark theme
│       ├── git/config               # XDG Git configuration with Delta Solarized Dark diff pager
│       ├── nvim/                    # Modern Lua Neovim (Lazy.nvim, Native LSP, Tree-sitter, Telescope)
│       │   ├── init.lua
│       │   ├── lazy-lock.json
│       │   ├── ftplugin/java.lua
│       │   ├── queries/
│       │   └── after/queries/
│       └── tealdeer/config.toml     # Tealdeer tldr cheatsheet viewer with Solarized Dark styling
│
├── lib/                             # Shared helper libraries
│   ├── log.sh                       # Terminal logging and dry-run runner
│   ├── os.sh                        # Operating system and architecture detection
│   └── symlink.sh                   # Safe atomic symlinking with directory backup support
│
├── modules/                         # Stage-based single-responsibility modules
│   ├── 00-packages.sh               # System packages, database servers, and desktop apps
│   ├── 10-dotfiles.sh               # Declarative dotfile auto-discovery and mirroring
│   ├── 20-bin.sh                    # User binaries and Debian shims (fd, bat)
│   ├── 30-fonts.sh                  # MesloLGS Nerd Font Mono (v3) downloader with disk cache
│   ├── 40-mise.sh                   # Mise runtime manager and polyglot toolchains
│   ├── 60-shell.sh                  # Oh-My-Zsh, plugins, shellrc hooks, completions
│   ├── 70-terminal.sh               # Terminal emulator profile provisioning (GNOME Terminal and macOS)
│   └── 99-uninstall.sh              # Clean uninstallation of managed components
│
├── colors/                          # 24-bit TrueColor themes and terminal profiles
│   ├── Solarized-Dark-TrueColor.tmTheme  # Canonical Solarized Dark theme for bat
│   ├── Solarized-Dark.terminal           # macOS Terminal.app Solarized Dark profile
│   └── gnome-terminal-solarized.dconf    # GNOME Terminal Solarized Dark dconf profile
│
├── syntaxes/                        # Enhanced Sublime syntax packages for bat (36 languages)
│   ├── Bash.sublime-syntax          # Bash and POSIX shell syntax
│   ├── C.sublime-syntax             # Modern C23 syntax with granular declaration scopes
│   ├── C++.sublime-syntax           # Modern C++20 and C++23 syntax with concept and template support
│   ├── CSharp.sublime-syntax        # Modern C# 12 and 13 syntax (records, primary constructors, LINQ)
│   ├── CSS.sublime-syntax           # Modern CSS3 and Container Queries syntax
│   ├── Clojure.sublime-syntax       # Clojure syntax (namespaces, macros, protocols, keywords)
│   ├── Diff.sublime-syntax          # Standalone Git and Unified Diff syntax for bat
│   ├── Dockerfile.sublime-syntax    # Multi-stage Dockerfile and Containerfile syntax
│   ├── Elixir.sublime-syntax        # Elixir syntax (GenServer, @spec, @doc, pipe operators, atoms)
│   ├── Go.sublime-syntax            # Go syntax with calm Base0 qualifiers and struct tags
│   ├── GraphQL.sublime-syntax       # Declarative GraphQL schema and query syntax
│   ├── HTML.sublime-syntax          # HTML5 syntax with attribute-guarded script injections
│   ├── Haskell.sublime-syntax       # GHC2021 Haskell syntax (pragmas, typeclasses, GADTs, do)
│   ├── JSON.sublime-syntax          # JSON and JSONC declarative hierarchy syntax
│   ├── Java.sublime-syntax          # Modern Java 25 LTS (records, pattern matching, annotations)
│   ├── JavaProperties.sublime-syntax# Java .properties configuration syntax
│   ├── Kotlin.sublime-syntax        # Modern Kotlin 2.x (value classes, coroutines, annotations)
│   ├── Lua.sublime-syntax           # Modern Lua 5.4 and LuaJIT syntax (<const>, metamethods)
│   ├── Makefile.sublime-syntax      # GNU Make syntax (directives, targets, automatic variables)
│   ├── Markdown.sublime-syntax      # Semantic Architecture Markdown syntax
│   ├── OCaml.sublime-syntax         # OCaml 5 syntax (modules, functors, polymorphic variants)
│   ├── Protobuf.sublime-syntax      # Protocol Buffers (.proto) schema syntax
│   ├── ProtobufText.sublime-syntax  # Protocol Buffers Text Format (.textproto, .pbtxt) syntax
│   ├── Python.sublime-syntax        # Modern Python 3.12+ syntax (type statements, match and case)
│   ├── Rego.sublime-syntax          # Open Policy Agent (OPA Rego v1) policy syntax
│   ├── Ruby.sublime-syntax          # Modern Ruby 3.3+ syntax (Data.define, pattern matching)
│   ├── Rust.sublime-syntax          # Rust syntax with unified attributes and lifetimes
│   ├── SQL.sublime-syntax           # ANSI, PostgreSQL, and MySQL declarative syntax
│   ├── Scala.sublime-syntax         # Scala 3 LTS syntax (enums, given, using, extensions)
│   ├── Starlark.sublime-syntax      # Open-source Bazel and Starlark (.bzl, BUILD.bazel) syntax
│   ├── Swift.sublime-syntax         # Modern Swift 6 (actors, structured concurrency, directives)
│   ├── TOML.sublime-syntax          # TOML syntax with Blue table headers and Green keys
│   ├── Terraform.sublime-syntax     # Terraform and HCL2 infrastructure syntax
│   ├── TypeScript.sublime-syntax    # TypeScript and JavaScript ES2024+ syntax
│   ├── XML.sublime-syntax           # XML syntax with namespaces, directives, and CDATA
│   └── Zig.sublime-syntax           # Modern Zig syntax (comptime, error sets, @builtins)
│
└── tests/                           # Automated test suites (500+ tests across 8 modules)
    ├── test-helper.sh               # Shared assertion library (pass, fail, assert_*, test_summary)
    ├── test-system-setup.sh         # Cross-platform CLI validation, bootstrap, and dry-run tests
    ├── test-dotfiles.sh             # Declarative dotfiles auto-discovery, backup, and drop-ins
    ├── test-bin.sh                  # User binaries symlinking and compatibility shims
    ├── test-env.sh                  # Environment variables, TrueColor, and Bash tests
    ├── test-zsh.zsh                 # Zsh aliases, functions, and live Git integration tests
    ├── test-completions.sh          # Completion symlinks and generator tests
    ├── test-vim.sh                  # Vim and Neovim configuration and snippet tests
    └── test-fonts.sh                # Cross-platform font installation tests
```

## Integrated development environment and AI workspace

The repository provides a terminal-based IDE (`bin/ide`) combining Tmux, Neovim, and AI CLIs (`agy`, `claude`, and `codex`, selectable via `ide --agent <cli>` or `$IDE_AI_CLI`).

- **Spatial window architecture**: Configured in `bin/ide` and `dotfiles/.tmux.conf`:
  - **Single-window geometry**: Runs inside a single Tmux window (`ide`) using an AI-first inverted-T layout:
    - **3-pane layout**: Launched by default via `ide`, `ide3`, or `ide --3pane` with a top-left AI Agent (50%×75%, focused on launch), top-right Main Editor (50%×75%, single Neovim server), and full-width bottom Interactive Shell (100%×25%).
    - **2-pane layout**: Launched via `ide2` or `ide --2pane` with a side-by-side 50% AI Agent and 50% full-height Main Editor.
  - **Interactive top status bar**:
    - **Left session badge**: Displays the session name at a fixed width; click to switch sessions.
    - **Center role switcher**: Shows the `AI`, `Editor`, and `Shell` panes with visual states for focused, unfocused, parked, and zoomed (`Alt+z`). Left-click any badge to focus, restore, or unzoom; right-click for the workspace menu.
    - **Right contextual hints and status**: Shows inline key hints during Tmux prefix (`Ctrl+b`) and copy modes. In normal mode, it displays conditional indicators for synchronized panes (`SYNC`), remote SSH hosts, active subdirectories, and the `Help` cheatsheet button (`Alt+?`).
  - **Pane parking, swapping, splitting, and resizing**:
    - Hide and restore the Editor (`Alt+Shift+E`), Shell (`Alt+Shift+T`), or AI Agent (`Alt+Shift+A`) without stopping running processes, or press `Prefix + b` to break the active pane into a standalone Tmux window and join it back into `ide`.
    - Swap panes directionally with `Alt+Shift+H/J/K/L`, split panes horizontally or vertically in the current working directory with `Prefix + |` or `Prefix + -`, resize by dragging borders with the mouse or pressing `Alt+Left/Down/Up/Right` (`Prefix + H/J/K/L`), and reload `~/.tmux.conf` with `Prefix + r`. Custom pane sizes persist across focus changes, parking, and zoom (`Alt+z`).
  - **Session isolation and quitting**:
    - IDE commands target only the active workspace session so other Tmux sessions are unaffected.
    - Standard Neovim quit commands (`:q`, `:wq`, `:qa`, `:wqa`) close only editor buffers and splits.
    - Workspace quit commands (`:Q`, `:Quit`, `Space q`, `Alt+q`, or `qide`) close the entire IDE session after checking for unsaved changes, while `:Q!`, `Alt+Shift+Q`, and `idek` force-quit immediately.

- **4-layer keybinding architecture**:
  - **Layer 1 (app-local)**: Uses `Ctrl` shortcuts inside individual applications. Tmux never binds root `Ctrl+h/j/k/l`, keeping standard terminal shortcuts (clear screen, newline, kill line, and backspace) intact in shells and AI CLIs. Inside Neovim, `Ctrl+h/j/k/l` navigate editor splits and `Ctrl+j/k` move through Telescope results.
  - **Layer 2 (workspace navigation)**: Uses `Alt` shortcuts across the workspace:
    - `Alt+h/j/k/l` move focus across Neovim splits and Tmux panes from any mode.
    - `Alt+a` (or `Space a`), `Alt+e`, and `Alt+t` jump directly to the AI Agent, Editor, or Shell pane; pressing the same key again bounces back to the previous pane.
    - `Alt+?`, `Space ?`, or `Prefix + ?` opens the interactive keybinding cheatsheet popup (`ide --keys`).
  - **Layer 3 (editor, file explorer, and live reload)**: Uses the `Space` leader key inside Neovim:
    - `Space e` opens the left-anchored `mini.files` column explorer at the current buffer's directory (`Space E` opens at the working directory) with a full-width preview pane on the right. Inside the explorer, navigate with `h/j/k/l` or arrow keys, press `Enter` or double-click to open a file or enter a directory, press `=` to apply file changes to disk, `g?` for help, and `q` to close.
    - `Space w` saves the active buffer (`:w`), and `Space h` clears search highlighting (`:nohlsearch`).
    - `Space m` toggles in-buffer Markdown rendering (`render-markdown.nvim`) with word-boundary soft wrapping.
    - `Space gs` opens Telescope `git_status` to review modified files, while `autoread` automatically reloads buffers edited on disk by AI agents.
    - `H` and `L` cycle open buffers, `Home` toggles between the first non-blank character on the line and column 1 across normal, visual, and insert modes, and `Space cd` (`:IdeCd` in Neovim, or `icd` in the shell) synchronizes the working directory across panes.
  - **Layer 4 (clickable links, jumplist, and clipboard)**:
    - **Terminal links**: `Ctrl+Click` or `Alt+Click` on URLs or prompt pull and merge request badges in the Shell or AI panes opens them in the browser on a local desktop (or via `$IDE_BROWSER`) or copies them to the local clipboard via OSC 52 over SSH. Clicking file paths, compiler errors (`file:line:col`), Markdown file links, or custom `~/.config/ide/links.sh` matches (overridable via `$IDE_LINK_RULES`) opens the target file and line in the Editor.
    - **In-buffer navigation**: Inside Neovim, `Ctrl+Click`, `Alt+Click`, and `gx` follow concealed Markdown links, table-of-contents `#heading` anchors, relative file paths, and web URLs, falling back to LSP go-to-definition on code symbols. In Markdown buffers, `gd` and `Enter` also follow links under the cursor.
    - **Single-step jump back**: Link jumps record a single context mark before switching files or lines, so mouse back and forward buttons (`Mouse4` and `Mouse5`) or `Ctrl+O` and `Ctrl+I` step cleanly backward and forward in the jumplist.
    - **Unified clipboard**: Mouse selection copies immediately in both local and remote SSH sessions (via OSC 52) while keeping the selection highlighted. Press `Alt+c` to copy and clear, `Escape` to clear, or `Alt+v` to paste.

- **LSP, Tree-sitter, and Neovim toolchains**:
  - **Native LSP**: Automatic language server provisioning (`mason.nvim` and `nvim-lspconfig`) for C, C++, Rust, Go, Python, Java (`nvim-jdtls`), Lua, Bash, Terraform, YAML, and JSON. Buffers with an attached language server bind `gd` (go to definition), `gr` (find references), `K` (hover documentation), `Space rn` (rename symbol), `Space ca` (code action), and `Space d` (line diagnostics float). Java buffers (`ftplugin/java.lua`) additionally bind `Space jo` (organize imports), `Space jv` (extract variable), `Space jc` (extract constant), and `Space jm` (extract method).
  - **Tree-sitter and Markdown rendering**: Solarized Dark syntax highlighting aligned with `bat`, plus live in-buffer Markdown formatting (`Space m`) for headings, tables, callouts, checkboxes, and code blocks.
  - **Telescope**: Fuzzy finders for files (`Space ff`), live grep (`Space fg`), open buffers (`Space fb`), and Git status (`Space gs`).
  - **Editor aliases**: `vi`, `vim`, and `v` launch `nvim` (with fallback to `vim`); inside an IDE session, `v [+line] <file>` opens the file directly in the main Editor pane.

### IDE workspace keybindings and navigation

The following table indexes all keyboard shortcuts, mouse actions, editor commands, and environment variables across the IDE workspace:

| Keybinding or action | Context | Description |
| :--- | :--- | :--- |
| `Alt+h/j/k/l` | Universal | Move focus across Neovim splits and Tmux panes |
| `Ctrl+h/j/k/l` | Neovim normal | Move focus across internal Neovim splits (`Ctrl+j/k` move through Telescope results) |
| `Alt+a` or `Space a` | Universal | Focus or unpark AI Agent pane; press again to bounce back |
| `Alt+e` | Universal | Focus or unpark Editor pane; press again to bounce back |
| `Alt+t` | Universal | Focus or unpark Shell pane; press again to bounce back |
| `Alt+Shift+E` | Universal | Hide or restore the Editor pane (`ide --toggle-editor`) |
| `Alt+Shift+T` | Universal | Hide or restore the Shell pane (`ide --toggle-term`) |
| `Alt+Shift+A` | Universal | Hide or restore the AI Agent pane (`ide --toggle-ai`) |
| `Alt+Shift+H/J/K/L` | Tmux | Swap active pane left, down, up, or right (`ide --swap`) |
| `Alt+z` | Tmux | Toggle full-window pane zoom |
| `Alt+Left/Down/Up/Right` or `Prefix + H/J/K/L` | Tmux | Resize active pane by 5 cells (or drag borders with the mouse) |
| `Prefix + \|` or `Prefix + -` | Tmux | Split active pane horizontally (`\|`) or vertically (`-`) in current directory |
| `Prefix + b` | Tmux | Break active pane into a standalone window or join it back into `ide` |
| `Prefix + r` | Tmux | Reload `~/.tmux.conf` configuration |
| `Alt+?`, `Space ?`, or `Prefix + ?` | Universal | Open interactive keybinding cheatsheet popup (`ide --keys`) |
| `Click status bar` | Tmux mouse | Left-click session badge, pane badges, or `Help`; right-click for workspace menu |
| `Alt+c` or `Alt+v` | Universal | Copy selection to clipboard and clear highlight (`Escape` clears) or paste from clipboard |
| `Ctrl+Click` or `Alt+Click` | Shell, AI, and Editor | Open terminal paths, compiler locations, or URLs; follow Markdown links, `#anchors`, or LSP definitions in Neovim |
| `gx` | Neovim normal | Open link under cursor (`#anchor`, file path, or URL), falling back to LSP definition |
| `gd`, `gr`, or `K` | Neovim LSP | Go to definition (`gd`), find references (`gr`), or show hover documentation (`K`) |
| `gd` or `Enter` | Neovim Markdown | Follow Markdown link under cursor, falling back to LSP definition (`gd`) or newline (`Enter`) |
| `Space rn`, `Space ca`, or `Space d` | Neovim LSP | Rename symbol (`Space rn`), run code action (`Space ca`), or show line diagnostics float (`Space d`) |
| `Space jo`, `Space jv`, `Space jc`, or `Space jm` | Neovim Java (JDTLS) | Organize imports (`Space jo`), extract variable (`Space jv`), extract constant (`Space jc`), or extract method (`Space jm`) |
| `Mouse4` or `Mouse5` | Universal and Editor | Jump backward (`Ctrl+O`) or forward (`Ctrl+I`) in the Editor jumplist |
| `Alt+q` or `Space q` | Universal | Quit the IDE workspace after checking for unsaved changes (`Alt+Shift+Q` forces quit) |
| `Space w` or `Space h` | Neovim and Vim normal | Save current buffer (`Space w`) or clear search highlight (`Space h`) |
| `Space e` or `Space E` | Neovim normal | Open `mini.files` explorer at buffer directory or working directory (`h/j/k/l` navigate, `Enter` or double-click open, `=` apply edits, `g?` help, `q` close) |
| `Space ff`, `Space fg`, or `Space fb` | Neovim normal | Find files (`Space ff`), live grep (`Space fg`), or switch buffers (`Space fb`) via Telescope |
| `Space gs` | Neovim normal | Open Telescope `git_status` picker to review modified files |
| `Space m` | Neovim normal | Toggle in-buffer Markdown rendering (`:RenderMarkdown toggle`) |
| `Space cd` or `:IdeCd [dir]` | Neovim normal | Synchronize Editor and Shell working directory |
| `H` or `L` | Neovim normal | Cycle previous or next buffer |
| `Home` | Neovim and Vim (`n/v/i`) | Smart-home: jump to first non-blank character on the line, or toggle to column 1 if already there |
| `:q`, `:wq`, `:qa`, or `:wqa` | Neovim command | Close Neovim window, buffer, or editor normally |
| `:Q` or `:Q!` | Neovim command | Quit entire IDE workspace session (`:Quit`; `!` forces quit) |
| `ide --ai <cli>` or `ide --agent <cli>` | Shell | Select AI CLI agent (`agy`, `claude`, or `codex`, overriding `$IDE_AI_CLI`) |
| `icd [dir\|--reset]` | Shell | Synchronize working directory across Editor and Shell panes |
| `v [+line] <file>` | Shell | Open file in the IDE Editor pane at optional line number |
| `IDE_AI_CLI`, `IDE_BROWSER`, `IDE_LINK_RULES` | Environment | Configure default AI agent CLI, browser executable for URLs, or custom link and session-naming script |

## Interactive shell and Powerlevel10k prompt

Interactive shells are configured for sub-10ms startup times, fast tab completion, and Solarized Dark styling:

- **Zsh engine and completion**: Fast interactive startup with `fpath` tab completions and support for untracked local `*.d/` drop-in directories.
- **Powerlevel10k and Bash Git prompts**: Configured in `.p10k.zsh` and `.bashrc-addendum`:
  - **Single-line shelf prompt**: Solarized Dark Base02 shelf displaying the OS icon, working directory, Git host icon, branch status, and execution telemetry in both Zsh and Bash.
  - **Daemon-free Git status**: Queries `git status --porcelain=v2` directly without `gitstatusd`, supporting standard, SHA-256, and `reftable` repositories.
  - **Clickable pull and merge request badges**: Renders `<branch>@<N>` as a clickable link to the active pull or merge request on GitHub, GitLab, Bitbucket, Gitea, Forgejo, and Codeberg. Pull request numbers are resolved and cached in the background via forge CLIs or `git ls-remote` so the prompt never blocks.
- **Syntax highlighting**: 24-bit Solarized Dark command highlighting (`zsh-syntax-highlighting`) that colors valid commands in Green, strings in Cyan, numbers in Magenta, paths in Blue, and errors in Red while keeping flags and operators in neutral Base0 grey.
- **Autosuggestions and history search**: Asynchronous inline history suggestions (`zsh-autosuggestions`) paired with interactive `Ctrl+R` fuzzy history search via `fzf`.
- **Smart directory jumping**: Frecency-based directory jumping via `zoxide` (`z <dir>`) with interactive tree previews (`zi`).

## Developer toolchains and modern CLI suite

Developer runtimes, language compilers, and modern CLI utilities are managed declaratively in user-space via [mise](https://mise.jdx.dev/) (`.mise.toml`), provisioning LTS Java (17, 21, and 25+), Maven, LTS Node.js, Go, Python, Rust, Terraform, Neovim, and the Tree-sitter CLI alongside a curated suite of 24-bit TrueColor terminal tools:

| Tool | Command or shortcut | Role and Solarized Dark integration |
| :--- | :--- | :--- |
| `java` | `java`, `javac` | LTS Java runtime and compiler (`java = "lts"`, targeting Java 21 and 25 LTS) |
| `maven` | `mvn <goal>` | Apache Maven build automation and dependency manager for Java projects |
| `node` | `node`, `npm`, `npx` | LTS Node.js JavaScript and TypeScript runtime (`node = "lts"`) |
| `go` | `go <cmd>` | Latest stable Go toolchain with XDG-compliant `GOPATH` and `GOCACHE` |
| `python` | `python3`, `pip` | Latest stable Python runtime and package tooling |
| `rust` | `cargo`, `rustc`, `rustup` | Latest stable Rust compiler and Cargo build toolchain |
| `terraform` | `terraform`, `tf` | Infrastructure-as-code CLI with Zsh and Bash tab completion |
| `neovim` | `nvim`, `vi`, `vim`, `v` | Modern Lua editor (`neovim = "latest"`) with Native LSP, Tree-sitter, and Solarized Dark theme |
| `tree-sitter` | `tree-sitter <cmd>` | Tree-sitter parser generator CLI required to compile custom pinned grammar revisions |
| `bat` | `bat <file>`, `b <file>` | TrueColor syntax-highlighting pager with 36 custom syntaxes matching Neovim Tree-sitter (`cat` remains pure coreutils) |
| `delta` | `git diff`, `git show` | TrueColor diff pager with word-level intra-line highlights, line numbers, and subtle Solarized tints |
| `dust` | `ds` | Graphical proportional disk space visualizer (Rust `du -sh` alternative) |
| `tealdeer` | `tldr <cmd>` | Fast offline cheatsheet viewer with Solarized Dark TrueColor styling |
| `glow` | `glow <file>` | Terminal Markdown reader and renderer |
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
| `mise` | `mise <cmd>` | Polyglot runtime manager for all language toolchains and CLI utilities declared in `.mise.toml` |
| `shellcheck` | `shellcheck <script>` | Static analysis linter for POSIX and Bash shell scripts |

## Terminal emulators and system monitoring

Terminal emulator profiles and system monitors are pre-configured with Ethan Schoonover's Solarized Dark palette, calibrated dim-text contrast (`#586E75`), and `MesloLGS Nerd Font Mono` typography:

- **Ghostty**: Configured in `dotfiles/.config/ghostty/config`:
  - 24-bit Solarized Dark theme with `MesloLGS Nerd Font Mono` (12pt), block cursor, flush window edges, and `macos-option-as-alt = true` so `Option` shortcuts map to `Alt`.
  - Built-in split and tab management: `Ctrl+Shift+D` opens a new split (`new_split:auto`), `Ctrl+Shift+W` closes the current surface, `Ctrl+Shift+Enter` toggles split zoom, `Ctrl+Shift+H/J/K/L` move focus across splits, `Ctrl+Shift+T` opens a new tab, and `Alt+Left/Right/Up/Down` forward standard ESC-prefixed sequences (`\x1b[1;3D`, `\x1b[1;3C`, `\x1b[1;3A`, `\x1b[1;3B`) to Tmux and the shell.
  - Automatically linked to `~/.config/ghostty/config` and macOS `Application Support`.
- **GNOME Terminal**: Configured via `bin/gnome-terminal-solarized`:
  - Provisions the Solarized Dark TrueColor profile into `dconf` with `MesloLGS Nerd Font Mono 12`, block cursor, and silent bell.
  - Calibrates ANSI Color 8 to Solarized Base01 (`#586E75`) so dim text and shell autosuggestions remain clearly visible.
- **macOS Terminal.app**: Configured via `bin/macos-terminal-solarized`:
  - Provisions `colors/Solarized-Dark.terminal` as the default profile with `MesloLGS Nerd Font Mono` (12pt), `useOptionAsMetaKey` enabled, and calibrated dim-text and selection contrast.
- **Btop++ system monitor**: Configured in `dotfiles/.config/btop/btop.conf`:
  - Custom Solarized Dark theme (`themes/solarized_dark.theme`) with Braille graphs, rounded borders, and Vim navigation keys (`h/j/k/l` and `g/G`).

| Keybinding | Application | Description |
| :--- | :--- | :--- |
| `Ctrl+Shift+D` | Ghostty | Open a new split automatically (`new_split:auto`) |
| `Ctrl+Shift+W` | Ghostty | Close the active terminal surface (`close_surface`) |
| `Ctrl+Shift+Enter` | Ghostty | Toggle zoom on the active split (`toggle_split_zoom`) |
| `Ctrl+Shift+H/J/K/L` | Ghostty | Move focus across left, bottom, top, or right Ghostty splits |
| `Ctrl+Shift+T` | Ghostty | Open a new terminal tab (`new_tab`) |
| `Alt+Left/Right/Up/Down` | Ghostty | Forward ESC-prefixed arrow sequences to Tmux and shells (with `macos-option-as-alt = true`) |
| `h/j/k/l`, `g/G` | Btop++ | Navigate process lists and jump to top or bottom using Vim keys |

## Extensibility and customization

The repository is structured for local customization without modifying tracked files:

- **Add a dotfile**: Drop any file or directory into `dotfiles/`. It is automatically discovered and symlinked into `$HOME` (backing up any existing physical directory to `.bak.<timestamp>`).
- **Add a CLI utility**: Drop any executable script into `bin/` to symlink it automatically into `~/.local/bin/`.
- **Local drop-in extensions**: Keep machine-specific or private settings in untracked local hooks:
  - `~/.environment-variables.d/*.sh`: Custom exports and `PATH` entries.
  - `~/.aliases.d/*.sh`: Custom shell aliases.
  - `~/.zsh-functions.d/*.zsh`: Custom Zsh functions.
  - `~/.config/ide/links.sh`: Custom workspace hooks for `ide` (overridable via `$IDE_LINK_RULES`):
    - Define `ide_resolve_link WORD CWD` to print a target URL for a clicked token and return `0`.
    - Define `ide_session_name DIR` to print a custom Tmux session name for a workspace directory.
  - `~/.config/zsh/p10k.local.zsh`: Local Powerlevel10k overrides sourced before prompt reload (such as custom folder markers or `POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN` for slow network mounts).
- **Add a provisioning stage**: Drop a numbered script into `modules/` (such as `modules/80-custom.sh`).

## Git and shell shortcuts

Shell aliases in `dotfiles/.aliases` and functions in `dotfiles/.zsh-functions` provide shortcuts for history search, directory jumping, `eza` directory listings, IDE session control, and Git branch maintenance:

| Shortcut | Description |
| :--- | :--- |
| `Ctrl+R` | Fuzzy search command history via `fzf` |
| `z <dir>` | Jump to frecency-ranked directory via `zoxide` |
| `zi` | Interactive directory jump with live `eza` preview |
| `sd <find> <replace> <file>` | Regex find-and-replace via `sd` |
| `b <file>` or `bat` | Syntax-highlighted file viewer (`cat` remains standard coreutils) |
| `vi`, `vim`, or `v` | Launch Neovim (inside `ide`, `v [+line] <file>` opens in the main Editor pane) |
| `ide` or `ide3` | Launch or attach to a 3-pane IDE workspace (`ide --3pane`) |
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
| `fs` | Recursive directory tree search (`fd` and `tree --fromfile`) |
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

## Standalone utilities (`bin/`)

Executable scripts in `bin/` are automatically symlinked into `~/.local/bin/` by `modules/20-bin.sh`. Every utility runs under `set -euo pipefail` and accepts `-h` or `--help` to display command-line usage:

| Script | Key options and arguments | Description |
| :--- | :--- | :--- |
| `gen-passwd` | `-u`, `-l`, `-n`, `-s`, `-t`, `-h, --help`, `[length]` | Generate random passwords with configurable length (default `16`) and character sets (uppercase, lowercase, digits, and symbols) |
| `gnome-terminal-solarized` | `--dry-run`, `-h, --help` | Provision or preview the Solarized Dark TrueColor profile in GNOME Terminal (`dconf`) |
| `ide` | `--3pane`, `--2pane`, `--ai, --agent <cli>`, `--cd [dir\|--reset]`, `--open <file> [line]`, `--keys`, `--quit`, `--kill`, `-h, --help`, `[dir]` | Launch and manage multi-pane Tmux, Neovim, and AI Agent (`agy`, `claude`, `codex`) IDE workspaces |
| `macos-terminal-solarized` | `--dry-run`, `-h, --help` | Provision or preview the Solarized Dark TrueColor profile in macOS `Terminal.app` |
| `repeat-until-success` | `-n <attempts>`, `-s, -d <seconds>`, `-t`, `-h, --help`, `<command> [args...]` | Retry a command up to `N` attempts (default `10`) with a configurable delay in seconds (default `30`) |
| `sum` | `-d <delim>`, `-k <col>`, `-H`, `-a`, `-s`, `-f <fmt>`, `-t`, `-h, --help`, `[numbers... \| files...]` | Sum numbers from stdin, files, or arguments with support for CSV columns, human byte units, averages, and summary statistics |
| `update-system` | `--all`, `--system-only`, `-n, --dry-run`, `-i, --interactive`, `--skip-snaps`, `--skip-snap`, `--skip-flatpak`, `--with-dev, --dev, --tools`, `--no-cleanup`, `--macos-system`, `--os <distro>`, `-y, --yes`, `-h, --help` | Cross-platform system package and toolchain updater (APT, DNF, Homebrew, Pacman, Snap, Flatpak, and Mise) |

## Development and testing

All scripts enforce `set -euo pipefail` for fail-fast safety. Run the full verification pipeline or target individual test suites through `make`:

```bash
# Run full automated test suite (500+ tests across 8 test modules)
make test

# Run individual test suites
make test-system-setup
make test-dotfiles
make test-bin
make test-env
make test-zsh
make test-completions
make test-vim
make test-fonts

# Run syntax, ShellCheck, and documentation lint validation
make lint

# Run both lint and test suites
make check
```
