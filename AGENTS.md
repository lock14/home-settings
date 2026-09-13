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
| 🚫 **NEVER** | **No Semantic Flipping for Factory Functions** | Never color factory function calls (`NewClusterNode`, `NewService`) in Yellow as constructors. In languages like Go where constructors are standard functions, function invocations strictly remain in Solarized Blue (`#268BD2`) across both definition and call sites. |
| 🚫 **NEVER** | **No Token Fracturing in Structured Strings or Attributes** | Never fracture compound constructs like Go struct tags (``` `json:"port"` ```), C++ attributes (`[[nodiscard]]`), Rust attributes (`#[derive]`, `#[inline]`), printf format specifiers (`%s\n`), diff lines (`+ line`), or Rust lifetimes (`'a`, `'static`) into multi-colored checkerboards. They must remain unified in their primary accent. |
| 🚫 **NEVER** | **No Piped Multi-Kilobyte Variables to Early-Terminating Consumers** | Under `set -euo pipefail`, piping multi-kilobyte strings into early-terminating consumers (e.g. `echo "$OUT" \| grep -q`) triggers `SIGPIPE` (exit 141) on the producer. Always use Bash here-strings (`grep -Fq "$pattern" <<< "$OUT"`) or temporary files to ensure 100% deterministic test execution. |
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
| **Bat Syntax Packages** | `syntaxes/*.sublime-syntax` (C, C++, Diff, Go, Java, Python, Rust, Bash, SQL) | `${XDG_CONFIG_HOME:-$HOME/.config}/bat/syntaxes/` | `tests/test-dotfiles.sh` |
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
| **Comments / Dim Borders** | `base01` | `#586E75` | Code comments (upright), eza tree connectors (`xx=38;5;10`), bat borders |
| **Subtle Text** | `base00` | `#657B83` | Secondary text, status indicators |
| **Standard Foreground** | `base0` | `#839496` | Standard typed text, CLI arguments, paths, struct fields, identifiers |
| **Emphasis Text** | `base1` | `#93A1A1` | Bright text, highlighted labels |
| **Keywords & Control** | `green` | `#859900` | `package`, `func`, `return`, `if`, `for`, `var`, `type`, `struct`, `interface` |
| **Types & Struct Names** | `yellow` | `#B58900` | Primitive types (`int`, `string`, `bool`), custom types, structs, classes, interfaces, `map`, `chan`, CursorLineNr |
| **Functions & Methods** | `blue` | `#268BD2` | Function declarations, method calls, directory names, Markdown blockquotes |
| **Namespaces & Modules** | `violet` | `#6C71C4` | Namespaces, modules, module declarations (`package main`, `namespace core::telemetry`), `@module` |
| **Strings & Paths** | `cyan` | `#2AA198` | String literals, file paths, raw backtick struct tags |
| **Numbers & Constants** | `magenta` | `#D33682` | Numeric literals, `nil`, `true`, `false`, `iota`, scoped constants, sentinels |
| **Inclusions & Directives**| `orange` | `#CB4B16` | External imports (`import`, `from`, `use`), preprocessor macros (`#include`, `#define`), attributes (`[[nodiscard]]`) |
| **Errors & Diagnostics** | `red` | `#DC322F` | Syntax errors, diagnostic warnings |

### Universal Semantic Color Contract
Colors across our developer workstation fulfill invariant domain roles across all languages and filetypes:

