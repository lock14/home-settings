# home-settings

Home directory configuration files, prompt themes, developer toolchains, and setup automation for modern \*nix systems (**Ubuntu 22.04+ / 24.04+ LTS**, **Fedora 38+**). Provides visual and functional parity with [`windows-settings`](https://github.com/lock14/windows-settings) (PowerShell 7+ / Windows Terminal / Solarized Dark).

---

## Prerequisites

The following tools must be available before running any setup scripts:

- `bash` (5+)
- `git`
- `curl`
- `wget`
- `sudo` access

---

## Supported Platforms & Java Versions

- **Ubuntu**: Ubuntu 22.04+ LTS (Jammy), Ubuntu 24.04+ LTS (Noble)
- **Fedora**: Fedora 38+ / 40+
- **Java**: Actively supported, non-EOL LTS releases only (**OpenJDK 17 LTS**, **OpenJDK 21 LTS**; default: **21**)

---

## Quick Start

### 1. Automated Master Setup (All-in-One)

The master `setup.sh` orchestrator auto-detects your distribution (Ubuntu or Fedora) and configures both system packages and user dotfiles:

```bash
git clone https://github.com/lock14/home-settings.git
cd home-settings
./setup.sh
```

### 2. Turnkey Bootstrap (New Machines)

For a fresh install requiring base dependencies and default shell configuration upfront:

```bash
./bootstrap.sh
```

### 3. Selective & Modular Invocations

```bash
# Preview actions without making changes
./setup.sh --dry-run

# System package provisioning only (apt/dnf, Chrome, Java 21 LTS, Snap IDEs)
./setup.sh --system-only --jdk 21 --ide intellij-ultimate

# Dotfiles and user configuration only (no sudo required)
./setup.sh --dotfiles-only
# or
make install
```

### 4. Distro-Specific Setup Commands

You can run distro-specific workflows directly or pass `--os`:

```bash
# Ubuntu (22.04+ / 24.04+ LTS)
./ubuntu/ubuntu_18+_setup.sh -j 21 -i intellij-ultimate

# Fedora (38+)
./fedora/fedora_30+_setup.sh -j 21 -i intellij-ultimate
```

---

## Command-Line Options (`./setup.sh`)

| Option | Default | Description |
| :--- | :--- | :--- |
| `-j, --jdk <ver>` | `21` | Active Java LTS version to install (`17`, `21`) |
| `-i, --ide <name>` | `intellij-ultimate` | IDE to install (`intellij`, `intellij-ultimate`, `eclipse`, `netbeans`, `code`, `none`) |
| `--os <distro>` | *auto* | Override OS adapter (`ubuntu`, `fedora`) |
| `--dry-run` | *disabled* | Print commands without making modifications |
| `--skip-system` | *disabled* | Skip entire system provisioning (apt/dnf, Chrome, JDK, Snap apps) |
| `--dotfiles-only` | *disabled* | Alias for `--skip-system` |
| `--skip-packages` | *disabled* | Skip OS package manager updates and core CLI tools |
| `--skip-chrome` | *disabled* | Skip Google Chrome installation |
| `--skip-jdk` | *disabled* | Skip OpenJDK installation and alternatives configuration |
| `--skip-snaps` | *disabled* | Skip Snap desktop application provisioning |
| `--skip-user` | *disabled* | Skip user environment and dotfiles configuration |
| `--system-only` | *disabled* | Alias for `--skip-user` |
| `--skip-fonts` | *disabled* | Skip MesloLGS NF font installation |
| `--skip-vim` | *disabled* | Skip Vim configuration and Pathogen plugins |
| `--skip-zsh` | *disabled* | Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k |
| `--skip-bash` | *disabled* | Skip Bash configuration and environment variables |
| `--skip-bin` | *disabled* | Skip `~/bin` utility synchronization |
| `--skip-completions`| *disabled* | Skip CLI tab completions setup |

---

## Repository Architecture

```text
home-settings/
├── setup.sh                         # Master orchestrator (auto-detects OS or accepts --os)
├── bootstrap.sh                     # Turnkey installer (base packages, shell, make install)
├── user-setup.sh                    # User dotfiles orchestrator (make install, zsh, vim, fonts)
├── Makefile                         # Dotfiles symlinks & test targets
├── AGENTS.md                        # Architecture guidelines & agent directives
│
├── system/                          # Common system provisioning modules
│   ├── system-setup.sh              # Common OS setup engine (CLI validation, dispatch)
│   ├── snap-packages.sh             # Shared Snap installer (IntelliJ, VS Code, Slack, Postman)
│   └── java-common.sh               # Shared Java validation & architecture normalization
│
├── ubuntu/                          # Ubuntu-specific adapter (22.04+ / 24.04+ LTS)
│   ├── os-packages.sh               # APT updates, core packages (vim, curl, mariadb, dconf)
│   ├── install-chrome.sh            # Ubuntu Chrome installer
│   ├── install-jdk.sh               # Ubuntu JDK install (17, 21) & update-java-alternatives
│   ├── ubuntu_18+_setup.sh          # Legacy backwards-compatible entrypoint
│   └── bin/
│       └── switch-java-version      # Distro wrapper delegating to common switcher
│
├── fedora/                          # Fedora-specific adapter (38+)
│   ├── os-packages.sh               # DNF updates, core packages, snapd initialization
│   ├── install-chrome.sh            # Fedora Chrome repository & package install
│   ├── install-jdk.sh               # Fedora JDK install (17, 21) & update-alternatives
│   ├── fedora_30+_setup.sh          # Legacy backwards-compatible entrypoint
│   └── bin/
│       └── change-java-version      # Distro wrapper delegating to common switcher
│
├── common-bin/                      # Common utilities deployed to ~/bin/
│   ├── gen-passwd                   # Password generator
│   ├── install-go                   # Go SDK version installer
│   ├── switch-go                    # Go SDK version switcher
│   ├── install-tf                   # Terraform version installer
│   ├── mvn-release                  # Maven release automation
│   ├── repeat-until-success         # Command retry helper
│   ├── sum                          # Number sum utility
│   └── switch-java-version          # Distro-aware Java SDK switcher (Java 17, 21 LTS)
│
└── tests/
    ├── test_system_setup.sh         # System setup CLI validation & dry-run tests
    ├── test_env.sh                  # Environment variables and bash tests
    ├── test_zsh.zsh                 # Zsh aliases, functions, git helpers tests
    ├── test_completions.sh          # Completion symlinks & generator tests
    ├── test_vim.sh                  # Vim configuration & plugin tests
    └── test_fonts.sh                # Font installation & idempotency tests
```

---

## Utility Scripts (`common-bin/`)

| Script | Description |
|---|---|
| `gen-passwd` | Generate random passwords with configurable character sets and lengths |
| `install-go` | Download and install a specific Go version (multi-arch `amd64`/`arm64`) |
| `switch-go` | Switch active Go version via symlink in `~/software/sdk/go` |
| `install-tf` | Download and install a specific Terraform version |
| `mvn-release` | Cut a Maven release: branch, tag, deploy, bump SNAPSHOT |
| `repeat-until-success` | Retry a command up to N times with a configurable sleep interval |
| `sum` | Sum numbers from stdin |
| `switch-java-version` | Switch or list active Java LTS versions (17, 21) across Ubuntu and Fedora |

---

## Development & Testing

All scripts use `set -euo pipefail` to ensure fail-fast safety.

```bash
# Run full test suite
make test

# Run syntax & lint validation
make lint
```
