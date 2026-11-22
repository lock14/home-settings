# Documentation architecture and technical writing style

Technical documentation in `home-settings` is engineered for cognitive efficiency, scannability, and long-term accuracy. It communicates system mental models and mechanical precision without marketing prose, conversational filler, or typographic clutter.

These guidelines synthesize the Google Developer Documentation Style Guide, Matthew Butterick's *Practical Typography*, Diátaxis, Google Engineering Practices, and Chris Beams' Git commit conventions. Apply these 6 principles across `README.md`, `AGENTS.md`, `docs/*.md`, pull requests, issues, comments, and commit messages.

## Principle I: Intent-driven architecture (Diátaxis and macro-to-micro flow)

Separate documentation by reader intent rather than mixing tutorials, reference tables, and design history in a single stream:

- **Quick start (Tutorial)**: The shortest command sequence to reach a working state. Omit alternative flags, edge cases, and architectural history.
- **Task guides (How-to)**: Goal-oriented recipes written in the imperative mood for readers who already know the basics.
- **Lookup tables (Reference)**: Austere, factual tables and schemas that mirror the codebase without narrative prose.
- **Architecture (Explanation)**: System topology, design rationale, and trade-offs ("why"), organized from macro mental model down to runtime mechanics and concrete toolchains:
  - **Tier 1 (mental model and spatial architecture)**: System topology, geometry, layout, purpose, and visual metaphors (such as Inverted-T 3-pane versus 2-pane geometry and session isolation).
  - **Tier 2 (first-principles structural layers)**: Conceptual decoupling and behavioral tiers (such as the 4 keybinding layers: App-Local, Spatial Navigation, Editor and Explorer, Clickable Links and Clipboard).
  - **Tier 3 (runtime engines and automation)**: Execution mechanics, event loops, data flow, telemetry, and edge-case mitigation (such as native `autoread` and `checktime` synchronization and non-destructive pane parking).
  - **Tier 4 (toolchains, plugins, and integrations)**: Concrete tool configurations, LSP servers, syntax parsers, and terminal profile integrations.

## Principle II: Dual representation rule (prose and lookup tables)

- Interactive keybindings, CLI flags, environment variables, and shell shortcuts must never exist exclusively inside paragraph prose.
- Represent them in two places:
  - Conceptually within their structural section (explaining how they fit the workflow, why they are mapped, and how they avoid domain conflicts).
  - Tabularly in a dedicated reference table ([IDE workspace keybindings and navigation](../README.md#ide-workspace-keybindings-and-navigation), [Git and shell shortcuts](../README.md#git-and-shell-shortcuts)) with sentence-case column headers for fast lookup.
- Use tables only for genuine two-dimensional data (items sharing three or more attributes, or structured key-value lookups), never for single-column lists.

## Principle III: The non-accretion rule (holistic maintenance)

- When introducing or modifying features, never append a standalone bullet point or note to the end of an existing section.
- Review the surrounding section holistically:
  - Integrate the change into its proper architectural tier or table.
  - Prune superseded or redundant statements so the document reads as a single cohesive draft.

## Principle IV: High information density and zero fluff

- **No marketing or conversational filler**: Omit buzzwords ("effortlessly", "blazing fast", "seamlessly") and preambles ("Note that...", "In this section we will...", "It is worth mentioning...").
- **Concrete semantic payload**: Every sentence must state exact technical nouns, flags, file paths, key combinations, and deterministic runtime behaviors.
- **User-facing readability versus internal specification**: In `README.md`, communicate what features do and how to use them in clear, scannable prose. Never chain long sequences of inline code spans, internal variable or option names (`@ide_*`, `#{...}`), Tree-sitter S-expressions, URL route templates, or repetitive RGB hex codes in a single paragraph—keep low-level implementation mechanics in `AGENTS.md` and `docs/*.md`.
- **Zero aspirational documentation**: Document only behavior that is implemented, tested, and verified against the current codebase.

## Principle V: Typography and formatting restraint (Google Style Guide, Butterick)

- **One format per span**: Never combine bold, italics, code font, or hyperlinks on the same text (no bolded code spans, no bolded links, no bold-italics, no bolded first-column table cells).
- **Strict role separation**:
  - **Code font**: Use backticks strictly for literal code, CLI commands, flags (`--3pane`), file paths (`dotfiles/.tmux.conf`, `init.lua`), configuration keys, and keyboard shortcuts (`Alt+h`, `Space e`, `Ctrl+Click`). Keep sentence punctuation outside the backticks.
  - **Bold**: Use `**...**` only for UI labels and run-in headings at the start of list items. Never use bold for mid-sentence emphasis or whole clauses.
  - **Italics**: Use `_..._` or `*...*` only when introducing or defining a term on first use, or for titles of standalone works.
- **Sentence case headings**: Use sentence case for all document titles, section headings, and table column headers (capitalize only the first word and proper nouns), with no trailing punctuation, and surround every heading with blank lines.
- **Zero yellow and zero artificial bold in headings**: Never use yellow in Markdown headings and never apply bold font styles across entire headings (`bold = false`).
- **No decorative symbols, Latin abbreviations, or math arrows in prose**: Omit decorative emojis, GitHub emoji shortcodes, Latin abbreviations (write "such as", "that is", "and more", and "versus"), LaTeX math arrows, ASCII arrows, and inequality signs (`>`) as prose connectors. Write plain verbs ("maps to", "takes precedence over") instead.
- **No horizontal section dividers**: Do not place horizontal rules between sections; Markdown headings already provide structural hierarchy.
- **Clean punctuation**:
  - **Parentheses**: Use sparingly and keep short. Never place critical requirements inside parentheses, never nest parentheses, and never pack long lists of code spans inside parentheses mid-sentence. Avoid optional plurals like `file(s)`.
  - **Slashes and connectors**: Do not use slashes (`/`), ampersands, or plus signs in prose to join words (write "or" and "and" instead). Reserve `/` for file paths, URLs, and literal commands.
  - **Dashes**: Use hyphens (`-`) for compound modifiers, "to" for ranges, and unspaced em-dashes (`—`) sparingly for clause breaks. Never use dashes to separate a list term from its definition; use a colon after run-in list headings.
- **List discipline**:
  - Use numbered lists strictly for sequential steps where order matters; use bulleted lists for non-sequential sets.
  - Keep list items parallel in grammatical structure and consistent in terminal punctuation.
  - Avoid italic parenthetical asides. If a detail matters, state it as a normal sentence; reserve callout blocks (`> [!IMPORTANT]`) for destructive hazards or critical prerequisites.

## Principle VI: Surface-specific standards

- **READMEs**: Open with a two-to-three sentence summary of what the tool does and which platforms it targets, followed immediately by a minimal quick-start block, task guides, and reference tables. Keep build pipeline internals and agent instructions out of user-facing READMEs.
- **Pull request descriptions**: Use a standalone imperative sentence for the title, explain why the prior code was insufficient before summarizing subsystem changes, and keep templates lean (`## Summary` and `## Verification` with plain-text checkboxes).
- **Issues**: Include environment, numbered reproduction steps, expected behavior, and actual terminal output for bug reports; state the workflow problem before proposing CLI schemas for features.
- **Code and review comments**: Exported functions and modules state their contract and error behavior in complete sentences; implementation comments explain non-obvious constraints rather than restating code; review comments critique code on engineering principles (`Nit:` for polish).
- **Commit messages (Chris Beams' 7 Rules)**: Imperative capitalized subject targeting 50 characters (hard cap 72) with no trailing period, separated by a blank line from a 72-character-wrapped plain-text body explaining what problem existed and why the change was made.