| Palette Color | Hex Code | Universal Semantic Role | Manifestations Across Languages & Tools |
| :--- | :--- | :--- | :--- |
| **Solarized Green** | `#859900` | Control, declarations, keywords, diff additions | `if`, `return`, `package`, `typedef`, `struct`, `sizeof`, `+` added lines, `diffAdded` |
| **Solarized Red** | `#DC322F` | Errors, deletions, invalid states | `invalid.illegal`, `-` deleted lines, `diffRemoved`, compiler diagnostics |
| **Solarized Blue** | `#268BD2` | Invocations, callable routines, structural headers | `printf()`, `std::move()`, `diffLine`, `@@ ... @@` hunk headers, blockquotes |
| **Solarized Yellow**| `#B58900` | Types, structs, concepts, type parameters | `int`, `uint8_t`, `WorkerNode`, `Printable`, `T`, `same_as`, `map`, `chan`, `CursorLineNr` |
| **Solarized Violet**| `#6C71C4` | Namespaces, modules, declarations | `package main`, `namespace core::telemetry`, `using namespace`, `@module` |
| **Solarized Magenta**| `#D33682`| Constants, literals, hashes, sentinels, built-in object references | `EXIT_FAILURE`, `4b825dc`, `100644`, `std::nullopt`, `true`, `42`, `LevelDebug`, `this`, `self` |
| **Solarized Cyan**  | `#2AA198` | Strings, filesystem paths, URIs | `"Hello %s\n"`, `a/src/...`, markdown link URLs, backtick struct tags |
| **Solarized Orange**| `#CB4B16` | Directives, preprocessor macros, attributes, imports | `#define`, `#include`, `import`, `from`, `use`, `[[nodiscard]]`, Markdown `#` H1 |
| **Base0 Grey**      | `#839496` | Neutral ground, operators, delimiters, context | `+`, `-`, `*`, `==`, `--git`, `activeNodes map[...]`, struct fields, parameters, Go dot qualifiers (`context.`, `fmt.`), C++ scope qualifiers (`std::`, `boost::`) |
| **Base01 Dim**      | `#586E75` | Comments, subtle metadata | `// upright comments`, bat borders, tree connectors, autosuggestions |

### High-Level Architectural Principles
1. **Lexical vs. AST Convergence (The Engine Translation Principle)**:
   - `bat` (Syntect / Sublime Text) operates as a regex-based pushdown automaton with scope stacks, devoid of symbol tables or semantic awareness. Neovim operates on concrete syntax trees (Tree-sitter GLR parser) and compiler semantic tokens (LSP). Trying to force one engine to imitate the other's internal representation leads to fragile hacks.
   - Parity is achieved through **canonical semantic mapping**: In `bat`, use structural conventions (`ALL_CAPS` constants, `PascalCase` types), negative lookaheads (`(?!\s*\()` to distinguish types from function invocations), and contextual scoping to approximate symbol tables. In Neovim, use Tree-sitter query predicates (`(#match? @type "^([A-Z]|.+_t$)")`, `(#any-of? @constant "nullopt" "npos")`, `(deletion "-" @diff.minus)`) to constrain ambiguous AST nodes to their true domain roles.
2. **Gestalt Semantic Continuity (No Artificial Token Fracturing)**:
   - Syntax engines mechanically chop code into lexical tokens. However, the human brain reads in Gestalt units (law of continuity and closure). Artificial accent switching across token boundaries causes saccadic interrupts:
     - *Strings & Formatting*: Format specifiers (`%s`, `%d`) and escape sequences (`\n`, `\t`) are integral to the string value. Breaking them into contrasting colors produces disruptive visual checkerboarding. Unified in **Solarized Cyan (`#2AA198`)**.
     - *Diff Lines*: The leading diff marker (`+` or `-`) and the line text form a single semantic addition or deletion. Unifying marker and line body into continuous **Solarized Green (`#859900`)** or **Solarized Red (`#DC322F`)** preserves Gestalt continuity.
     - *Attribute Enclosures*: In `[[nodiscard]]`, both the brackets `[[`, `]]` and the attribute identifier form one syntactic construct, unified in **Solarized Orange (`#CB4B16`)**.
     - *Struct Tags*: Backtick field tags in Go (``` `json:"port"` ```) are unified in **Solarized Cyan (`#2AA198`)** to avoid internal checkerboarding.
     - *Rust Lifetimes*: The lifetime tick (`'`) and lifetime identifier (`a`, `static`, `_`) form a single semantic borrow/modifier unit. Breaking them into contrasting colors produces disruptive visual checkerboarding. Unified in **Solarized Green (`#859900`)**.
3. **Domain-Specific Cognitive Roles**:
   - Highlighting is not decoration; it is an ergonomic aid designed to reduce cognitive load during comprehension and code review. Every color represents an invariant mental category: structural framing (Green/Yellow/Blue/Violet), data values (Cyan/Magenta), and compiler directives / inclusions (Orange), anchored on a calm monotone ground (Base0/Base01).
