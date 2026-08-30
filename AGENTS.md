# Agent Guidelines for home-settings

This repository contains workstation setup automation, dotfiles, prompt themes, shell configurations, CLI tab completions, and developer toolchains for **modern Unix systems (Ubuntu 22.04+ / 24.04+ LTS, Fedora 38+ / 40+, and macOS)**.

Any agent modifying this repository must follow these core architectural principles.

---

## 1. Supported Platform & Toolchain Invariants

- **Supported Operating Systems**:
  - **Ubuntu**: Modern LTS releases (**Ubuntu 22.04+ LTS Jammy**, **Ubuntu 24.04+ LTS Noble**).
  - **Fedora**: Actively maintained releases (**Fedora 38+ / 40+**).
  - **macOS**: Modern macOS releases (Apple Silicon `arm64` and Intel `x86_64`).
- **Toolchain & Runtime Management**:
  - Language runtimes and build tools (Java, Maven, Go, Terraform) are managed declaratively via [**`mise`**](https://mise.jdx.dev/) (`.mise.toml`).
  - **Supported Java Versions**: Only actively supported, non-EOL Java LTS releases are permitted (**Java 17 LTS**, **Java 21 LTS**; default: **Java 21 LTS**). Deprecated / EOL versions (Java 8, Java 11) must be rejected with informative error messages.
- **Never Commit Personal User Paths**:
  - Never hardcode personal paths like `/home/brianb/`, `/home/<username>/`, `/Users/<username>/`, or `C:\Users\<username>\` into scripts, configuration files, or tests.
- **Use Canonical Shell & Environment Variables**:
  - User Home: `$HOME`
  - XDG Data Home: `${XDG_DATA_HOME:-$HOME/.local/share}`
  - XDG Config Home: `${XDG_CONFIG_HOME:-$HOME/.config}`
  - XDG Cache Home: `${XDG_CACHE_HOME:-$HOME/.cache}`
  - Fonts: `$HOME/Library/Fonts` on macOS, `${XDG_DATA_HOME:-$HOME/.local/share}/fonts` on Linux.
  - Script Directory: Always resolve dynamically via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
- **Target Directory Structures (`dotfiles/`)**:
  - All portable dotfiles live in `dotfiles/` and are symlinked into `$HOME/`:
    - `dotfiles/.environment-variables` $\to$ `$HOME/.environment-variables`
    - `dotfiles/.bashrc-addendum` $\to$ `$HOME/.bashrc-addendum`
    - `dotfiles/.zshrc-addendum` $\to$ `$HOME/.zshrc-addendum`
    - `dotfiles/.zsh-aliases` $\to$ `$HOME/.zsh-aliases`
    - `dotfiles/.zsh-functions` $\to$ `$HOME/.zsh-functions`
    - `dotfiles/.zsh-completions` $\to$ `$HOME/.zsh-completions`
    - `dotfiles/.p10k.zsh` $\to$ `$HOME/.p10k.zsh`
    - `dotfiles/.vimrc` $\to$ `$HOME/.vimrc`
    - `dotfiles/.dir-colors/dircolors` $\to$ `$HOME/.dir-colors/dircolors`
  - User Binaries: `common-bin/*` symlinked into `${XDG_DATA_HOME:-$HOME/.local}/bin/` (`$HOME/.local/bin/`).
- **Multi-Architecture Support**:
  - Normalize architecture detection across scripts (`x86_64` -> `amd64`, `aarch64` / `arm64` -> `arm64`).

---

## 2. Destructive Safety & Idempotent Automation

- **Mandatory Non-Destructive Operations**:
  - Symlinking must use `ln -sf` (or `ln -sfn` for directories) to prevent creating nested directory symlinks on re-runs.
  - Sourcing blocks added to `~/.bashrc` or `~/.zshrc` must be guarded by `grep -qxF` to prevent duplicate configuration blocks.
- **Idempotency Requirement**:
  - Running setup scripts (`setup.sh`, `Makefile` targets) repeatedly must be completely safe, non-destructive, and not create redundant backups or corrupted states.
- **Support `--dry-run` and Selective Flags**:
  - All provisioning and setup logic in `setup.sh` must support `--dry-run` and provide granular skip switches (`--skip-packages`, `--skip-chrome`, `--skip-apps`, `--skip-fonts`, `--skip-tools`, `--skip-vim`, `--skip-zsh`, `--skip-bash`, `--skip-bin`, `--skip-completions`).
- **Fail-Fast Shell Scripting**:
  - All Bash scripts must begin with `set -euo pipefail` (or `set -o errexit -o nounset -o pipefail`).
  - Validate prerequisites gracefully and report informative errors.

---

## 3. Architecture: Unified Cross-Platform Engine

- **Single Master Orchestrator**:
  - [`setup.sh`](file:///home/brianb/home-settings/setup.sh) serves as the unified entrypoint for both new machine bootstrapping (`--bootstrap`), system package provisioning (`--system-only`), and user dotfile configuration (`--dotfiles-only`).
- **Declarative Package Matrix**:
  - Package manager dispatch (`apt` for Ubuntu, `dnf` for Fedora, `brew` / `brew --cask` for macOS) is handled declaratively in `setup.sh`.
- **Parallel Asset & Plugin Fetching**:
  - Font downloads and Vim/Zsh plugin git clones are executed asynchronously in background jobs to maximize performance.

---

## 4. Shell Performance, Code Quality & Theme Hygiene

- **High-Speed Shell Startup (< 10ms)**:
  - Keep `.environment-variables`, `zshrc-addendum`, and `bashrc-addendum` lightweight. Never run expensive synchronous CLI subcommands (like `go env GOPATH`) on shell startup.
- **Syntax and Lint Compliance**:
  - All bash and sh scripts must pass `bash -n` and `shellcheck` with zero errors.
  - All zsh scripts must pass `zsh -n`.
- **Solarized Dark & Powerline Theme Integrity**:
  - Terminal color schemes, LS_COLORS/dircolors, Zsh autosuggestion highlight styles (`fg=10` / Solarized base01), and Vim Solarized Dark settings must strictly adhere to the Solarized Dark palette and MesloLGS NF typography.

---

## 5. Developer Shortcuts & Standalone Utilities

- **Git Shortcuts**:
  - `gco`, `gcb`, `gcm`, `ga`, `gst`, `gcommit`, `gamend`, `gfetch`, `gpush`, `gpushf`, `gpull`, `gup`, `gprune`, `gsync`, `fix-abcxyz-branch-name`.
- **Developer Shortcuts**:
  - `go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, `tf`, `fs`, `ll`, `la`.
- **Standalone Tools in `common-bin/`**:
  - `gen-passwd`, `sum`, `repeat-until-success`, `mvn-release`.

---

## 6. Verification Checklist for Agents

Before completing any task:
1. **Run Static Analysis & Lint Checks**:
   ```bash
   make lint
   ```
   Ensure shell syntax validations (`zsh -n`, `bash -n`) and `shellcheck` pass cleanly.
2. **Run Test Suite**:
   ```bash
   make test
   ```
   Ensure all test suites in `tests/` pass cleanly:
   - `test-system-setup.sh` (Cross-platform CLI validation, Java LTS enforcement, dry-run, OS dispatching, mise definition)
   - `test-env.sh` (Environment variables, PATH, dircolors, GOPATH instant startup)
   - `test-zsh.zsh` (Aliases, functions, live git integration test, zshrc addendum)
   - `test-completions.sh` (Completions symlinks, generators, idempotency)
   - `test-vim.sh` (Vimrc parsing, mappings, snippet validation)
   - `test-fonts.sh` (Font downloads for Linux and macOS, font idempotency)
3. **Verify Path Invariants**:
   Inspect `git diff` to confirm no hardcoded personal usernames or machine-specific paths were introduced.
4. **Update Documentation**:
   - Update `README.md` if user-facing behavior, options, or tools changed.
   - Update `AGENTS.md` if repository principles or agent workflows changed.
