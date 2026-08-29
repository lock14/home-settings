# home-settings

Workstation setup automation, prompt themes, developer toolchains, and dotfiles for modern Unix systems (**Ubuntu 22.04+ / 24.04+ LTS**, **Fedora 38+ / 40+**, and **macOS** Apple Silicon / Intel).

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
  - **Java**: Non-EOL LTS releases only (**Temurin / OpenJDK 21 LTS** default, **17 LTS**)
  - **Go**: Latest Go runtime
  - **Terraform**: Latest Terraform binary

---

## Quick Start

### 1. Automated Master Setup (All-in-One)

The master `setup.sh` orchestrator auto-detects your platform (**Ubuntu**, **Fedora**, or **macOS**) and provisions system packages, desktop tools, and user dotfiles:

```bash
git clone https://github.com/lock14/home-settings.git
cd home-settings
./setup.sh
```

### 2. Turnkey Bootstrap (New Machines)

For a fresh install requiring base dependencies, shell switching, and full dotfiles setup:

```bash
./setup.sh --bootstrap
```

### 3. User Dotfiles Only (No `sudo` Required)

To install dotfiles, fonts, user bin tools, and editor plugins without modifying system packages:

```bash
./setup.sh --dotfiles-only
# or
make install
```

### 4. Preview Changes (Dry Run)

```bash
./setup.sh --dry-run
```

---

## Command-Line Options (`./setup.sh`)

| Option | Default | Description |
| :--- | :--- | :--- |
| `--bootstrap` | *disabled* | Full new machine bootstrap (base packages, shell switch, tools, dotfiles) |
| `--dotfiles-only` | *disabled* | Configure user dotfiles, fonts, and tools only (no root required) |
| `--system-only` | *disabled* | Provision OS packages, desktop apps, and CLI tools only |
| `--dry-run` | *disabled* | Preview actions without making system changes |
| `--os <distro>` | *auto* | Override OS target (`ubuntu`, `fedora`, `macos`) |
| `-j, --jdk <ver>` | `21` | Active Java LTS version (`17`, `21`) |
| `-i, --ide <name>` | `intellij-ultimate` | IDE to install (`intellij`, `intellij-ultimate`, `code`, `eclipse`, `netbeans`, `none`) |
| `--skip-system` | *disabled* | Skip system package updates and application provisioning |
| `--skip-packages` | *disabled* | Skip core system package manager installs |
| `--skip-chrome` | *disabled* | Skip Google Chrome installation |
| `--skip-apps` | *disabled* | Skip desktop applications (VS Code, Postman, Slack, IDE) |
| `--skip-user` | *disabled* | Skip user dotfiles and environment configuration |
| `--skip-fonts` | *disabled* | Skip MesloLGS NF font installation |
| `--skip-tools` | *disabled* | Skip Mise polyglot toolchain runtime installation |
| `--skip-vim` | *disabled* | Skip Vim configuration and plugins |
| `--skip-zsh` | *disabled* | Skip Zsh dotfiles, Oh-My-Zsh, plugins, and Powerlevel10k |
| `--skip-bash` | *disabled* | Skip Bash configuration and environment variables |
| `--skip-bin` | *disabled* | Skip `~/bin` utility symlinks |
| `--skip-completions`| *disabled* | Skip CLI tab completions generation |

---

## Repository Architecture

```text
home-settings/
├── setup.sh                         # Master cross-platform setup & bootstrap engine
├── Makefile                         # Lifecycle targets (install, uninstall, test, lint)
├── .mise.toml                       # Mise polyglot runtime toolchain (Java 21, Go, Terraform)
├── AGENTS.md                        # Architecture principles & agent directives
│
├── dotfiles/                        # Centralized, portable dotfile tree
│   ├── .environment_variables       # Sub-millisecond environment & PATH exports
│   ├── .bashrc-addendum             # Bash integration hook
│   ├── .zshrc_addendum              # Zsh integration hook & plugin loader
│   ├── .zsh_aliases                 # Git, Golang, and Terraform shortcuts
│   ├── .zsh_functions               # Git synchronization (gsync) & search (fs)
│   ├── .zsh_completions             # Fpath completion registration
│   ├── .p10k.zsh                    # Powerlevel10k prompt configuration
│   ├── .vimrc                       # Solarized Dark Vim configuration
│   └── .dir_colors/dircolors        # Solarized Dark dircolors database
│
├── common-bin/                      # Standalone Unix utilities (symlinked to ~/bin/)
│   ├── gen-passwd                   # Password generator with custom character sets
│   ├── sum                          # High-performance AWK number summation & stats
│   ├── repeat-until-success         # Command retry loop with configurable delay
│   └── mvn-release                  # Automated Maven release branching and tagging
│
├── code-style/                      # Eclipse Java code formatting XML profiles
│
├── .vim/                            # UltiSnips snippets (C, Java) & Pathogen autoload
│
└── tests/                           # Automated test suites
    ├── test_system_setup.sh         # Cross-platform CLI validation & dry-run tests
    ├── test_env.sh                  # Environment variables and bash tests
    ├── test_zsh.zsh                 # Zsh aliases, functions, git helpers tests
    ├── test_completions.sh          # Completion symlinks & generator tests
    ├── test_vim.sh                  # Vim configuration & snippet tests
    └── test_fonts.sh                # Cross-platform font installation tests
```

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
# Run full automated test suite
make test

# Run syntax & lint validation
make lint
```
