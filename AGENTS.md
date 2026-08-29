# Agent Guidelines for home-settings

This repository contains workstation configuration files, dotfiles, prompt themes, shell configurations, CLI tab completions, and setup automation for **modern Linux (*nix) systems (Ubuntu 22.04+ / 24.04+ LTS, Fedora 38+)**. It is the reference repository providing visual and functional parity with [`windows-settings`](https://github.com/lock14/windows-settings) (PowerShell 7+ / Windows Terminal / Solarized Dark).

Any agent modifying this repository must follow these core principles.

---

## 1. Supported Platform & Toolchain Invariants

- **Supported Operating Systems**:
  - **Ubuntu**: Modern LTS releases only (**Ubuntu 22.04+ LTS Jammy**, **Ubuntu 24.04+ LTS Noble**).
  - **Fedora**: Actively maintained releases (**Fedora 38+ / 40+**).
- **Supported Java Versions**:
  - Only actively supported, non-EOL Java LTS releases are permitted (**Java 17 LTS**, **Java 21 LTS**).
  - Deprecated / End-of-Life versions (Java 8, Java 11) must be rejected with informative error messages.
  - The default JDK version across the repository is **Java 21 LTS**.
- **Never Commit Personal User Paths**:
  - Never hardcode personal paths like `/home/brianb/`, `/home/<username>/`, `/Users/<username>/`, or `C:\Users\<username>\` into scripts, configuration files, or tests.
- **Use Canonical Shell & Environment Variables**:
  - User Home: `$HOME`
  - XDG Data Home: `${XDG_DATA_HOME:-$HOME/.local/share}`
  - XDG Config Home: `${XDG_CONFIG_HOME:-$HOME/.config}`
  - XDG Cache Home: `${XDG_CACHE_HOME:-$HOME/.cache}`
  - Script Directory: Always resolve dynamically via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
- **Standard Target Directory Structures**:
  - **Zsh Dotfiles**: `$HOME/.zshrc`, `$HOME/.zsh_aliases`, `$HOME/.zsh_functions`, `$HOME/.zshrc_addendum`, `$HOME/.zsh_completions`
  - **Bash Dotfiles**: `$HOME/.bashrc`, `$HOME/.bashrc-addendum`, `$HOME/.environment_variables`
  - **Powerlevel10k Theme**: `$HOME/.p10k.zsh`
  - **Vim Runtime & Configuration**: `$HOME/.vimrc`, `$HOME/.vim/`
  - **User Fonts**: `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/`
  - **User Binaries**: `$HOME/bin/` and `$HOME/software/bin/` (registered in `$PATH`)
- **Multi-Architecture Support**:
  - Normalize architecture detection across scripts (`x86_64` -> `amd64`, `aarch64` / `arm64` -> `arm64`).

---

## 2. Destructive Safety & Idempotent Automation

- **Mandatory Non-Destructive Operations**:
  - Symlinking must use `ln -sf` (or `ln -sfn` for directories) to prevent creating nested directory symlinks on re-runs.
  - Sourcing blocks added to `~/.bashrc` or `~/.zshrc` must be guarded by `grep -qxF` to prevent duplicate configuration blocks.
- **Idempotency Requirement**:
  - Running setup scripts (`setup.sh`, `user-setup.sh`, `zsh-setup.sh`, `system-setup.sh`) repeatedly must be completely safe, non-destructive, and not create redundant backups or corrupted states.
- **Support `--dry-run` and Selective Flags**:
  - All provisioning and setup scripts must support `--dry-run` where applicable and provide granular skip switches (`--skip-packages`, `--skip-snaps`, `--skip-chrome`, `--skip-fonts`, etc.).
- **Fail-Fast Shell Scripting**:
  - All Bash scripts must begin with `set -euo pipefail` (or `set -o errexit -o nounset -o pipefail`).
  - Validate prerequisites gracefully and report informative errors.

---

## 3. Modular Architecture: Common vs. Distro-Specific

- **Maximize Shared Common Logic**:
  - Generic CLI parsing, validation, logging, and distro-agnostic package installers (such as Snap apps: IntelliJ, VS Code, Postman, Slack) live in `system/` or `common-bin/`.
- **Relegate Distro Differences to Adapter Directories**:
  - Package manager commands (`apt` vs `dnf`), package name variations (`dconf-cli` vs `dconf`), distro repository setup (Chrome), and alternative link managers (`update-java-alternatives` vs `update-alternatives`) must reside in `ubuntu/` and `fedora/`.
- **Top-Level Orchestration**:
  - Top-level [`setup.sh`](file:///home/brianb/home-settings/setup.sh) auto-detects the operating system (`/etc/os-release`) and delegates to the appropriate adapters while maintaining backward compatibility with legacy entrypoints (`ubuntu/ubuntu_18+_setup.sh`, `fedora/fedora_30+_setup.sh`).

---

## 4. Shell Performance, Code Quality & Theme Hygiene

- **High-Speed Shell Startup**:
  - Keep `zshrc_addendum` and `bashrc-addendum` lightweight. Heavy operations should be lazy-loaded or cached.
- **Syntax and Lint Compliance**:
  - All bash and sh scripts must pass `bash -n` and `shellcheck` with zero errors.
  - All zsh scripts must pass `zsh -n`.
- **Solarized Dark & Powerline Theme Integrity**:
  - Terminal color schemes, LS_COLORS/dircolors, Zsh autosuggestion highlight styles (`fg=10` / Solarized base01), and Vim Solarized Dark settings must strictly adhere to the Solarized Dark palette and MesloLGS NF typography.
  - In Vim, `highlight Normal ctermbg=NONE` and `highlight NonText ctermbg=NONE` ensure seamless integration with the terminal background.

---

## 5. Cross-Platform Parity with `windows-settings`

- **Maintain Alias & Shortcut Parity**:
  - Git shortcuts: `gco`, `gcb`, `gcm`, `ga`, `gst`, `gcommit`, `gamend`, `gfetch`, `gpush`, `gpushf`, `gpull`, `gup`, `gprune`, `gsync`, `fix-abcxyz-branch-name`.
  - Developer shortcuts: `go_testall`, `go_buildall`, `go_lint`, `yaml_lint`, `tf`, `fs`, `ll`, `la`.
- **Native Utility Parity in `common-bin/`**:
  - Keep utility tools in `common-bin/` (`gen-passwd`, `repeat-until-success`, `sum`, `install-go`, `switch-go`, `install-tf`, `mvn-release`, `switch-java-version`) matching the behavior and flags of their PowerShell equivalents in `windows-settings/bin/`.
- **Vim Plugins & Snippets**:
  - Pathogen bundle parity: `vim-colors-solarized`, `auto-pairs`, `ultisnips`, `supertab`.

---

## 6. Documentation Boundaries & Mandatory Updates

- **Mandatory Documentation Synchronization**:
  - Whenever new aliases, functions, CLI utilities, setup parameters, or distro modules are added or modified, update `README.md` in the same commit/PR.
- **`README.md` is for Users**:
  - Focus on user-facing instructions: prerequisites, quick start, directory structure, CLI flags, shortcuts, and utility examples.
- **`AGENTS.md` is for Agents & Contributors**:
  - Architectural principles, path invariants, lint rules, testing workflows, and agent directives belong exclusively in `AGENTS.md`.

---

## 7. Continuous Learning & Principle Encoding

- **Persist User Corrections**:
  - Whenever an agent receives feedback, corrections, or instructions regarding repository conventions, it **must immediately encode the underlying principle into `AGENTS.md`** before concluding the task.

---

## 8. Verification Checklist for Agents

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
   - `test_system_setup.sh` (Modular system setup CLI flags, Java LTS enforcement, dry-run, OS dispatching)
   - `test_env.sh` (Environment variables, PATH, dircolors)
   - `test_zsh.zsh` (Aliases, functions, git helpers, zshrc addendum)
   - `test_completions.sh` (Completions symlinks, generators)
   - `test_vim.sh` (Vimrc parsing, mappings, options)
   - `test_fonts.sh` (Font downloads and font-setup idempotency)
3. **Verify Path Invariants**:
   Inspect `git diff` to confirm no hardcoded personal usernames or machine-specific paths were introduced.
4. **Update Documentation**:
   - Update `README.md` if user-facing behavior, options, or tools changed.
   - Update `AGENTS.md` if repository principles or agent workflows changed.