4. **Standalone Subsystem Independence (The Dependency Trap)**:
   - Upstream tools often attempt to embed external packages (e.g. `bat`'s built-in Diff syntax attempting to include `Packages/Git Formats/Git Diff.sublime-syntax` which is missing in standalone `bat`, or Go syntax attempting to include `source.go.embedded-backtick-string.css`). When a referenced grammar or configuration is absent, the engine fails silently, falling back to unstyled text or emitting cache build warnings.
   - All toolchain grammars, tree-sitter queries, and shell configurations in this repository must be **completely self-contained**. Distributing standalone grammars (`C.sublime-syntax`, `C++.sublime-syntax`, `Diff.sublime-syntax`, `Go.sublime-syntax`, `Java.sublime-syntax`, `Python.sublime-syntax`, `Rust.sublime-syntax`, `Bash.sublime-syntax`, `SQL.sublime-syntax`) in `syntaxes/` ensures deterministic behavior without external dependency traps.
5. **Declarative Domain Anchoring (Declarations vs. Qualifiers)**:
   - Module and namespace declarations (`package main`, `namespace core::telemetry`, `using namespace ...`) establish architectural boundaries and are highlighted in **Solarized Violet (`#6C71C4`)**.
   - In-code qualifiers (`context.`, `fmt.`, `std::`, `boost::`) are navigational routing metadata. Coloring them causes high-frequency chromatic vibration against adjacent types (Yellow) and functions (Blue). They strictly remain in calm **Base0 Grey (`#839496`)**.
6. **Functional Invariance Across Definition and Call Sites (No Semantic Flipping)**:
   - In languages like Go where constructors are standard functions returning pointers or structs rather than language-level primitives, an identifier's semantic role must remain invariant across definition and invocation. Upstream Tree-sitter regexes (`^[nN]ew.+$`) that color factory calls as `@constructor` (Yellow) are overridden to `@function.call` in **Solarized Blue (`#268BD2`)**, maintaining visual continuity with `func New...`.
7. **Dual-Identity Contextual Disambiguation (Operational Role Invariance)**:
   - Language keywords and built-in identifiers often fulfill different syntactic functions depending on their usage context. In Java, C++, and Python:
     - When used as an instance reference or receiver (`this.timeoutMs`, `self.val`, `super.init()`), it represents an immutable reference to the current or parent object instance, categorized as a built-in constant/value in **Solarized Magenta (`#D33682`)** (`@variable.builtin` / `variable.language`).
     - When used as an explicit constructor delegation (`this(...)`, `super(...)`), it acts as a callable routine invoked with argument lists, categorized as an invocation in **Solarized Blue (`#268BD2`)** (`@function.builtin` / `variable.function`).
   - Highlighting must reflect the **operational role** of the token at runtime rather than its static keyword spelling. Lookaheads (`(?=\()`) in regex syntaxes and AST parent node constraints (`(constructor_invocation)`) in Tree-sitter ensure functional continuity across invocation sites.
8. **Temporal Grammatical Divergence (The LTS Currency Imperative)**:
   - Operating system package managers and upstream text-editor grammars inevitably lag programming language evolution by 5–10 years (e.g. standard Sublime Text Java grammars lack Java 16+ records, Java 21+ pattern matching, Java 23+ Markdown comments, and Java 25+ flexible constructor bodies).
   - Workstations provisioning actively supported LTS language runtimes (Java 17/21/25, C++20/23, Go 1.22+, Rust 2021/2024) must decouple themselves from upstream grammar stagnation by maintaining version-controlled, standalone grammars and Tree-sitter query overrides in `syntaxes/` and `after/queries/`.
9. **Positional Grammatical Anchoring (The Statement vs Expression Boundary Principle)**:
   - In dynamically typed or indentation-delimited languages without statement delimiters (Python, YAML, Ruby), punctuation marks like colons (`:`) fulfill divergent grammatical roles (statement block headers `if:`, `try:`, `finally:` vs variable type annotations `x: int` vs dictionary key-value pairs).
   - In pushdown automaton regex syntax engines (`bat` / Syntect), an unanchored rule like `({{ident}})\s*(:)\s*` greedily matches statement headers (`try:`, `finally:`, `if metric is None:`), pushing the `type-expression` context and poisoning subsequent lines into miscolored types (**Solarized Yellow `#B58900`**).
   - Grammatical rules for variable and member declarations must enforce **strict positional anchoring** (`^\s*`, parameter-list containment, or negative lookahead constraints) rather than greedy mid-line matching to ensure contextual transitions respect structural block boundaries.
10. **Interpolation Isolation & Non-Bleeding Scoping (The Nested Scope Isolation Principle)**:
   - Modern languages support interpolated strings (Python f-strings `f"..."`, JS template literals `` `...` ``, Ruby `#{...}`, C# `$"{...}"`), interleaving static string literals with dynamic executable expressions.
   - Applying a blanket `meta_scope: string.interpolated` over an entire interpolation container causes nested expression tokens inside `{...}` (variable identifiers, function invocations, formatting specifiers) to inherit the parent string Cyan scope, dulling or distorting their syntax accents.
   - Interpolation containers must enforce **strict lexical boundaries**: literal text segments receive continuous string scoping (**Solarized Cyan `#2AA198`**), interpolation delimiters (`{`, `}`) remain calm punctuation in Base0 grey, format specifiers (`:.4f`, `:X`) remain calm and structured, and embedded expressions dynamically transition to the full expressive syntax hierarchy of the language (variables in Base0, function calls in Blue, numbers in Magenta) without background scope bleeding.
11. **Universal Directive Classification for Syntactic Annotations (Decorators & Attributes as Tier 3 Inclusions)**:
   - Multi-paradigm languages provide declarative meta-programming constructs: Python decorators (`@dataclass`, `@property`), Java annotations (`@Service`, `@Override`), C++ attributes (`[[nodiscard]]`), Rust attributes (`#[derive(...)]`), and C preprocessor directives (`#include`, `#define`).
   - Upstream grammar distributions often introduce arbitrary splits—for example, treating `@property` as a keyword (Green) while `@dataclass` is an attribute (Orange), or treating C++ `[[nodiscard]]` as Base0 punctuation.
   - All declarative meta-programming directives modifying declarations or runtime dispatch fulfill the invariant role of **compiler / runtime directives (Tier 3)** and are strictly unified in **Solarized Orange (`#CB4B16`)** across all syntax engines (`keyword.other.decorator`, `storage.type.annotation`, `meta.attribute` in `bat`, and `@attribute`, `@keyword.directive` in Neovim).
12. **Atomic Compound Enclosure (The Multi-Token Sigil Invariance Principle)**:
   - Modern languages employ composite sigils and meta-programming enclosures: Rust attributes (`#[derive(...)]`, `#![no_std]`), Rust lifetimes (`'a`, `'static`), C++ attributes (`[[nodiscard]]`), Python decorators (`@dataclass`), and Java annotations (`@Override`).
   - Upstream tokenizers frequently atomize these composite constructs into disjoint lexical tokens (e.g. Tree-sitter scoping `#` as `@punctuation.special` in Green, `[` as Base0, and `derive` as `@attribute` in Orange; or `'` as `@keyword.modifier` in Green and `a` as `@attribute` in Orange).
   - In human visual perception (Gestalt law of closure and continuity), the enclosure sigil and its enclosed identifier form a single, inseparable cognitive unit. Fracturing the sigil from the identifier across contrasting palette accents forces saccadic eye movement and breaks visual coherence.
   - Enclosure punctuation (`#`, `!`, `[`, `]`, `'`) must be visually unified with the payload directive in **Solarized Orange (`#CB4B16`)** for attributes/directives and **Solarized Green (`#859900`)** for storage/borrow modifiers across all syntax engines.
13. **Pushdown Automata Delimiter Consumption Trap (The Lookahead vs. Consumption Invariance)**:
   - In pushdown automaton regex grammar engines (`bat` / Syntect / Sublime Text), using non-consuming lookaheads to trigger contextual state transitions (e.g. `match: '({{ident}})\s*(?=\()'` with pop condition `match: '\)'`) creates a fatal failure mode if inner contexts also consume delimiters.
   - Specifically, if an inner rule matches `\(` and `\)`, the unconsumed opening `(` triggers the child rule, which subsequently consumes the closing `\)`. As a result, the parent context's pop condition is never satisfied, trapping the parser permanently in the child context and corrupting all subsequent file lines into miscolored scopes or unstyled text.
   - Grammatical push transitions must strictly consume their opening delimiters (`match: '({{ident}})\s*(\()'` with capture 2 scoped to punctuation) so that delimiter balance counters and push/pop symmetry remain mathematically deterministic.
14. **Cross-Paradigm Morphological Disambiguation (Modifier vs Nominal Generic Parameters)**:
   - In languages supporting unified generic parameter lists (e.g. `<'a, T>` in Rust, or `template <typename T, auto N>` in C++), tokens occupying identical syntactic positions fulfill fundamentally distinct semantic roles: nominal types (`T`) are domain nouns (**Solarized Yellow `#B58900`**), whereas borrow/lifetime qualifiers (`'a`) are temporal constraint modifiers (**Solarized Green `#859900`**).
   - Highlighting engines must disambiguate based on morphological sigils (leading apostrophe `'`) and functional roles rather than naive bracket-containment scoping, preventing nominal types from bleeding into modifiers or vice-versa.
15. **Syntactic Compounding vs Operand Autonomy (Composite Operator Deconstruction)**:
   - In shell and systems programming, operators frequently bind directly to operands without separating whitespace (e.g. file descriptor redirections `>&2`, `<&1`, `2>&1`, address-of/dereference `*ptr`, `&val`).
   - Naive pushdown regex engines match the entire composite construct as a single monolithic operator token, swallowing the operand into the operator's neutral foreground (**Base0 Grey `#839496`**).
   - Highlighting engines must decompose composite operator-operand tokens at lexing time so that operands retain their intrinsic domain categorization (file descriptors and numeric literals in **Solarized Magenta `#D33682`**, operators in **Base0 Grey `#839496`**), mirroring compiler AST leaf nodes.
16. **Structural Scope Isolation for Context-Dependent Grammar (Statement Arm Isolation)**:
   - In language constructs with custom branch headers (such as shell `case ... in ... esac` arms `INFO)`, `WARN)`, `*)` or pattern matching guards), identifiers appear unquoted at the start of indented lines.
   - Without an isolated pushdown parser state, general statement parsers greedily classify these branch labels as executable command or function invocations (**Solarized Blue `#268BD2`**).
   - Grammars must enforce strict state transitions upon entering branch blocks (`case ... in` -> push `case-body`). Line-initial identifiers within branch bodies must be scoped as pattern labels / arguments (**Base0 Grey `#839496`**) or regex wildcards (**Solarized Magenta `#D33682`**), shielding them from top-level statement dispatch until branch terminators (`;;`, `esac`) pop the context.
17. **Contextual Polysemy of Universal Sigils (Structural Role Disambiguation)**:
   - Multi-purpose punctuation marks (`@`, `*`, `#`) carry fundamentally divergent semantic meanings depending on grammatical placement. In shell:
     - In positional expansions (`$@`, `$*`), `@` represents the collection of argument parameters (**Solarized Magenta `#D33682`**).
     - In array subscripts (`${arr[@]}`, `${arr[*]}`), `@` is an iteration wildcard index (**Solarized Cyan `#2AA198`**).
   - Universal sigils must never be assigned blanket keyword or constant scoping across an entire language grammar. Scoping rules must enforce structural containment checks (e.g. subscript brackets `[...]` vs prefix parameter sigils `$`) to reflect the exact semantic role of the token.
18. **Sub-Grammar Inheritance Isolation (The Legacy Fallback Trap)**:
   - In modular text-processing environments, layered grammar inheritance cascades (e.g. `SQL -> MySQL -> SQL (basic) -> TextMate SQL.tmLanguage`) create hidden single points of failure.
   - When an upstream dependency fails to resolve in a standalone utility, the runtime silently falls back to legacy regex grammars whose antiquated semantic scopes (such as categorizing database columns as `constant.other.column-name`) catastrophically poison downstream syntax themes into garish, unreadable color palettes (turning column identifiers violently Magenta).
   - Specialized language support must be implemented via **fully isolated, non-inheriting, self-contained grammars** that declare all root contexts explicitly, eliminating cascading dependency traps and ensuring invariant, predictable theme rendering across all host systems.
19. **Relational Paradigm Ontology (Relational Entities as Schema Types)**:
   - Programming language highlighting systems are historically biased toward imperative and object-oriented paradigms, where "types" denote primitive scalars (`int`, `bool`) and class/struct definitions, while collections and tables are variable instances.
   - In relational database theory (Codd's relational model), relations (tables, views, materialized views, CTE aliases, and schema indexes) represent the structural data schemas and relational types of the schema domain, whereas columns represent attributes and tuples represent records.
   - Highlighting systems must reflect this relational ontology by treating tables, CTEs, and indexes as structural schema entities in **Solarized Yellow (`#B58900`)**, while preserving attribute columns and alias navigators in calm **Base0 Grey (`#839496`)**, avoiding cognitive dissonance between imperative types and relational schemas.
20. **Tri-State Logic & Sentinel Disambiguation (Literal vs Type Classification)**:
   - In SQL's three-valued logic (3VL), `NULL` represents an unknown/missing state value or sentinel literal, behaving analogously to `nil`, `None`, and `nullptr` in systems programming.
   - Upstream AST grammars (such as Tree-sitter SQL) frequently misclassify `NULL` under `@type.builtin` simply because SQL column specifications permit `NOT NULL` constraints, erroneously grouping the keyword under type rules.
   - Semantic token mapping must strictly disambiguate syntactic keywords by their operational logic: `NULL`, `TRUE`, and `FALSE` are boolean and sentinel literals (**Solarized Magenta `#D33682`**), decoupled from structural types and keywords, ensuring visual parity across imperative, functional, and relational environments.
21. **Contextual Polysemy of Multi-Semantic Operators (Arithmetic vs Projection Invariance)**:
   - Punctuation symbols such as the asterisk (`*`) serve radically divergent functions within the same language: as a projection quantifier (`SELECT *`, `COUNT(*)`, `t.*`) denoting relational attribute expansion, versus a binary arithmetic operator (`a * b`, `price * quantity`) denoting mathematical multiplication.
   - Naive regex engines indiscriminately classify all asterisks as wildcards or constants, polluting arithmetic expressions with distracting syntax accents.
   - Grammars must maintain contextual distinction: binary arithmetic operators between expressions remain in calm **Base0 Grey (`#839496`)**, while projection and quantifier expansions are isolated within selection contexts and tuple accessors.

### Integration Rules & Tooling Implementations
1. **3-Tier Ergonomic Architecture**: All syntax highlighting across Neovim, `bat`, and shell environments strictly follows the 3-Tier cognitive hierarchy:
   - **Tier 1: Monotone Ground (70–80% screen area)**: Base0 (`#839496`) and Base01 (`#586E75`). Houses variables, field names, symbolic math/logic operators (`+`, `-`, `*`, `/`, `=`, `==`, `<`, `>`, `?`, `:`), delimiters, brackets (`()`, `{}`, `[]`), upright parameters, upright comments, Go dot qualifiers (`context.`, `fmt.`, `time.`), and C++ scope qualifiers (`std::`, `boost::`). Keeps the background calm and eliminates visual vibration caused by equal-lightness accent switching.
   - **Tier 2: Structural Anchors (15–20% screen area)**: Green (`#859900`), Yellow (`#B58900`), Blue (`#268BD2`), Violet (`#6C71C4`). Frames program architecture: Green for control flow (`if`, `for`, `return`), declarations (`package`, `typedef`, `struct`), and word operators (`sizeof`, `alignof`, `static_assert`); Yellow for primitive and custom types (`int`, `char`, `WorkerNode`, `SeverityLevel`, `*_t`, `map`, `chan`, concepts); Blue for function declarations, method calls, and user function invocations (`emit_log`, `printf`, `malloc`, `NewClusterNode`); Violet for module and namespace declarations (`package main`, `namespace core::telemetry`, `using namespace`).
   - **Tier 3: Values & Directives (5–10% screen area)**: Cyan (`#2AA198`), Magenta (`#D33682`), Orange (`#CB4B16`). Highlights payload data: Cyan for strings, unbroken escape sequences/format specifiers (`\n`, `%s`), and struct tags; Magenta for numeric literals, booleans (`true`, `false`), named `ALL_CAPS` / `iota` constants/enum members (`EXIT_FAILURE`, `MAX_BUFFER_SIZE`, `LOG_ERROR`, `NodeState::Initializing`, `LevelDebug`), and sentinels (`std::nullopt`); Orange for external inclusions and directives (`import`, `from`, `use`, `#define`, `#include`, `[[nodiscard]]`).
2. **Word Operators vs Symbolic Operators**: Reserved keyword operators (`sizeof`, `alignof`, `_Alignof`, `static_assert`, `_Generic`) are mapped to **Solarized Green (`#859900`)** matching Neovim's `@keyword.operator`. Symbolic operators (`+`, `-`, `*`, `?`, `:`, `==`, `=`) strictly remain calm in **Base0 grey (`#839496`)**.
3. **Gestalt String Continuity**: String literals, format specifiers (`%s`, `%d`, `%lX`), escape characters (`\n`, `\t`), and Go backtick struct tags are strictly unified in **Solarized Cyan (`#2AA198`)** to avoid disruptive checkerboarding inside strings.
4. **`bat`**: Uses `colors/Solarized-Dark-TrueColor.tmTheme` compiled into cache (`bat cache --build`) with italic rendering (`BAT_OPTS="--italic-text=always"`), modern Sublime C/C++/Diff/Go/Java/Python/Rust/Bash/SQL syntaxes in `syntaxes/`, and full Solarized Dark palette coverage. Function calls (`variable.function`) are mapped to Blue, word operators (`keyword.operator.word`) to Green, PascalCase types (`support.type.user-defined`) to Yellow, `ALL_CAPS` constants and `variable.other.constant` to Magenta, diff additions to Green, deletions to Red, and hunk ranges to Blue. Available via `bat` or `b`; `cat` strictly remains standard Unix coreutils.
5. **`eza`**: Available via `e`, `el`, `elm`, `et`, `elt`, and `elx`, with `EZA_COLORS` and `EXA_COLORS` configured with Solarized Dark palette. Native `ls` and `ll` use standard GNU/BSD `ls` with Solarized `dircolors`.
6. **Neovim Lua**: Uses `maxmx03/solarized.nvim` with `variant = "spring"` matching `bat` 1:1, integrated with Native Neovim 0.11+ LSP (`vim.lsp.config`, `LspAttach`) and Tree-sitter queries in `after/queries/` (including `c/highlights.scm`, `cpp/highlights.scm`, `diff/highlights.scm`, `go/highlights.scm`, `java/highlights.scm`, `python/highlights.scm`, `rust/highlights.scm`, `bash/highlights.scm`, and `sql/highlights.scm` capturing `package` in Green, `import` in Orange, `sizeof` type arguments as `@type`, factory functions as Blue, records/guards as Green, annotations/decorators as Orange, method initializers as Blue, Rust attributes as Orange, Rust lifetimes as Green, Bash trap signals, positional parameters, redirection descriptors, case patterns, subscript wildcards, and SQL null sentinels, table alias qualifiers, and relational objects matching bat).
7. **Zsh Autosuggestions**: Highlight style is pinned to `fg=#586E75` (Solarized Base01).
8. **CLI Syntax Highlighting (`zsh-syntax-highlighting` / `ZLE`)**: Explicitly configured in `.zshrc-addendum` using 24-bit TrueColor Solarized Dark with restrained, non-distracting syntax highlighting (`commands` green `#859900`, `strings` cyan `#2AA198`, `numbers` magenta `#D33682`, `functions`/`paths` blue `#268BD2`, `errors` red `#DC322F`, `comments`/`suggestions` base01 `#586E75`, `selection` base02 `#073642`, with options, parameters, assignments, and operators kept calm in neutral foreground base0 `#839496`).
9. **GNOME Terminal**: Configured via `colors/gnome-terminal-solarized.dconf` and `bin/gnome-terminal-solarized` with authentic TrueColor Solarized Dark, Color 8 pinned to `base01` (`#586E75`), MesloLGS NF 12 font, and base02 highlight.
10. **Explicit Markup Tags Only for Typography**: Italics and bold are strictly reserved for text where the author has explicitly written markup tags (e.g. Markdown `*italic*` and `**bold**`, `#` headings, or HTML `<i>`/`<b>`). All programming code tokens, parameters, keywords, and comments remain 100% upright regular monospace.

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
