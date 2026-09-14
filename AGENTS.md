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
| 🚫 **NEVER** | **No Hardcoded Dotfile Arrays in Setup** | Never maintain hardcoded lists of dotfile paths in `setup.sh`. All dotfiles must be auto-discovered declaratively by `modules/10-dotfiles.sh` and mirrored to `$HOME`. |
| 🚫 **NEVER** | **No Redundant Standard Git Aliases** | Standard Git aliases (`ga`, `gst`, `gco`, `gd`, `gb`, `gl`, `gp`) are provided directly by Oh-My-Zsh's `git` plugin. Keep `.aliases` pruned to custom workflows (`gcommit`, `gamend`, `gsync`, `guser-branch`, `gprune`, `gpurge`, etc.). |
| 🚫 **NEVER** | **No Starship Prompt** | The shell prompt is strictly single-line **Powerlevel10k Solarized Dark**. Never re-introduce `starship`. |
| 🚫 **NEVER** | **No EOL Java Releases** | Only actively supported Java LTS releases are allowed (**Java 17 LTS**, **Java 21 LTS**, **Java 25 LTS**). Deprecated/EOL versions (Java 8, Java 11) must never be used. Runtimes are managed declaratively via `.mise.toml` (`java = "lts"`). |
| 🚫 **NEVER** | **No Nested Directory Symlinks** | When symlinking directory trees (e.g. `${XDG_CONFIG_HOME:-$HOME/.config}/nvim`), always check if the target is an existing physical directory. If so, back it up (`nvim.bak.<timestamp>`) before calling `ln -sfn` to prevent creating nested links (`~/.config/nvim/nvim`). Enforced via `lib/symlink.sh`. |
| 🚫 **NEVER** | **No Chromatic Noise on Scope Qualifiers** | Never color prefix qualifiers (`std::`, `boost::`, `context.`, `fmt.`) in accent colors. Only formal declaration sites (`package main`, `namespace core::telemetry`, `using namespace ...`) receive Violet (`#6C71C4`); qualifiers in code strictly remain in calm Base0 Grey (`#839496`). |
| 🚫 **NEVER** | **No Semantic Flipping for Factory Functions** | Never color factory function calls (`NewClusterNode`, `NewService`) in Yellow as constructors. In languages like Go where constructors are standard functions, function invocations strictly remain in calm Base0 Grey (`#839496`) alongside all routine invocations. |
| 🚫 **NEVER** | **No Token Fracturing in Structured Strings or Attributes** | Never fracture compound constructs like Go struct tags (``` `json:"port"` ```), C++ attributes (`[[nodiscard]]`), Rust attributes (`#[derive]`, `#[inline]`), printf format specifiers (`%s\n`), diff lines (`+ line`), or Rust lifetimes (`'a`, `'static`) into multi-colored checkerboards. They must remain unified in their primary accent. |
| 🚫 **NEVER** | **No Piped Multi-Kilobyte Variables to Early-Terminating Consumers** | Under `set -euo pipefail`, piping multi-kilobyte strings into early-terminating consumers (e.g. `echo "$OUT" \| grep -q`) triggers `SIGPIPE` (exit 141) on the producer. Always use Bash here-strings (`grep -Fq "$pattern" <<< "$OUT"`) or temporary files to ensure 100% deterministic test execution. |
| 🚫 **NEVER** | **No Yellow in Markdown Headings** | Never use Solarized Yellow (`#B58900`) for Markdown headings. Headings strictly follow Semantic Architecture: H1 Orange (`#CB4B16`), H2 Blue (`#268BD2`), H3 Violet (`#6C71C4`), H4 Base1 (`#93A1A1`), H5/H6 Base0 (`#839496`), with `#` delimiter sigils in Base01 (`#586E75`). Yellow is reserved exclusively for control flow / execution pathways inside embedded code blocks. |
| 🚫 **NEVER** | **No Artificial Bold Typography in Headings** | Never apply bold font styles across Markdown headings (`bold = false`). Monospace character metrics and zero-jitter layout are strictly preserved. Explicit author bold (`**bold**`) remains Base1 Bold (`#93A1A1`). |
| ✅ **ALWAYS** | **Modular Stage Architecture** | Keep `setup.sh` strictly as an orchestrator CLI (~240 lines). Subsystem provisioning belongs in dedicated scripts under `modules/<NN>-<name>.sh` using shared helpers in `lib/`. |
| ✅ **ALWAYS** | **LTS Preference for Mise Tools** | For all tools defined in `.mise.toml`, specify `lts` whenever supported by the tool's ecosystem (`java = "lts"`, `node = "lts"`). For tools without an official LTS channel (Go, Python, Maven, Terraform, Rust, Neovim), default to `latest` stable. |
| ✅ **ALWAYS** | **Modern Neovim via Mise** | Modern Neovim (0.11+ / 0.12+) is provisioned via `mise` (`neovim = "latest"`), avoiding obsolete distro packages (such as Ubuntu's default 0.9.5). |
| ✅ **ALWAYS** | **XDG Base Directory Compliance** | Keep `$HOME` clean of language runtime workspaces and cache clutter. Go workspace and cache must strictly point to XDG paths: `export GOPATH="${XDG_DATA_HOME:-$HOME/.local/share}/go"` and `export GOCACHE="${XDG_CACHE_HOME:-$HOME/.cache}/go-build"`. |
| ✅ **ALWAYS** | **Idempotent & Fail-Fast Scripts** | All Bash scripts must begin with `set -euo pipefail`. Re-running `setup.sh` or `Makefile` targets must be completely safe, non-destructive, and produce identical results. |

---

## 2. Component Matrix & Associated Test Suites

| Component | Repository Source | Target System Location | Associated Test File |
| :--- | :--- | :--- | :--- |
| **Modular Orchestrator & CLI** | `setup.sh` | Orchestrator (Local & `curl \| bash`) | `tests/test-system-setup.sh` |
| **Shared Libraries** | `lib/*.sh` (`log.sh`, `os.sh`, `symlink.sh`) | Internal helper runtime | `tests/test-system-setup.sh`, `tests/test-dotfiles.sh` |
| **Stage Modules** | `modules/*.sh` (`00` through `99`) | Stage runners invoked by `setup.sh` | `tests/test-system-setup.sh`, `tests/test-dotfiles.sh`, `tests/test-bin.sh` |
| **Declarative Dotfiles Mirror** | `dotfiles/` (auto-discovered) | `$HOME/` and `${XDG_CONFIG_HOME:-$HOME/.config}/` | `tests/test-dotfiles.sh` |
| **Environment Variables** | `dotfiles/.environment-variables` | `$HOME/.environment-variables` | `tests/test-env.sh`, `tests/test-dotfiles.sh` |
| **Zsh Addendum & Hooks** | `dotfiles/.zshrc-addendum` | `$HOME/.zshrc-addendum` | `tests/test-zsh.zsh` |
| **Bash Addendum & Hooks** | `dotfiles/.bashrc-addendum` | `$HOME/.bashrc-addendum` | `tests/test-env.sh` |
| **Shortcuts & Aliases** | `dotfiles/.aliases` | `$HOME/.aliases` (and `$HOME/.zsh-aliases`) | `tests/test-zsh.zsh`, `tests/test-dotfiles.sh` |
| **Shell Functions** | `dotfiles/.zsh-functions` | `$HOME/.zsh-functions` | `tests/test-zsh.zsh`, `tests/test-dotfiles.sh` |
| **CLI Completions** | `dotfiles/.zsh-completions` | `$HOME/.zsh-completions` | `tests/test-completions.sh` |
| **Powerlevel10k Theme** | `dotfiles/.p10k.zsh` | `$HOME/.p10k.zsh` | `tests/test-zsh.zsh` |
| **Neovim Configuration** | `dotfiles/.config/nvim/init.lua` | `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua` | `tests/test-vim.sh`, `tests/test-dotfiles.sh` |
| **Ghostty Terminal Config** | `dotfiles/.config/ghostty/config` | `${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config` | `tests/test-dotfiles.sh` |
| **Legacy Vim Config** | `dotfiles/.vimrc` | `$HOME/.vimrc` | `tests/test-vim.sh` |
| **Bat TrueColor Theme** | `colors/Solarized-Dark-TrueColor.tmTheme` | `${XDG_CONFIG_HOME:-$HOME/.config}/bat/themes/` | `tests/test-env.sh`, `tests/test-dotfiles.sh` |
| **Bat Syntax Packages** | `syntaxes/*.sublime-syntax` (C, C++, Diff, Go, Java, Python, Rust, Bash, SQL, Terraform, Markdown) | `${XDG_CONFIG_HOME:-$HOME/.config}/bat/syntaxes/` | `tests/test-dotfiles.sh` |
| **Tree-sitter Query Overrides** | `dotfiles/.config/nvim/after/queries/<lang>/highlights.scm` | `${XDG_CONFIG_HOME:-$HOME/.config}/nvim/after/queries/` | `tests/test-vim.sh`, `tests/test-dotfiles.sh` |
| **GNOME Terminal Profile** | `colors/gnome-terminal-solarized.dconf` | dconf `/org/gnome/terminal/legacy/profiles:/` | `tests/test-bin.sh`, `tests/test-system-setup.sh` |
| **macOS Terminal Profile** | `colors/Solarized-Dark.terminal` | `~/Library/Preferences/com.apple.Terminal.plist` | `tests/test-bin.sh`, `tests/test-system-setup.sh` |
| **Dircolors Database** | `dotfiles/.dir-colors/dircolors` | `$HOME/.dir-colors/dircolors` | `tests/test-env.sh`, `tests/test-dotfiles.sh` |
| **Standalone Binaries** | `bin/*` | `${XDG_DATA_HOME:-$HOME/.local}/bin/` | `tests/test-bin.sh`, `tests/test-system-setup.sh` |
| **Polyglot Toolchains** | `.mise.toml` | `${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml` | `tests/test-system-setup.sh` |
| **Meslo Nerd Fonts** | Downloaded dynamically | `${XDG_DATA_HOME:-$HOME/.local/share}/fonts/` or macOS Fonts | `tests/test-fonts.sh` |
| **Shared Test Harness** | `tests/test-helper.sh` | Internal test assertion library | All `tests/*.sh` and `tests/*.zsh` |

---

## 3. Visual Precision & Solarized Dark TrueColor Palette

All UI components across terminal, prompt, file viewers, and editor must strictly adhere to the authentic **Ethan Schoonover Solarized Dark** specification in 24-bit TrueColor (`COLORTERM=truecolor`):

| Role | Color Name | Hex Code | Purpose / Usage |
| :--- | :--- | :--- | :--- |
| **Base Background** | `base03` | `#002B36` | Terminal background, Neovim background, bat background |
| **Current Line / Alt Bg** | `base02` | `#073642` | CursorLine, selection background, line highlight |
| **Comments / Dim Borders** | `base01` | `#586E75` | Code comments (upright), eza tree connectors (`xx=38;5;10`), bat borders, Markdown heading/quote/table delimiters, unchecked task boxes |
| **Subtle Text** | `base00` | `#657B83` | Secondary text, status indicators |
| **Standard Foreground & Custom Types** | `base0` | `#839496` | Standard typed text, CLI arguments, paths, struct fields, custom domain types (`OrderRecord`, `Context`, `HashMap`), schema relations (tables/views/CTEs), identifiers, function invocations (`printf()`, `.stream()`), Markdown H5/H6, blockquote body text |
| **Subtle Highlight & Bold** | `base1` | `#93A1A1` | Markdown Bold, Markdown H4 (retired from syntax types for ergonomic canvas tranquility) |
| **Control Flow & Jumps** | `yellow` | `#B58900` | Uncontested execution pathways: `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, CursorLineNr (never used in Markdown headings) |
| **Scaffolding & Primitive Types** | `green` | `#859900` | Structural scaffolding, static primitive types & core built-ins: `int`, `double`, `u64`, `usize`, `bool`, `void`, Python built-in types (`int`, `str`, `float`, `bool`, `list`, `dict`, `set`, `tuple`), `package`, `func`, `fn`, `def`, `class`, `struct`, `interface`, `type`, `var`, `let`, `const`, `CREATE TABLE`, SQL data types (`VARCHAR`, `BIGINT`) |
| **Routine Declarations** | `blue` | `#268BD2` | Function/method declarations (`func New...`, `fn find...`, `def __init__`), diff hunk headers (`@@ ... @@`), Markdown H2 |
| **Aspects & Modules** | `violet` | `#6C71C4` | Decorators (`@dataclass`), annotations (`@Service`), attributes (`#[derive]`, `[[nodiscard]]`), `import`, `package main`, Markdown H3 |
| **Strings & Paths** | `cyan` | `#2AA198` | String literals, file paths, raw backtick struct tags |
| **Numbers, Constants & Sentinels** | `magenta` | `#D33682` | Numeric literals, `nil`, `null`, `None`, `true`, `false`, `iota`, `ALL_CAPS` constants, sentinels, `this`, `self` |
| **Directives & Preprocessor**| `orange` | `#CB4B16` | Preprocessor macros (`#include`, `#define`), interpreter shebang (`#!/bin/bash`), Markdown H1 |
| **Errors & Diagnostics** | `red` | `#DC322F` | Syntax errors, diagnostic warnings, diff deletions |

### Universal Semantic Color Contract
Colors across our developer workstation fulfill invariant domain roles across all languages and filetypes:

| Palette Color | Hex Code | Universal Semantic Role | Manifestations Across Languages & Tools |
| :--- | :--- | :--- | :--- |
| **Solarized Yellow**| `#B58900` | Uncontested control flow & jumps | `if`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `throw`, `yield`, `await`, `CASE/WHEN` (exclusive to control flow, never in Markdown headings) |
| **Solarized Green** | `#859900` | Structural scaffolding, declarations, static primitive types & core built-ins, diff additions | `int`, `double`, `u64`, `usize`, `bool`, `void`, Python built-in types (`int`, `str`, `float`, `bool`, `list`, `dict`, `set`, `tuple`), `package`, `func`, `fn`, `def`, `class`, `struct`, `interface`, `var`, `let`, `const`, `typedef`, `CREATE TABLE`, `DEFAULT`, `ASC`, `DESC`, SQL data types (`VARCHAR`, `BIGINT`), `+` added lines, task checked `[x]` |
| **Base0 Grey**      | `#839496` | Neutral ground, custom domain types, schemas, invocations, operators | Custom domain types (`OrderRecord`, `Context`, `HashMap`, `Instant`), schema relations (tables/views/CTEs), dynamic types/classes (Python `Callable`, `Union`, `EndpointMetrics`, `MetricsCollector`), built-in exceptions (`ValueError`), function/method calls (`printf()`, `.stream()`), operators (`+`, `==`), qualifiers (`context.`, `std::`), fields, parameters, expansion sigils (`$`, `${`, `}`), Markdown H5/H6, blockquote body |
| **Solarized Blue**  | `#268BD2` | Routine declarations & structural headers | `func New...`, `fn find...`, `def __init__`, `diffLine`, `@@ ... @@` hunk headers, Markdown H2, GitHub alert `[!NOTE]` |
| **Solarized Violet**| `#6C71C4` | Aspects, annotations, attributes, modules & imports | `@Service`, `@dataclass`, `#[derive]`, `[[nodiscard]]`, `import`, `from`, `use`, `package main`, `@module`, Markdown H3, GitHub alert `[!IMPORTANT]` |
| **Solarized Magenta**| `#D33682`| Constants, literals, hashes, sentinels, receivers | `1024`, `nil`, `null`, `None`, `true`, `false`, `LevelDebug`, `MAX_CONNECTIONS`, `4b825dc`, `this`, `self` |
| **Solarized Cyan**  | `#2AA198` | Strings, filesystem paths, struct tags, format placeholders | `"Hello %s\n"`, `a/src/...`, markdown link URLs, backtick struct tags, format specifiers (`%s`, `:.4f`, `%d`) |
| **Solarized Orange**| `#CB4B16` | Directives, preprocessor macros, shebang | `#define`, `#include`, `#!/bin/bash`, Markdown `#` H1, GitHub alert `[!WARNING]` |
| **Base01 Dim**      | `#586E75` | Comments, subtle metadata, structural delimiters | `// upright comments`, bat borders, tree connectors, autosuggestions, Markdown `#` heading markers, quote `>` markers, table `\|` borders, task unchecked `[ ]` |

### The Seven Higher-Order Architectural Pillars

1. **Pillar I: The 3-Tier Semantic Color Contract & Canvas Tranquility**
   - *Core Premise*: Highlighting is not visual decoration; it is an ergonomic aid engineered to minimize cognitive load and saccadic fatigue during code reading, navigation, and review. Every palette color fulfills an invariant mental category across all programming languages, configuration syntaxes, and markup documents:
     - **Tier 1: Monotone Ground (70–80% screen area) — Solarized Base0 (`#839496`) & Base01 (`#586E75`)**: Standard text, variable identifiers, parameters, struct/field members, custom domain types/classes (`OrderRecord`, `Context`, `HashMap`, `Instant`, `ClusterNode`, `WorkerNode`, Java/Rust `String`), generic type parameters (`T`), dynamically typed classes/typing constructs (Python `Callable`, `Union`, `EndpointMetrics`), built-in exceptions (`ValueError`), schema relations (SQL tables, CTEs, views, indexes), Terraform schema blocks, routine and method invocations (`printf()`, `.stream()`, `node.Greet()`, `contains()`), symbolic operators (`+`, `-`, `*`, `/`, `=`, `==`, `<`, `>`, `?`, `:`), structural delimiters/brackets (`()`, `{}`, `[]`), upright code comments, and scope qualifiers (`context.`, `fmt.`, `std::`, `boost::`). Anchoring domain entities and routine call sites to the neutral canvas achieves optimal canvas tranquility ("Alabaster" effect) and eliminates the exhausting blue/grey zebra-striping of routine calls.
     - **Tier 2: Structural Anchors (15–20% screen area) — Green, Yellow, Blue, Violet**: Frames structural topology:
       - **Solarized Green (`#859900`)**: Structural scaffolding and declarations (`package`, `func`, `fn`, `def`, `class`, `struct`, `interface`, `var`, `let`, `const`, `typedef`, `CREATE TABLE`, `DEFAULT`, `ASC`, `DESC`), reserved word operators (`sizeof`, `alignof`, `_Alignof`, `static_assert`, `_Generic`), and static primitive types / core built-in scalars (`int`, `double`, `u64`, `usize`, `bool`, `void`, SQL `VARCHAR`/`BIGINT`, Python built-in scalars `int`, `str`, `float`, `bool`, `bytes`, `list`, `dict`, `set`, `tuple`, `object`, `range`). Leveraging the human visual cortex's primary sensitivity to green hue provides effortless structural scanning without the "Primitive Fracture" or "Type Paradox" of conventional themes.
       - **Solarized Yellow (`#B58900`)**: Uncontested control flow and jumps (`if`, `else`, `return`, `for`, `while`, `switch`, `case`, `select`, `defer`, `match`, `try`, `catch`, `throw`, `yield`, `await`, `CASE/WHEN`). Reserving Yellow exclusively for execution pathways ensures branch points and jump exits command instantaneous peripheral attention, completely uncontested by types, keywords, or document headings.
       - **Solarized Blue (`#268BD2`)**: Routine and function declarations (`func New...`, `fn find...`, `def __init__`, `cleanup() {`), diff hunk headers (`@@ ... @@`), and Markdown H2 section boundaries.
       - **Solarized Violet (`#6C71C4`)**: Serene aspect layer, declarative metadata, annotations, decorators, attributes, imports, and modules (`@Service`, `@dataclass`, `#[derive]`, `[[nodiscard]]`, `import`, `from`, `use`, `package main`, `@module`, Markdown H3). Transforms stacked annotations into a quiet, elegant boundary that recedes behind the foreground code plane.
     - **Tier 3: Values & Directives (5–10% screen area) — Cyan, Magenta, Orange**: Data values and compiler meta-instructions:
       - **Solarized Cyan (`#2AA198`)**: String literals, filesystem paths, unbroken escape sequences and format specifiers (`%s`, `\n`), raw backtick struct tags, and Markdown link targets.
       - **Solarized Magenta (`#D33682`)**: Numeric literals, booleans (`true`, `false`), named `ALL_CAPS` and `iota` constants (`EXIT_FAILURE`, `MAX_BUFFER_SIZE`, `LevelDebug`), and sentinel values (`nil`, `null`, `None`, `std::nullopt`, `_`, `this`, `self`).
       - **Solarized Orange (`#CB4B16`)**: Compiler directives, preprocessor macros (`#define`, `#include`), interpreter shebangs (`#!/bin/bash`), and Markdown H1 titles.
   - *Markdown Semantic Architecture*: Engineering documentation heavily embeds polyglot code blocks (Rust, Python, Go, Java, Bash). Allocating Yellow to Markdown headings catastrophically collides with embedded code control flow (`if err != nil`). Markdown strictly implements a non-colliding semantic hierarchy: H1 Orange (`#CB4B16`), H2 Blue (`#268BD2`), H3 Violet (`#6C71C4`), H4 Base1 (`#93A1A1`), H5/H6 Base0 (`#839496`), with `#` delimiter sigils quietly anchored in Base01 (`#586E75`). Blockquote markers (`>`) sit in Base01 with body in calm Base0; GitHub alert callouts follow functional accents (`[!NOTE]` Blue, `[!TIP]` Green, `[!IMPORTANT]` Violet, `[!WARNING]` Orange, `[!CAUTION]` Red); task checkboxes reflect state (`[x]` Green, `[ ]` Base01); table borders (`|`) sit in Base01, headers in Base1, and data cells in Base0. Fenced code blocks preserve 1:1 nested polyglot syntax isolation with zero scope bleeding.
   - *Pure Monospace Typography*: Zero-jitter invariance. Bold weight and italics are strictly stripped from code tokens (`bold = false`, `italic = false`) to eliminate font metric mismatches, horizontal jitter, and terminal ANSI color remapping. Styling is reserved exclusively for explicit author markup (Markdown `*italic*` and `**bold**`).

2. **Pillar II: Operational Role Invariance (Runtime Semantics over Static Syntax)**
   - *Core Premise*: Highlighting must reflect the runtime operational role of a token rather than its static lexical spelling or compiler internal representation:
     - **Definition vs. Invocation Decoupling**: Function declarations (`func Process()`) are structural landmarks in Blue (`#268BD2`); function and method invocations (`node.Process()`) are runtime operations resting on the calm Base0 Grey (`#839496`) canvas.
     - **Factory Invariance (No Semantic Flipping)**: In languages where constructors are ordinary functions (such as Go `NewClusterNode` or factory patterns), constructors remain invocations in calm Base0 Grey (`#839496`), preserving visual continuity across all call sites rather than falsely masquerading in Yellow as language-level primitive constructors.
     - **Built-in Routine Invariance**: Standard library and compiler built-in routines (`panic(...)`, `make(...)`, `len(...)`, `printf(...)`) function identically to user routines at the call site and sit calmly on Base0 Grey.
     - **Dual-Identity Contextual Disambiguation**: In Java, C++, and Python, receiver keywords fulfill dual functions based on syntax context: when acting as an instance reference or receiver (`this.timeoutMs`, `self.val`, `super.init()`), they represent immutable instance constants in Solarized Magenta (`#D33682`); when acting as explicit constructor delegations (`this(...)`, `super(...)`), they act as callable routine invocations in calm Base0 Grey (`#839496`).
     - **Sentinels vs. Types in Tri-State Logic**: In SQL and systems programming, sentinel literals (`NULL`, `None`, `nil`, `_`, `std::nullopt`) represent missing states or wildcards and are classified strictly as constants in Solarized Magenta (`#D33682`), decoupling them from structural types and keywords.
     - **Positional Contextuality of Meta-Arguments**: Declarative identifiers fulfilling dual roles (such as Terraform `provider "aws" {` vs `provider = aws.west`) are disambiguated positionally: block headers join Green declarations, while assignment targets fall through to Base0 attributes.

3. **Pillar III: Gestalt Semantic Continuity & Atomic Compound Enclosure**
   - *Core Premise*: The human visual cortex parses code in Gestalt units (laws of continuity, proximity, and closure). Syntax engines that mechanically fracture unified semantic constructs into contrasting checkerboards induce disruptive saccadic interrupts:
     - **String Payload & Format Cohesion**: String literals, interpolation wrappers, escape sequences (`\n`, `\t`), and format placeholders (`%s`, `:.4f`, `%d`) form a single continuous string entity, unified in Solarized Cyan (`#2AA198`). Format delimiter punctuation (`:`) remains calm Base0, while specification payloads maintain string cohesion in Cyan.
     - **Atomic Compound Enclosures**: Enclosure sigils and their enclosed identifiers form inseparable cognitive units. Brackets, hashes, and directive names in Rust attributes (`#[derive(...)]`, `#![no_std]`), C++ attributes (`[[nodiscard]]`), Python decorators (`@dataclass`), and Java annotations (`@Override`) are unified in Solarized Violet (`#6C71C4`). Rust lifetime ticks and identifiers (`'a`, `'static`) are unified in Solarized Green (`#859900`). Go backtick struct tags (``` `json:"port"` ```) are unified in Solarized Cyan (`#2AA198`).
     - **Diff Line Continuity**: The diff indicator sigil (`+` or `-`) and the entire line body form a single semantic mutation, unified in continuous Solarized Green (`#859900`) or Solarized Red (`#DC322F`).

4. **Pillar IV: Navigational Neutrality (Qualifiers, Sigils, and Scope Boundaries)**
   - *Core Premise*: Routing metadata, scoping prefixes, and expansion sigils serve as navigational plumbing rather than semantic payloads. Coloring them in high-chroma accents causes visual friction:
     - **Scope Qualifiers**: In-code namespace and package qualifiers (`std::`, `boost::`, `context.`, `fmt.`) serve navigational routing. Highlighting them in accent colors creates high-frequency vibration against adjacent types and routines. Qualifiers strictly remain in calm Base0 Grey (`#839496`), whereas formal architectural definition sites (`package main`, `namespace core::telemetry`) receive Solarized Violet (`#6C71C4`).
     - **Expansion Sigils & Punctuation**: Shell parameter expansion sigils (`$`, `${`, `}`), command substitutions (`$(...)`), and arithmetic substitutions (`$((...))`) are navigational syntax anchors and strictly remain in calm Base0 Grey (`#839496`), preserving visual prominence for the enclosed variable or constant payload.
     - **Declarative Scope Symmetry**: In infrastructure DSLs (such as HCL/Terraform), engine-provided scope root keywords (`var.`, `local.`, `terraform.`, `data.`, `module.`) maintain declarative symmetry with top-level block keywords in Solarized Green (`#859900`), while user-defined resource chains and member accessors remain in calm Base0 Grey (`#839496`).
     - **Interpolation Boundary Isolation**: Interpolation delimiters (`${`, `}`) and heredoc strip markers (`~`, `%{`) strictly remain Base0 punctuation across quoted strings and multi-line heredocs, preventing chromatic fusion with adjacent keywords and maintaining clean lexical boundaries.

5. **Pillar V: Pushdown Automata State Machine Engineering**
   - *Core Premise*: Regex-based pushdown automata (`bat` / Syntect / Sublime Text) operate without compiler symbol tables or AST graphs. Achieving 1:1 parity with AST engines requires robust state machine engineering:
     - **Non-Greedy Transition Eagerness**: Pushdown state transitions must match structural framing prefixes (e.g. Markdown list sigils `^\s*([-*+]|\d+\.)(?=\s)` or quote sigils `^\s*(>)`) and *never* greedily consume downstream content (`(.*)$`). Consuming downstream characters on transition starves child contexts, skipping inline formatting, code spans, and links.
     - **Opening Delimiter Consumption vs. Lookahead Trap**: Context push rules must consume their opening delimiters (`match: '({{ident}})\s*(\()'` with capture 2 scoped to punctuation) rather than using lookaheads (`(?=\()`). Non-consuming lookaheads leave delimiters in the buffer to be consumed by inner rules, breaking pop condition symmetry and permanently trapping the parser in corrupted child states.
     - **Positional & Boundary Anchoring**: In indentation-sensitive or statement-delimiter-free syntaxes (Python, YAML, Markdown), rules must enforce line-initial anchors (`^\s*`) and negative lookaheads (`(?!\s*[=:])`) to prevent statement block headers (`try:`, `finally:`) from poisoning expression contexts.
     - **Composite Operator Deconstruction**: Glued operator-operand constructs (`>&2`, `2>&1`, `*ptr`) must be deconstructed at lexing time so operators remain Base0 Grey while numeric file descriptors retain Solarized Magenta (`#D33682`).
     - **Statement Arm Isolation**: Context-dependent statement blocks (such as shell `case ... in ... esac` arms) require dedicated pushdown contexts (`case-body`) to prevent line-initial pattern labels from being misparsed as command invocations in Blue.
     - **Contextual Polysemy Disambiguation**: Multi-purpose punctuation symbols (`*`, `@`, `#`) must be disambiguated by structural containment: SQL `*` in projection (`SELECT *`) vs binary arithmetic (`a * b` in Base0); shell `@` in parameter expansions (`$@` in Magenta) vs array subscripts (`${arr[@]}` in Cyan).
     - **Punctuation-Safe Word Tokenization**: Plain-text fallback rules must segregate non-space runs into word runs (`[^\s`*!_\[\]~()]+`), punctuation clusters, and fallback characters, preventing punctuation enclosures (`(**Debian/Ubuntu**,`) from swallowing adjacent markup delimiters.
     - **Multi-State Grammar Sequencing for Tabular Topology**: Pushdown automata must model tabular layouts as a multi-stage topological state machine (`table` $\to$ `table-after-header` $\to$ `table-body`) to distinguish Base1 headers from Base0 data cells.

6. **Pillar VI: Tree-sitter AST Query Hierarchy & Cascade Engineering**
   - *Core Premise*: Neovim's Tree-sitter architecture evaluates declarative S-expression pattern queries over concrete syntax trees. Robust query design prevents AST shadowing and ensures seamless polyglot injection:
     - **Root Fallback Invariance (The Cascade Principle)**: Root query capture groups (`@function.call = Base0`, `@function.builtin = Base0`, `@keyword.import = Violet`, `@variable.builtin = Magenta`) must strictly mirror the universal semantic contract. Contradictions in root highlights corrupt every embedded polyglot block and newly installed grammar. Aligning root captures enables hundreds of lines of repetitive per-language overrides to be pruned.
     - **Leaf-Node Dominance & Priority Predicates**: Parent container captures do not override child leaf nodes without explicit leaf captures or priority weighting (`#set! priority 120`). In compound AST nodes (such as Markdown alert callouts `[!NOTE]`), leaf tokens (`link_text`) must be targeted directly to guarantee visual dominance over generic parent bounds.
     - **Query Stream Ordering**: In Tree-sitter query streams, broader generic captures occurring later silently supersede earlier specific captures unless guarded by priority assertions. Specialized domain rules (such as dunder attributes `__name__` or qualified receivers) must be defended with explicit precedence.
     - **Polyglot Code Block Injection Isolation**: Markdown code block injections dynamically invoke the target language's Tree-sitter parser, executing the full syntax contract of the embedded language with strict scope boundaries.

7. **Pillar VII: Standalone Subsystem Independence & LTS Currency**
   - *Core Premise*: Workstation developer environments must be completely decoupled from distro packaging lag and upstream dependency rot:
     - **Standalone Grammar Independence (Zero Dependency Traps)**: Grammars in `syntaxes/` must be 100% self-contained, declaring all contexts locally without external TextMate includes (`Packages/Git Formats/...` or `source.go.embedded...`). Missing external dependencies trigger silent fallback cascades to obsolete regex packages that poison modern themes (e.g. turning SQL column names Magenta).
     - **LTS Currency Imperative**: Operating system distributions and upstream grammars lag language evolution by 5–10 years (e.g. missing Java 16+ records, Java 21+ pattern matching, Java 23+ Markdown comments, Java 25+ flexible constructor bodies, C++20/23, Go 1.22+, Rust 2021/2024). This repository provisions actively supported LTS runtimes via `mise` and decouples syntax highlighting through maintained, version-controlled grammars in `syntaxes/` and query overrides in `after/queries/`.
     - **Canonical Semantic Mapping Across Heterogeneous Engines**: `bat` (regex pushdown automaton) and Neovim (Tree-sitter GLR parser / LSP) employ fundamentally different parsing paradigms. Complete visual parity is achieved through canonical mapping: structural conventions and regex lookaheads in `bat` mirror AST node constraints and query predicates in Neovim, producing 1:1 identical TrueColor rendering across both tools.

---

### Integration Rules & Tooling Implementations

1. **`bat` (Syntect CLI File Viewer)**:
   - Compiled theme cache via `bat cache --build` using `colors/Solarized-Dark-TrueColor.tmTheme`.
   - Standalone modern Sublime grammars in `syntaxes/` (`C`, `C++`, `Diff`, `Go`, `Java`, `Python`, `Rust`, `Bash`, `SQL`, `Terraform`, `Markdown`).
   - Routine declarations in Blue (`#268BD2`), invocations in Base0 (`#839496`), control flow exclusively in Yellow (`#B58900`), declarations and scalar primitives/data types in Green (`#859900`), custom types and schemas in Base0 (`#839496`), annotations/decorators/attributes/imports in Violet (`#6C71C4`), preprocessor directives in Orange (`#CB4B16`), constants/sentinels/literals in Magenta (`#D33682`), diff additions in Green, deletions in Red, and hunk ranges in Blue.
   - Available via `bat` or `b`; standard Unix `cat` strictly remains coreutils.

2. **Neovim (Native LSP & Tree-sitter Editor)**:
   - Uses `maxmx03/solarized.nvim` with `variant = "spring"` matching `bat` 1:1.
   - Integrated with Native Neovim 0.11+ LSP (`vim.lsp.config`, `LspAttach`) and Tree-sitter query overrides in `after/queries/` (`c`, `cpp`, `diff`, `go`, `java`, `python`, `rust`, `bash`, `sql`, `terraform`, `markdown`, `markdown_inline`).
   - Structural declarations and scalar primitives in Green, control flow exclusively in Yellow, custom types and schema relations in calm Base0, function declarations in Blue, function calls in Base0, annotations/decorators/attributes/imports in Violet, sentinels/constants/booleans in Magenta, preprocessor directives in Orange, and Base0 delimiters/table boundaries matching `bat` 1:1.

3. **`eza` (Modern Directory Listing)**:
   - Configured via aliases `e`, `el`, `elm`, `et`, `elt`, and `elx` with `EZA_COLORS` and `EXA_COLORS` adhering strictly to Solarized Dark: unbolded layout, tree connectors in Base01 (`xx=38;2;88;110;117`), directories in Blue (`di=38;2;38;139;210`), executables in Green (`ex=38;2;133;153;0`), regular files, code and documents in calm Base0 (`fi`, `sc`, `do` in `38;2;131;148;150`), media in Violet (`im`, `vi`, `mu`, `lo` in `38;2;108;113;196`), archives in Orange (`cr=38;2;203;75;22`), symlinks in Cyan (`ln=38;2;42;161;152`), broken links in Red (`or=38;2;220;50;47`), and unbolded table headers in Base1 (`hd=4;38;2;147;161;161`).

4. **GNU/BSD `ls` & `dircolors` (Solarized Dark `LS_COLORS`)**:
   - Configured via `dotfiles/.dir-colors/dircolors` evaluated into `LS_COLORS`. Pure monospace, zero-jitter, unbolded file classification: directories in Blue (`DIR 34`), executables in Green (`EXEC 32`), symlinks in Cyan (`LINK 36`), regular text files, source code, and documents in calm Base0 (`FILE 00`, `.c 00`, `.py 00`, `.md 00`, `.txt 00`, `.pdf 00`), media in Violet (`35`), archives in Orange (`33`), broken symlinks in Red (`ORPHAN 31`, `MISSING 31`), and backup files in Base01 (`90`).

5. **Zsh Shell & Autosuggestions (`zsh-syntax-highlighting` / `ZLE`)**:
   - Autosuggestions pinned to `fg=#586E75` (Solarized Base01).
   - `zsh-syntax-highlighting` configured in `.zshrc-addendum` using 24-bit TrueColor Solarized Dark with restrained, zero-jitter, unbolded syntax highlighting: valid command invocations, builtins, aliases, and functions in Green (`#859900`), control flow reserved words exclusively in Yellow (`#B58900`), strings in Cyan (`#2AA198`), numbers and arithmetic in Magenta (`#D33682`), precommands/paths in Blue (`#268BD2`), errors in Red (`#DC322F`), comments in Base01 (`#586E75`), selection in Base02 (`#073642`), with command substitution delimiters `$( ... )`, options, parameters, assignments, and operators kept calm in neutral foreground Base0 (`#839496`).

6. **Powerlevel10k Solarized Dark Prompt (`.p10k.zsh`)**:
   - Single-line Powerlevel10k prompt configured in `dotfiles/.p10k.zsh` with Ethan Schoonover's authentic palette: OS icon anchored to authentic Solarized Dark Base1 (`#93A1A1`) background with Base03 (`#002B36`) foreground for calm, distinct badge contrast without off-palette light-mode bleed, directory anchor bold disabled (`POWERLEVEL9K_DIR_ANCHOR_BOLD=false`) for zero-jitter typography, untracked git status reclassified to Yellow (`#B58900`) for clear dirty-state awareness, ornaments/frame connectors in Base01 (`%F{#586E75}`), and `prompt_char` omitted in favor of the clean, uncluttered `╰─ ` multiline input connector (Pillar IV: Navigational Neutrality).

7. **Terminal Emulators (GNOME Terminal, macOS Terminal, Ghostty)**:
   - GNOME Terminal configured via `colors/gnome-terminal-solarized.dconf` and `bin/gnome-terminal-solarized` with authentic TrueColor Solarized Dark, Color 8 pinned to `base01` (`#586E75`), MesloLGS NF 12 font, and Base02 highlight.
   - Ghostty configured via `.config/ghostty/config` with `theme = "Solarized Dark"`, palette overrides, and MesloLGS NF font.
   - macOS Terminal configured via `colors/Solarized-Dark.terminal`.

---

## 4. Step-by-Step Task Recipes for Agents

### Recipe A: Adding or Updating a Developer Toolchain
1. Edit `.mise.toml` to declare the tool:
   - Use `"lts"` if the tool ecosystem supports LTS releases (e.g. `java = "lts"`, `node = "lts"`).
   - Use `"latest"` for all other stable tools (e.g. `go = "latest"`, `python = "latest"`, `neovim = "latest"`).
2. If client CLI utilities are needed from distro package managers, add them to `modules/00-packages.sh`.
3. Update `.mise.toml` validation in `tests/test-system-setup.sh`.
4. Run `make test` and `make lint` to verify.

### Recipe B: Adding a Setup CLI Switch / Option
1. Update `setup.sh` argument parser (`while [ $# -gt 0 ]; do ... done`).
2. Implement `--dry-run` and live behavior within the relevant `modules/<NN>-*.sh` script.
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

### Recipe E: Adding a New Managed Dotfile
1. Drop the file or directory directly into `dotfiles/` (e.g. `dotfiles/.gitconfig`, `dotfiles/.tmux.conf`).
2. Dotfiles are automatically discovered and mirrored to `$HOME` by `modules/10-dotfiles.sh` and cleaned up by `modules/99-uninstall.sh`.
3. Add assertion to `tests/test-dotfiles.sh`.
4. Run `make test` and `make lint`.

### Recipe F: Adding a Standalone CLI Utility
1. Drop the executable script into `bin/` (e.g. `bin/my-util`).
2. Make it executable (`chmod +x bin/my-util`) and start with `#!/bin/bash` + `set -euo pipefail`.
3. It is automatically symlinked to `~/.local/bin/my-util` by `modules/20-bin.sh` and cleaned up by `modules/99-uninstall.sh`.
4. Add unit test to `tests/test-bin.sh`.
5. Run `make test` and `make lint`.

### Recipe G: Adding a New Provisioning Module
1. Create `modules/<NN>-<feature>.sh` (numbered between 00 and 99 by execution order).
2. Include standard shebang, `set -euo pipefail`, and source `lib/log.sh`, `lib/os.sh`, `lib/symlink.sh`.
3. Respect standard environment flags: `DRY_RUN`, `OS`, `ARCH`.
4. Wire the module into `setup.sh`.
5. Add test coverage and verify with `make test` and `make lint`.

---

## 5. Anti-Patterns & Common Traps (What NOT to Do)

| Anti-Pattern | Why It Breaks | Correct Implementation |
| :--- | :--- | :--- |
| **Masking Startup Warnings (`2>/dev/null`)** | Hides real syntax/configuration errors from the user. | Fix the root cause (trust configs via `mise trust`, install missing runtimes via `mise install`). |
| **Hardcoding Dotfile Lists in Scripts** | Requires editing bash arrays whenever dotfiles change. | Drop dotfiles in `dotfiles/`; let `modules/10-dotfiles.sh` auto-discover and mirror. |
| **Inlining Module Logic into `setup.sh`** | Re-creates a bloated, unmaintainable monolithic script. | Keep `setup.sh` strictly as an orchestrator CLI; place logic into `modules/<NN>-<name>.sh`. |
| **Blind `ln -sfn` Over Existing Directory** | Creates a nested symlink (`~/.config/nvim/nvim -> ...`) instead of replacing the directory. | Use `lib/symlink.sh` (`link_dir` / `link_file`) which backs up physical directories to `.bak.<timestamp>`. |
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
   Ensures `shellcheck` and shell syntax checks (`bash -n`, `zsh -n`) pass with 0 warnings across all scripts.

2. **Run Full Test Suite**:
   ```bash
   make test
   ```
   Ensures all 160+ validation tests across all 8 test modules pass with 0 failures:
   - `test-system-setup.sh`: Cross-platform CLI, dry-run, OS dispatching, Mise definitions, bootstrapper.
   - `test-dotfiles.sh`: Declarative dotfiles auto-discovery, physical directory backup, drop-ins, uninstallation.
   - `test-bin.sh`: User binaries symlinking, compatibility shims (fd, bat), uninstallation.
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
