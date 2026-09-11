# Workstation Architecture & Environment Specification

An authoritative technical overview of the workstation configuration, directory topologies, developer toolchains, and visual presentation layer for modern Unix systems (**Debian/Ubuntu**, **Fedora/RHEL**, and **macOS**).

---

## 1. Executive Summary & Design Philosophy

The developer workstation environment provides an automated, idempotent configuration pipeline designed for reproducible development. By strictly adhering to the **XDG Base Directory Specification** and leveraging Ethan Schoonover's authentic **Solarized Dark TrueColor** palette, the setup achieves maximum readability and zero clutter in `$HOME`.

> "Solarized is a sixteen color palette designed for use with terminal and GUI applications. It includes unique properties and is tested extensively in real-world use."
> — Ethan Schoonover, *Solarized Specification*

Key architectural tenets include:
- **Declarative Configuration**: All user preferences, toolchains, and dotfiles are defined declaratively and mirrored into place without hardcoded personal usernames.
- **Fail-Fast & Idempotent**: Scripts execute with `set -euo pipefail`. Running `./setup.sh` multiple times produces completely deterministic, repeatable results.
- **Visual Precision**: Single-line Powerlevel10k shell prompt, TrueColor (`COLORTERM=truecolor`) rendering, and full 1:1 syntax highlight parity between `bat` and Neovim (`nvim`).
- **Standard Tool Preservation**: Core Unix utilities like standard coreutils `cat` remain unaliased, while modern enhancements like `bat` and `eza` are provided via dedicated, ergonomic shortcuts (`b`, `el`, `et`).

---

## 2. Core Subsystems & Directory Layout

### 2.1 File System Topology & XDG Compliance

Workspaces, local binaries, cache trees, and configuration files strictly honor XDG Base Directory environment variables. User home directories remain clean of language runtime workspaces and temporary files.

| Environment Variable | Target Path | Purpose / Managed Contents | Persistence |
| :--- | :--- | :--- | :--- |
| `${XDG_CONFIG_HOME}` | `$HOME/.config/` | Application configs (`nvim/`, `ghostty/`, `bat/`, `mise/`) | Permanent |
| `${XDG_DATA_HOME}` | `$HOME/.local/share/` | Standalone runtimes, Go workspace (`$GOPATH`), fonts | Permanent |
| `${XDG_CACHE_HOME}` | `$HOME/.cache/` | Go build cache (`$GOCACHE`), `bat` themes binary cache | Ephemeral |
| `${XDG_STATE_HOME}` | `$HOME/.local/state/` | Shell command history files, editor undo trees | Permanent |
| `${PATH}` Prefix | `$HOME/.local/bin/` | Symlinked custom utilities and standalone CLI tools | Permanent |

### 2.2 Shell Environment & Hook Pipeline

When an interactive shell session starts, initialization occurs through a structured sequential pipeline:

1. **Environment Initialization**: Sources `~/.environment-variables` to export `EDITOR=nvim`, `COLORTERM=truecolor`, `BAT_THEME="Solarized-Dark-TrueColor"`, and `BAT_OPTS="--italic-text=always"`.
2. **Path Resolution**: Prepends `${XDG_DATA_HOME}/bin` and `${HOME}/.local/bin` to ensure user binaries take precedence over distro defaults.
3. **Shell Addendum Loading**: Executes `~/.zshrc-addendum` (or `~/.bashrc-addendum`) to register completions, Oh-My-Zsh plugins, and custom aliases.
4. **Visual Palette Registration**: Configures Zsh Line Editor (`ZLE`) highlighters and dircolors.

#### 2.2.1 Syntax Highlighting & Token Classification

The visual presentation layer uses restrained, non-distracting 24-bit TrueColor tokens:

*   **Executable Commands**: Solarized Green (`#859900`)
*   **Strings & Paths**: Solarized Cyan (`#2AA198`) with underline on file targets
*   **Functions & Methods**: Solarized Blue (`#268BD2`)
*   **Options & Arguments**: Solarized Base0 (`#839496`)
*   **Selections & Visual Range**: Solarized Base02 (`#073642`) background highlight

##### 2.2.1.1 Error Token & Diagnostic Handling

Any unrecognized command token, malformed redirection, or missing delimiter triggers an immediate visual feedback signal using Solarized Red (`#DC322F`), alerting the developer before pressing Return.

###### Operational Verification Checklist

- [x] TrueColor 24-bit terminal capability confirmed (`COLORTERM=truecolor`)
- [x] Solarized Dark TrueColor theme compiled into `~/.cache/bat/themes.bin`
- [x] Neovim 0.11+ Treesitter highlights aligned 1:1 with `bat`
- [x] MesloLGS NF font rendering correctly with Powerlevel10k glyphs
- [ ] User custom aliases drop-in verified (`~/.aliases.d/*.sh`)

---

## 3. Quickstart & Toolchain Provisioning

### 3.1 Initial Installation

To clone and bootstrap a new workstation, run the modular orchestrator CLI:

```bash
# Clone the configuration repository
git clone https://github.com/example/home-settings.git "$HOME/home-settings"
cd "$HOME/home-settings"

# Run non-destructive bootstrap (install packages, link dotfiles, compile themes)
./setup.sh --verbose

# Source the newly established shell environment
source "$HOME/.zshrc"
```

### 3.2 Key Developer Shortcuts

The environment provisions ergonomic shortcuts for common daily workflows:

- `b <file>`: Fast syntax-highlighted pager via `bat` with line numbers and Git modification markers.
- `v <file>` or `vi <file>`: Modern Neovim editor with LSP integration.
- `el` / `elt`: Directory listing and tree view via `eza` with Solarized file metadata colors.
- `gsync`: Synchronize feature branches with `main` cleanly using rebase and stash preservation.
- `gprune`: Safely delete merged local tracking branches.

---

### Further Reading & External References

*   [Ethan Schoonover's Solarized Homepage](https://ethanschoonover.com/solarized/) — Official color specifications and mathematical CIELAB coordinates.
*   [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) — Standards for modern Unix filesystem cleanliness.
*   [Powerlevel10k Theme Documentation](https://github.com/romkatv/powerlevel10k) — Fast, customizable Zsh prompt engine.
