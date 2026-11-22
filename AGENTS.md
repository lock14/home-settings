# Agent guidelines and repository architecture for home-settings

This repository provides automated workstation provisioning, dotfiles, shell environments, and developer toolchains for modern Unix systems: Debian-based Linux (Ubuntu, Debian, Pop!_OS), RHEL-based Linux (Fedora, RHEL, CentOS Stream, Rocky Linux), and macOS.

Any AI agent interacting with or modifying this repository must strictly adhere to the invariants below and consult the linked domain specifications in `docs/` and `.agents/` when modifying syntax, themes, IDE internals, TUI surfaces, or documentation:

- [Visual precision and semantic color architecture](docs/color-architecture.md): Solarized Dark 14-slot specification, 17-theme rules, universal semantic color contract, Pillars I–IX, and Tree-sitter and Sublime syntax rules.
- [IDE workspace, multiplexer, and portable shell architecture](docs/ide-architecture.md): Single-window Tmux geometry, exact session targeting, single-server Neovim MsgPack-RPC, `Alt+s` lazy switcher docking and scroll preservation, hook-only AI state machine, OSC 8 and OSC 52 routing, and portable `.vimrc` and `.bashrc-addendum` contracts.
- [Monospace TUI design standard and project rules](.agents/rules/monospace-tui.md): `mono-tui v0.2.5` responsive `90`-column versus `80×24` layout breakpoints, width-fitted `fzf` command bars, calm `BASE01` borders with `[PREVIEW]` versus `[LIVE]` badges, 4-tier color capability degradation, and Nerd Font ASCII fallback (paired with [mono-tui-design](.agents/skills/mono-tui-design/SKILL.md) and [mono-tui-audit](.agents/skills/mono-tui-audit/SKILL.md)).
- [Documentation architecture and technical writing style](docs/writing-style.md): Diátaxis macro-to-micro hierarchy, dual representation rule, non-accretion rule, Google and Butterick typography rules, and PR and commit conventions.

## 1. Non-negotiable core invariants and guardrails

