---
name: mono-tui-design
description: Design and build terminal user interfaces for home-settings (`bin/ide`, `libexec/ide_lib/`, `dotfiles/.tmux.conf`, and `libexec/theme_lib/`) following the Monospace Design TUI (`mono-tui v0.2.5`) specification and project rules. Use when adding, modifying, or styling IDE views, popups, layouts, status bars, themes, or keybindings.
---

# Monospace TUI design skill

Use this skill when designing, implementing, or refactoring terminal UI views, `tmux` chrome, `fzf` pickers, popups,
themes, or keyboard interactions in `bin/ide`, `libexec/ide_lib/`, `libexec/theme_lib/generators.py`, `dotfiles/.tmux.conf`,
or `dotfiles/.config/nvim/lua/solarized/ide.lua`.

## Reference reading order

Always resolve rules in this order (higher overrides lower):

1. [monospace-tui.md](../../rules/monospace-tui.md): Project-specific `[OVERRIDE]`, `[WAIVE]`, and `[P#]` rules for
   `home-settings`.
2. [standard.md](references/standard.md): The Monospace Design TUI (`mono-tui v0.2.5`) interaction, layout, keyboard,
   and archetype specification.
3. [rendering.md](references/rendering.md): Character encodings, layout geometry, ANSI color palettes, component
   measurements, and color capability degradation (`§R1` to `§R4` and `§R7`).
4. [patterns.md](references/patterns.md): Canonical interaction patterns and audit checklists (`Footer Command Bar`,
   `Focused Surface`, `Master-Detail`, `Expand-to-Focus`, and `Search/Select Set`).
5. [AGENTS.md](../../../AGENTS.md): Repository-wide architecture, 14-slot Solarized palette contract, keybinding
   layers, and testing invariants.

## Design and implementation workflow

1. **Identify the screen and workflow archetype**:
   * Map changes to `ide`'s `§11.1` operational cockpit top shelf (`dotfiles/.tmux.conf`), `§11.5` fuzzy finder and
     `Master-Detail` workspace switcher (`ide -s` in `libexec/ide_lib/switcher.py`, `sessions.py`, `preview.py`, and
     `dock.py`), `Expand-to-Focus` directory launcher (`Alt+n` `New IDE >`), or responsive `108×34` / `80×24` modal
     overlays (`ide keys` in `bin/ide`).
2. **Apply project overrides, focus clarity, and glyph hygiene**:
   * Keep both main workspace and `ai-sw-*` switcher `pane-border-style`, `pane-active-border-style`, and
     `WinSeparator` calm in `BASE01` (`[OVERRIDE] §6.1`, avoiding two-tone `tmux` border seams), distinguishing active
     versus inactive switcher panes via left-aligned `[PREVIEW]` versus `▸ ... [LIVE]` top-border labels
     (`[OVERRIDE] §6.3`).
   * Keep classic daily-driver themes 100% free of vendor-bitmap emojis, and gate Nerd Font PUA glyphs in `bin/ide` and
     `libexec/ide_lib/` through `use_nerd_fonts()` (`IDE_NERD_FONTS=0` / `TERM=dumb` ASCII fallback, `[P1]`).
   * Derive all colors through `load_active_palette()` (`detect_color_tier()` in `libexec/ide_lib/theme.py`) and
     `generate_tmux_theme_text()` (`[OVERRIDE] §R3.2`), supporting TrueColor, 256-color, 16-color, `TERM=dumb`
     monochrome SGR attributes, and `NO_COLOR`.
3. **Preserve keyboard layers and CUA dual-key discoverability**:
   * Never bind unmodified printable keys or root `Ctrl+h/j/k/l` in `dotfiles/.tmux.conf` (`[OVERRIDE] §2.2 and §2.8`).
   * Keep `F1` (`ide keys`) and `F5` (`reload`) bound alongside `Alt+?` and `Ctrl+r` inside `ide -s`, and keep
     `format_sessions_footer_label` width-fitted to the active pane so footer hints never clip mid-word
     (`[OVERRIDE] §1.4 and §R4.11`).
   * Synchronize any user-facing keybinding or CLI flag across both conceptual prose and reference tables in `README.md`.
4. **Enforce defensive rendering, lazy docking, and 80×24 geometry**:
   * Gate two-pane side-by-side `ai-sw-*` (`libexec/ide_lib/switcher.py`) and `bin/theme` (`libexec/theme_lib/preview.py`)
     layouts on `90` columns (`[OVERRIDE] §1.6`), stacking vertically on narrower viewports, flipping Neovim Telescope
     (`layout_strategy = "flex"`) below `110` columns, and scaling `mini.files` below `80` columns so split panes keep
     their preview windows.
   * Keep `ide keys` within `<= 104` columns and `<= 30` lines inside `108×34` popups on standard canvases while
     degrading to `<= 76` columns and `<= 22` lines on `80×24` terminals, scale the top `tmux` status bar across `120`,
     `105`, and `95`-column tiers, and fit interactive `ide list`, `ide new`, and `theme --list` / `--preview` outputs
     to the active TTY width without truncating piped output (`[P2]`).
   * Stream read-only ANSI previews during `fzf` browsing without `swap-pane` or `SIGWINCH`, lazily docking on
     `Alt+l`, `Alt+a`, or click and restoring `copy-mode` `scroll_position` and zoomed Editor `winsaveview()` on
     undock (`[P3]`).
5. **Verify with lints and isolated PTY tests**:
   * Add or update isolated `tmux` and PTY assertions in `tests/test-ide-fleet.sh`, `tests/test-bin.sh`,
     `tests/test-dotfiles.sh`, and `tests/test-vim.sh` (always clearing `TMUX=""` and `TMUX_PANE=""`).
   * Run `make check` to validate shellcheck, Python 3.9+ AST compliance, verbatim `[OVERRIDE]` / `[WAIVE]` freshness,
     documentation links, and all 10 parallel test suites.
