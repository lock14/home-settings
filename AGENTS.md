# Agent Guidelines & Repository Architecture for home-settings

This repository provides automated workstation provisioning, dotfiles, shell environments, and developer toolchains for **modern Unix systems: Debian-based Linux (Ubuntu, Debian, Pop!_OS), RHEL-based Linux (Fedora, RHEL, CentOS Stream, Rocky Linux), and macOS**.

Any AI agent interacting with or modifying this repository **MUST** strictly adhere to the instructions and invariants below.

---

## 1. Non-Negotiable Core Invariants & Guardrails

| Rule | Invariant | Description |
| :--- | :--- | :--- |
| 🚫 **NEVER** | **No Hardcoded Personal Paths** | Never commit paths containing personal usernames like `/home/brianb/`, `/Users/username/`, or Windows user profiles. Always use `$HOME`, `${XDG_DATA_HOME:-$HOME/.local/share}`, `${XDG_CONFIG_HOME:-$HOME/.config}`, or `${XDG_CACHE_HOME:-$HOME/.cache}`. |
| 🚫 **NEVER** | **No Blind Error Suppression** | Never redirect `stderr` to `/dev/null` or use blanket quiet flags (`MISE_QUIET=1`, etc.) in startup files (`.zshrc-addendum`, `.bashrc-addendum`) or orchestrators. Always resolve the root cause (e.g. trusting configs, installing missing toolchains). |
| 🚫 **NEVER** | **No Default Heavy Daemons / GUI Apps** | Heavyweight database server daemons (PostgreSQL, MariaDB) and GUI applications (Chrome, VS Code) must **never** be installed by default. Only lightweight client CLI tools (`psql`, `mariadb-client`) are installed unless opted into via `--with-postgres`, `--with-mariadb`, `--db <engine>`, or `--with-gui`. |
| 🚫 **NEVER** | **No Redundant Standard Git Aliases** | Standard Git aliases (`ga`, `gst`, `gco`, `gd`, `gb`, `gl`, `gp`) are provided directly by Oh-My-Zsh's `git` plugin. Keep `.aliases` pruned to custom workflows (`gcommit`, `gamend`, `gsync`, `guser-branch`, `gprune`, etc.). |
| 🚫 **NEVER** | **No Starship Prompt** | The shell prompt is strictly single-line **Powerlevel10k Solarized Dark**. Never re-introduce `starship`. |
| 🚫 **NEVER** | **No EOL Java Releases** | Only actively supported Java LTS releases are allowed (**Java 17 LTS**, **Java 21 LTS**; default: **Java 21 LTS**). Deprecated/EOL versions (Java 8, Java 11) must be rejected with informative error messages. |
| 🚫 **NEVER** | **No Nested Directory Symlinks** | When symlinking directory trees (e.g. `${XDG_CONFIG_HOME:-$HOME/.config}/nvim`), always check if the target is an existing physical directory. If so, back it up (`nvim.bak.<timestamp>`) before calling `ln -sfn` to prevent creating nested links (`~/.config/nvim/nvim`). |
| ✅ **ALWAYS** | **LTS Preference for Mise Tools** | For all tools defined in `.mise.toml`, specify `lts` whenever supported by the tool's ecosystem (`java = "lts"`, `node = "lts"`). For tools without an official LTS channel (Go, Python, Maven, Terraform, Rust, Neovim), default to `latest` stable. |
| ✅ **ALWAYS** | **Modern Neovim via Mise** | Modern Neovim (0.11+ / 0.12+) is provisioned via `mise` (`neovim = "latest"`), avoiding obsolete distro packages (such as Ubuntu's default 0.9.5). |
| ✅ **ALWAYS** | **XDG Base Directory Compliance** | Keep `$HOME` clean of language runtime workspaces and cache clutter. Go workspace and cache must strictly point to XDG paths: `export GOPATH="${XDG_DATA_HOME:-$HOME/.local/share}/go"` and `export GOCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/go-build"`. |
| ✅ **ALWAYS** | **Idempotent & Fail-Fast Scripts** | All Bash scripts must begin with `set -euo pipefail`. Re-running `setup.sh` or `Makefile` targets must be completely safe, non-destructive, and produce identical results. |

---

## 2. Component Matrix & Associated Test Suites

| Component | Repository Source | Target System Location | Associated Test File |
| :--- | :--- | :--- | :--- |
| **Unified Setup & Bootstrapper** | `setup.sh` | Orchestrator (Local & `curl \| bash`) | `tests/test-system-setup.sh` |
| **Environment Variables** | `dotfiles/.environment-variables` | `$HOME/.environment-variables` | `tests/test-env.sh` |
| **Zsh Addendum & Hooks** | `dotfiles/.zshrc-addendum` | `$HOME/.zshrc-addendum` | `tests/test-zsh.zsh` |
| **Bash Addendum & Hooks** | `dotfiles/.bashrc-addendum` | `$HOME/.bashrc-addendum` | `tests/test-env.sh` |
| **Shortcuts & Aliases** | `dotfiles/.aliases` | `$HOME/.aliases` (and `$HOME/.zsh-aliases`) | `tests/test-zsh.zsh` |
| **Shell Functions** | `dotfiles/.zsh-functions` | `$HOME/.zsh-functions` | `tests/test-zsh.zsh` |
| **CLI Completions** | `dotfiles/.zsh-completions` | `$HOME/.zsh-completions` | `tests/test-completions.sh` |
| **Powerlevel10k Theme** | `dotfiles/.p10k.zsh` | `$HOME/.p10k.zsh` | `tests/test-zsh.zsh` |
| **Neovim Configuration** | `dotfiles/.config/nvim/init.lua` | `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua` | `tests/test-vim.sh` |
| **Legacy Vim Config** | `dotfiles/.vimrc` | `$HOME/.vimrc` | `tests/test-vim.sh` |
| **Bat TrueColor Theme** | `colors/Solarized-Dark-TrueColor.tmTheme` | `${XDG_CONFIG_HOME:-$HOME/.config}/bat/themes/` | `tests/test-env.sh` |
| **Dircolors Database** | `dotfiles/.dir-colors/dircolors` | `$HOME/.dir-colors/dircolors` | `tests/test-env.sh` |
| **Standalone Binaries** | `common-bin/*` | `${XDG_DATA_HOME:-$HOME/.local}/bin/` | `tests/test-system-setup.sh` |
| **Polyglot Toolchains** | `.mise.toml` | `${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml` | `tests/test-system-setup.sh` |
| **Meslo Nerd Fonts** | Downloaded dynamically | `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/` or macOS Fonts | `tests/test-fonts.sh` |

---

## 3. Visual Precision & Solarized Dark TrueColor Palette

All UI components across terminal, prompt, file viewers, and editor must strictly adhere to the authentic **Ethan Schoonover Solarized Dark** specification in 24-bit TrueColor (`COLORTERM=truecolor`):

| Role | Color Name | Hex Code | Purpose / Usage |
| :--- | :--- | :--- | :--- |
| **Base Background** | `base03` | `#002B36` | Terminal background, Neovim background, bat background |
| **Current Line / Alt Bg** | `base02` | `#073642` | CursorLine, selection background, line highlight |
| **Comments / Dim Borders** | `base01` | `#586E75` | Code comments (italic), eza tree connectors (`xx=38;5;10`), bat borders |
| **Subtle Text** | `base00` | `#657B83` | Secondary text, status indicators |
| **Standard Foreground** | `base0` | `#839496` | Standard typed text, CLI arguments, paths, struct fields, identifiers |
| **Emphasis Text** | `base1` | `#93A1A1` | Bright text, highlighted labels |
| **Keywords & Control** | `green` | `#859900` | `package`, `import`, `func`, `return`, `if`, `for`, `var`, `type`, `struct` |
| **Types & Struct Names** | `yellow` | `#B58900` | Primitive types (`int`, `string`, `bool`), CursorLineNr |
| **Functions & Methods** | `blue` | `#268BD2` | Function declarations, method calls, directory names |
| **Strings & Paths** | `cyan` | `#2AA198` | String literals, file paths |
| **Numbers & Constants** | `magenta` | `#D33682` | Numeric literals, `nil`, `true`, `false`, `iota` |
| **Preprocessors & Headers**| `orange` | `#CB4B16` | Preprocessor macros, compiler directives |
| **Errors & Diagnostics** | `red` | `#DC322F` | Syntax errors, diagnostic warnings |

### Integration Rules
1. **`bat`**: Uses `colors/Solarized-Dark-TrueColor.tmTheme` compiled into cache (`bat cache --build`). `cat` is aliased to `bat --theme="Solarized-Dark-TrueColor" --paging=auto`.
2. **`eza`**: Available via `el` and `et` (`eza --tree`), with `EZA_COLORS` and `EXA_COLORS` configured with Solarized Dark palette. Native `ls` and `ll` use standard GNU/BSD `ls` with Solarized `dircolors`.
3. **Neovim Lua**: Uses `maxmx03/solarized.nvim` with `variant = "spring"` matching `bat` 1:1, integrated with Native Neovim 0.11+ LSP (`vim.lsp.config`, `LspAttach`).
4. **Zsh Autosuggestions**: Highlight style is pinned to `fg=10` (Solarized Base01).

---

## 4. Step-by-Step Task Recipes for Agents

### Recipe A: Adding or Updating a Developer Toolchain
1. Edit `.mise.toml` to declare the tool:
   - Use `"lts"` if the tool ecosystem supports LTS releases (e.g. `java = "lts"`, `node = "lts"`).
   - Use `"latest"` for all other stable tools (e.g. `go = "latest"`, `python = "latest"`, `neovim = "latest"`).
2. If client CLI utilities are needed from distro package managers, add them to `setup.sh` package lists.
3. Update `.mise.toml` validation in `tests/test-system-setup.sh`.
4. Run `make test` and `make lint` to verify.

### Recipe B: Adding a Setup CLI Switch / Option
1. Update `setup.sh` argument parser (`while [ $# -gt 0 ]; do ... done`).
2. Implement `--dry-run` branch and live branch.
3. Add a test case in `tests/test-system-setup.sh` asserting both `--help` and `--dry-run` behavior.
4. Update the CLI Options table in `README.md`.
5. Update `AGENTS.md` if the option establishes a new invariant.
6. Run `make test` and `make lint`.

### Recipe C: Adding a Custom Git Workflow or Developer Shortcut
1. Add the alias to `dotfiles/.aliases` (or function to `dotfiles/.zsh-functions` if multi-line).
2. Ensure no standard Oh-My-Zsh git aliases are duplicated.
3. Add the alias/function name to the assertion list in `tests/test-zsh.zsh`.
4. Run `make test` and `make lint`.

### Recipe D: Modifying Environment Variables or PATH
1. Edit `dotfiles/.environment-variables`.
2. Ensure XDG paths (`XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`) are respected.
3. Update assertions in `tests/test-env.sh`.
4. Run `make test` and `make lint`.

---

## 5. Anti-Patterns & Common Traps (What NOT to Do)

| Anti-Pattern | Why It Breaks | Correct Implementation |
| :--- | :--- | :--- |
| **Masking Startup Warnings (`2>/dev/null`)** | Hides real syntax/configuration errors from the user. | Fix the root cause (trust configs via `mise trust`, install missing runtimes via `mise install`). |
| **Blind `ln -sfn` Over Existing Directory** | Creates a nested symlink (`~/.config/nvim/nvim -> ...`) instead of replacing the directory. | Check `if [ -d "$target" ] && [ ! -L "$target" ]`, back it up to `.bak.<timestamp>`, then symlink. |
| **Hardcoding Distro Neovim Paths** | Ubuntu 22.04 apt installs Neovim 0.9.5, which crashes modern LSP plugins. | Rely on modern Neovim provisioned via `mise` (`neovim = "latest"`). |
| **Letting Go Pollute `$HOME/go`** | Clutters user home directory. | Export XDG variables: `GOPATH="$HOME/.local/share/go"` and `GOCACHE="$HOME/.cache/go-build"`. |
| **Installing Database Daemons by Default** | Consumes system memory, starts unwanted background services, and opens local listening ports. | Install only client CLIs by default; require `--with-postgres`, `--with-mariadb`, or `--db <engine>` for server daemons. |

---

## 6. Verification Checklist & Definition of Done

Before concluding any turn or marking any task complete:

1. **Run Static Analysis & Lint Checks**:
   ```bash
   make lint
   ```
   Ensures `shellcheck` and shell syntax checks (`bash -n`, `zsh -n`) pass with 0 warnings.

2. **Run Full Test Suite**:
   ```bash
   make test
   ```
   Ensures all 100+ validation tests across all 6 test modules pass with 0 failures:
   - `test-system-setup.sh`: Cross-platform CLI, Java LTS validation, dry-run, OS dispatching, Mise definitions, bootstrapper.
   - `test-env.sh`: Environment variables, PATH, COLORTERM, BAT_THEME, EZA_COLORS, dircolors, XDG GOPATH/GOCACHE.
   - `test-zsh.zsh`: Git aliases, functions, live git repo integration, zshrc addendum.
   - `test-completions.sh`: Completions symlinks, generators, idempotency.
   - `test-vim.sh`: Vimrc options/mappings, Neovim Lua syntax & plugin validation.
   - `test-fonts.sh`: Linux and macOS font downloads, font idempotency.

3. **Verify Path Invariants**:
   Inspect `git diff` to guarantee no personal usernames, host-specific paths, or unintended files were introduced.

4. **Synchronize Documentation**:
   - Update `README.md` if user-facing behavior, options, or tools changed.
   - Update `AGENTS.md` if repository principles or agent workflows changed.