| Rule | Invariant | Description |
| :--- | :--- | :--- |
| Never | No hardcoded personal paths | Never commit paths containing personal usernames (`/home/<user>/`, `/Users/<user>/`, Windows profiles). Always use `$HOME`, `${XDG_DATA_HOME:-$HOME/.local/share}`, `${XDG_CONFIG_HOME:-$HOME/.config}`, or `${XDG_CACHE_HOME:-$HOME/.cache}`. |
| Never | No employer-internal names in tracked files | This repository is public. Never commit company-internal hostnames, short links, monorepo paths, or internal product names in code, tests, docs, or commits. Machine-specific hooks belong in untracked `${XDG_CONFIG_HOME:-$HOME/.config}/ide/links.sh` (`$IDE_LINK_RULES`) and `${XDG_CONFIG_HOME:-$HOME/.config}/zsh/p10k.local.zsh`. |
| Never | No blind error suppression | Never redirect `stderr` to `/dev/null` or use blanket quiet flags (`MISE_QUIET=1`) in startup files (`.zshrc-addendum`, `.bashrc-addendum`) or orchestrators. Resolve root causes directly. |
| Never | No default heavy daemons or GUI apps | Database daemons (PostgreSQL, MariaDB) and GUI apps (Chrome, Ghostty, VS Code) are opt-in (`--db`, `--gui`). Only client CLIs install by default. |
| Never | No hardcoded dotfile arrays in setup | Never hardcode dotfile path lists in `setup.sh`. All dotfiles in `dotfiles/` are auto-discovered and mirrored by `setup/modules/10-dotfiles.sh`. |
| Never | No redundant standard Git aliases | Standard Git aliases (`ga`, `gst`, `gco`, `gd`, `gb`, `gl`, `gp`) come from Oh-My-Zsh's `git` plugin. Keep `.aliases` pruned to custom workflows (`gcommit`, `gamend`, `gpush`, `gpushf`, `gpull`, `gup`, `gsync`, `guser-branch`, `gprune`, `gpurge`). |
| Never | No Starship or frozen `gitstatusd` prompt | Prompt is single-line Powerlevel10k Solarized Dark (`POWERLEVEL9K_DISABLE_GITSTATUS=true` in `.p10k.zsh`), using single-fork `git --no-optional-locks status --porcelain=v2 --branch` and async OSC 8 `<branch>@<N>` PR and MR links (see [docs/ide-architecture.md](docs/ide-architecture.md#links-inline-images-clipboard-and-portable-shell-parity)). |
| Never | No EOL Java releases | Only active Java LTS releases (17, 21, 25 LTS) via `.mise.toml` (`java = "lts"`). Never use Java 8 or 11. |
| Never | No nested directory symlinks or in-place font unlinking | Back up physical directories (`.bak.<timestamp>`) before `ln -sfn` via `setup/lib/symlink.sh`. Install fonts (`MesloLGS Nerd Font Mono` v3.3.0+) via atomic `mv -f` from `$cached.tmp.$$.$BASHPID`, never raw `rm -f` under active terminal servers. |
| Never | No piped multi-kilobyte variables to early-terminating consumers | Under `set -euo pipefail`, `echo "$OUT" \| grep -q` triggers `SIGPIPE` (exit 141). Always use Bash here-strings (`grep -Fq "$pat" <<< "$OUT"`) or temp files. |
| Never | No semantic color or syntax contract violations | Never color scope qualifiers (`std::`, `context.`) or factory calls (`NewService`) in accents; never fracture compound tokens (Go struct tags, `#[derive]`, `[[nodiscard]]`, `%s`, `'a`, `--custom-prop`, `#002b36`); never use Yellow in Markdown headings, JSON, YAML, TOML, XML, HTML, CSS, Java Properties, or Protobuf; never bold Markdown headings (`bold = false`); never flatten TOML `[table]` Blue versus `key =` Green; never capture TOML timestamps as Cyan strings; never color `${key}` interpolations as Green declarations; never use high-contrast prompt OS icons, `│` shelf bars, or right-prompt margin gaps (`ZLE_RPROMPT_INDENT=0`); never collide crypto keys (Magenta) with directories or archives or assume uncalibrated ANSI slots; and never remap physical hues in classic daily-driver themes or collide `GREEN`, `YELLOW`, and `RED` in holiday themes (see [docs/color-architecture.md](docs/color-architecture.md)). |
| Never | No Tree-sitter, LSP, or headless Neovim traps | Guard contextual keywords (`(?<!\.)`, `(?!\s*:)`); never capture computed `[expr]` keys as Blue declarations; never rely on `@none` (`fg = nil`) to reset tokens to Base0; never inject `<script>` without `type` guards; supersede upstream `url` metadata in `queries/<lang>/highlights.scm` without `;; extends` and never duplicate `queries/` and `after/queries/` for one language; shield leaf selector tokens with priority `>= 130` and place generic catch-alls before `#lua-match?` rules; set `fg = "NONE"` on `DiagnosticUnderline*`, nullify `documentLinkProvider = nil`, and disable remote schema validation (`jsonls`, `yamlls`); pin `nvim-treesitter` `main` and parser SHAs in `treesitter.lua` and reconcile headlessly via `setup/modules/50-nvim.sh` (`-i NONE` and `GIT_DEFAULT_REF_FORMAT=files`); and never pass multi-line `-c` strings to `nvim --headless` (use `run_nvim_headless`). |
| Never | No root `Ctrl+hjkl` traps, guessed tmux targets, polling chrome, or SSH display spoofing | Keep `Ctrl+hjkl` internal to Neovim splits (`Alt+hjkl` universal), keep `Editor`, `Shell`, and `AI` in one `ide` window with `_ide_park_<role>` parking and single-server `@ide_socket` MsgPack-RPC, target `tmux` sessions by exact `=NAME` / `=NAME:`, isolate `TMUX_TMPDIR` tests with `TMUX=""`, `TMUX_PANE=""`, `NVIM_IDE_SOCKET=""`, and isolated `XDG_RUNTIME_DIR`, preserve `MouseDrag1Border`, navigate Markdown via Tree-sitter AST, transition AI state strictly via `ide state` and `ide ack` with zero `#(...)` polling, never remap `:q`/`:wq`/`:qa`/`:wqa`, never hot-reload live servers from setup modules, and never probe local `:0` displays over SSH or override `vim.g.clipboard` (see [docs/ide-architecture.md](docs/ide-architecture.md)). |
| Never | No feature accretion or typographic violations in docs | Integrate documentation updates holistically into the 4-tier architecture and lookup tables without appending flat lists, bolding code or table keys, or using prose slashes, arrows, or Latin abbreviations (see [docs/writing-style.md](docs/writing-style.md)). |
| Always | Portable `.vimrc` and zero-dependency `.bashrc-addendum` parity | `dotfiles/.vimrc` stays single-file and `dotfiles/.bashrc-addendum` paired with `dotfiles/.config/shell/` requires neither Python nor Zsh (providing all 17 themes, shelf VCS prompt, Readline `Ctrl+r` history drawer fallback, and clean lone-file degradation). |
| Always | Clean entrypoint, `setup/`, `libexec/`, and XDG modular boundaries | Keep `setup.sh`, `Makefile`, `bin/ide`, `bin/theme`, `dotfiles/.config/nvim/init.lua`, and top-level dotfiles as thin orchestrators. Place installer stages in `setup/modules/<NN>-<name>.sh`, installer Bash helpers in `setup/lib/*.sh`, internal Python 3.9+ packages in `libexec/{ide_lib,theme_lib}/*.py` (`from __future__ import annotations`, XDG `PYTHONPYCACHEPREFIX`, zero in-repo `__pycache__`, pure executables in `bin/`), Neovim modules in `lua/solarized/*.lua`, shell modules in `dotfiles/.config/shell/`, Mise LTS and stable tools (including modern Neovim) in `.mise.toml`, XDG `GOPATH` and `GOCACHE`, and `set -euo pipefail` idempotency across all scripts. |

## 2. Component matrix and associated test suites

| Component | Repository source | Target system location | Associated test file |
| :--- | :--- | :--- | :--- |
| Provisioning CLI and task facade | `setup.sh` and `Makefile` | Orchestrator (`./setup.sh`, `curl \| bash`, `make`) | `tests/test-system-setup.sh` |
| Installer libraries and stages | `setup/lib/*.sh` and `setup/modules/*.sh` (`00` through `99`) | Internal runtime for `setup.sh` and `bin/update-system` | `tests/test-system-setup.sh`, `tests/test-dotfiles.sh`, `tests/test-bin.sh` |
| Standalone CLI utilities | `bin/*` (`gen-passwd`, `gnome-terminal-solarized`, `ide`, `macos-terminal-solarized`, `repeat-until-success`, `sum`, `theme`, `update-system`) | `$HOME/.local/bin/` | `tests/test-bin.sh`, `tests/test-theme.sh`, `tests/test-ide-fleet.sh`, `tests/test-system-setup.sh` |
| Internal Python CLI packages | `libexec/ide_lib/*.py` and `libexec/theme_lib/*.py` | Private repository packages imported by `bin/ide`, `bin/theme`, and terminal scripts | `tests/test-ide-fleet.sh`, `tests/test-theme.sh`, `tests/test-bin.sh` |
| Declarative dotfiles and shell runtime | `dotfiles/` and `dotfiles/.config/shell/*.{sh,zsh}` | `$HOME/` and `${XDG_CONFIG_HOME:-$HOME/.config}/` | `tests/test-dotfiles.sh`, `tests/test-env.sh`, `tests/test-zsh.zsh`, `tests/test-completions.sh` |
| Neovim, Tree-sitter, and Vim | `dotfiles/.config/nvim/` (`init.lua`, `lua/solarized/*.lua`, `queries/`, `after/queries/`) and `dotfiles/.vimrc` | `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/` and `$HOME/.vimrc` | `tests/test-vim.sh`, `tests/test-dotfiles.sh` |
| Themes, terminal profiles, and `bat` grammars | `colors/themes/*.theme`, `colors/*.tmTheme`, `colors/gnome-terminal-solarized.dconf`, `colors/Solarized-Dark.terminal`, `syntaxes/*.sublime-syntax` | `${XDG_CONFIG_HOME:-$HOME/.config}/bat/`, `dconf`, `Terminal.app` | `tests/test-theme.sh`, `tests/test-dotfiles.sh`, `tests/test-env.sh` |
| Polyglot toolchains and fonts | `.mise.toml` and `setup/modules/{30-fonts,40-mise}.sh` | `${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml` and XDG or macOS fonts | `tests/test-system-setup.sh`, `tests/test-fonts.sh` |
| Monospace TUI rules and skills | `.agents/rules/monospace-tui.md`, `.agents/skills/mono-tui-design/`, `.agents/skills/mono-tui-audit/` | Scoped agent rules and `mono-tui v0.2.5` reference library governing `bin/ide`, `libexec/ide_lib/`, `libexec/theme_lib/{generators,preview}.py`, `dotfiles/.tmux.conf`, and `lua/solarized/{ide,plugins}.lua` | `tests/test-ide-fleet.sh`, `tests/test-bin.sh`, `tests/test-theme.sh`, `tests/test-vim.sh`, `tests/lint/lint_docs.py` |
| Test runners, static linters, and fixtures | `tests/run.sh`, `tests/lint.sh`, `tests/test-helper.sh`, `tests/lint/*.py`, `tests/fixtures/sample-code/*` | Verification and CI harness | All `tests/test-*.{sh,zsh}` |

## 3. Step-by-step task recipes for agents

Follow these workflows when extending toolchains, CLI options, dotfiles, utilities, or documentation:

- **Adding or updating a toolchain**: Declare `"lts"` (when supported, such as `java` and `node`) or `"latest"` in `.mise.toml`, add distro client packages to `setup/modules/00-packages.sh` if needed, update `.mise.toml` assertions in `tests/test-system-setup.sh` and the table in `README.md`, and run `make check`.
- **Adding a setup CLI option**: Parse the flag in `setup.sh`, implement `--dry-run` and live behavior in `setup/modules/<NN>-*.sh`, assert `--help` and `--dry-run` in `tests/test-system-setup.sh`, document the flag in `README.md`, and run `make check`.
- **Adding shell aliases, functions, or environment variables**: Edit `dotfiles/.config/shell/aliases-core.sh`, `functions.sh`, or `env-defaults.sh` (plus lone-file fallbacks if changing core `PATH` or XDG exports), add coverage in `tests/test-zsh.zsh` or `tests/test-env.sh`, and run `make check`.
- **Adding a managed dotfile**: Place the file or directory in `dotfiles/` (auto-mirrored by `setup/modules/10-dotfiles.sh` and unlinked by `setup/modules/99-uninstall.sh`), add assertions in `tests/test-dotfiles.sh`, and run `make check`.
- **Adding a standalone CLI utility**: Place an executable script (`#!/bin/bash` and `set -euo pipefail`, supporting `-h` and `--help`) in `bin/` (internal Python modules belong in `libexec/`), document it in `README.md`, add tests in `tests/test-bin.sh`, and run `make check`.
- **Adding a provisioning stage**: Create `setup/modules/<NN>-<feature>.sh` sourcing helpers from `$SETUP_DIR/lib/`, honor `DRY_RUN`, `OS`, and `ARCH`, wire it into `setup.sh`, and add tests in `tests/test-system-setup.sh`.
- **Updating documentation**: Follow [docs/writing-style.md](docs/writing-style.md), update both conceptual prose and reference tables in `README.md` (and `AGENTS.md`, `docs/*.md`, or `.agents/` for internal architecture), and verify with `./tests/lint.sh`.

## 4. Anti-patterns and common traps

| Anti-pattern | Why it breaks | Correct implementation |
| :--- | :--- | :--- |
| Masking startup warnings (`2>/dev/null`) | Hides real syntax and configuration errors. | Fix root causes (`mise trust`, `mise install`). |
| Putting library directories inside `bin/` or shell loops in `Makefile` | Pollutes `$PATH` directories and hides shell logic from `shellcheck`. | Keep `bin/` strictly for user executables, Python packages in `libexec/`, installer scripts in `setup/`, and test and lint logic in `tests/{run,lint}.sh` and `tests/lint/*.py`. |
| Inlining subsystem logic into entrypoints | Re-creates monolithic scripts and slows startup or lint isolation. | Keep `setup.sh`, `Makefile`, `bin/ide`, `bin/theme`, and `init.lua` thin; put domain modules in `setup/`, `libexec/`, `lua/solarized/`, and `dotfiles/.config/shell/`. |
| Blind `ln -sfn` over existing directories | Creates nested symlinks (`~/.config/nvim/nvim`). | Use `link_dir` and `link_file` from `setup/lib/symlink.sh`. |
| Hardcoding distro Neovim or `$HOME/go` | Distro Neovim lags modern LSP APIs; default Go paths clutter `$HOME`. | Provision `neovim = "latest"` via `mise` and export XDG `GOPATH` and `GOCACHE`. |
| Polling `#(...)` scripts or screen-column link scraping | Causes `tmux` status stutters and breaks concealed Markdown link clicks. | Use pure-C `tmux` formats with event-driven `@ide_*` options and Tree-sitter AST link traversal. |

## 5. Verification checklist and definition of done

Before concluding any task:

1. **Run static analysis and documentation lint**:
   ```bash
   make lint
   ```
   Executes `./tests/lint.sh` (`zsh -n`, `bash -n`, parallel `shellcheck`, `tests/lint/lint_python.py`, and `tests/lint/lint_docs.py` across `README.md`, `AGENTS.md`, `docs/*.md`, `.agents/`, and `tests/fixtures/sample-code/sample.md`).

2. **Run the automated test suite**:
   ```bash
   make test
   ```
   Executes `./tests/run.sh` across all 10 suites (`system-setup`, `dotfiles`, `bin`, `theme`, `ide-fleet`, `env`, `zsh`, `completions`, `vim`, and `fonts`; pass a suite name such as `./tests/run.sh vim` during targeted iteration).

3. **Verify path hygiene and agent rule budget**:
   Inspect `git diff` to ensure zero personal paths or untracked artifacts were introduced, and keep `AGENTS.md` concise (<24 KB) by placing deep subsystem prose in `docs/*.md` and `.agents/`.
