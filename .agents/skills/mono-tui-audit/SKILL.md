---
name: mono-tui-audit
description: Audit `home-settings` terminal UI code (`bin/ide`, `libexec/ide_lib/`, `dotfiles/.tmux.conf`, `libexec/theme_lib/generators.py`, and `lua/solarized/ide.lua`) against the Monospace Design TUI (`mono-tui v0.2.5`) specification and `.agents/rules/monospace-tui.md`. Use when reviewing TUI changes, checking `80×24` layout and color degradation compliance, or diagnosing visual, scroll, and keyboard bugs.
---

# Monospace TUI audit skill

Use this skill when auditing or reviewing `bin/ide`, `libexec/ide_lib/`, `libexec/theme_lib/generators.py`,
`dotfiles/.tmux.conf`, or `dotfiles/.config/nvim/lua/solarized/ide.lua` against the Monospace Design TUI
(`mono-tui v0.2.5`) specification and `home-settings` project rules.

## Audit reference order

1. [monospace-tui.md](../../rules/monospace-tui.md): Load all `[OVERRIDE]`, `[WAIVE]`, and `[P#]` entries first.
   Never flag an intentional project override or waiver as a violation; instead, verify the code follows the stated
   "Project rule" entry.
2. [standard.md](../mono-tui-design/references/standard.md): Check keyboard navigation, focus indicators, `80×24`
   minimum dimensions, layout responsiveness, and color independence rules that are not overridden.
3. [rendering.md](../mono-tui-design/references/rendering.md): Check `§R1` to `§R4` and `§R7` rendering rules (box
   alignment, SGR reset discipline, component measurements, and 4-tier color capability degradation).
4. [patterns.md](../mono-tui-design/references/patterns.md): Compare against `Footer Command Bar`, `Focused Surface`,
   `Master-Detail`, `Expand-to-Focus`, and `Search/Select Set` checklists.
5. [AGENTS.md](../../../AGENTS.md): Verify repository-wide glyph hygiene, zero-polling `tmux` status chrome, public
   path hygiene, and test isolation.

## Step-by-step audit checklist

1. **Glyph, theme, and color capability degradation**:
   * Confirm zero decorative emojis appear in `solarized-dark` or any of the 9 classic daily-driver themes, and confirm
     `IDE_NERD_FONTS=0` and `TERM=dumb` omit PUA icons cleanly across `ide --list`, `ide -s`, `ide --session-preview`,
     and `ide --keys` (`[P1]`).
   * Confirm `load_active_palette()` (`libexec/ide_lib/theme.py`) and `show_keys_cheatsheet()` (`bin/ide`) honor
     `NO_COLOR`, `TERM=dumb` monochrome SGR attributes, 256-color, 16-color, and 24-bit TrueColor (`[OVERRIDE] §R3.2`,
     `§5.6`, and `§R7.1`), and pair every status color with a non-color text or symbol indicator (`§5.3`).
2. **Container framing, focused-surface cues, and lazy-dock clarity**:
   * Confirm both main workspace and `ai-sw-*` switcher split borders (`pane-border-style` and
     `pane-active-border-style`) remain unified in calm `BASE01` without two-tone border seams, while switcher panes
     render explicit `[PREVIEW]` versus `▸ ... [LIVE]` left-aligned top-border titles (`[OVERRIDE] §6.1`, `§6.3`,
     `§6.6`, and `patterns.md` `Focused Surface`).
3. **Width math, 80×24 responsiveness, and footer parity**:
   * Confirm `SIDE_BY_SIDE_MIN_COLS = 90` (`libexec/ide_lib/switcher.py`) stacks `ide -s` vertically below `90` columns
     (`[OVERRIDE] §1.6`), `format_sessions_footer_label` packs complete `" · "`-separated hints within the pane width
     with zero mid-word clipping (`[OVERRIDE] §1.4 and §R4.11`), and `ide --keys` fits inside `-w 80 -h 24` (`<= 76`
     columns and `<= 22` lines, `[P2]`).
   * Confirm `visible_width`, `_expanded_cell_widths`, and `trunc_visible` (`…`, `[OVERRIDE] §R1.7`) preserve East
     Asian wide-char and tab alignment and append `\033[0m` on styled lines.
4. **Keyboard layers, scroll smoothness, and zero-jank UI performance**:
   * Confirm zero root-table `Ctrl+h/j/k/l` bindings or focus-stealing `WheelUpPane` / `WheelDownPane` `select-pane`
     calls exist in `dotfiles/.tmux.conf`, and confirm `F1` (`ide --keys`) and `F5` (`reload`) work alongside `Alt+?`
     and `Ctrl+r` inside `ide -s` (`[OVERRIDE] §2.2 and §2.8`).
   * Confirm `ide -s` browsing triggers zero `swap-pane` or `SIGWINCH`, lazy live docking preserves `copy-mode`
     `scroll_position` and zoomed Editor `winsaveview()`, and top `tmux` status chrome uses zero `#(...)` polling
     (`[P3]`).
5. **Override freshness and lint parity**:
   * Run `make lint` to verify every `### [OVERRIDE]` and `### [WAIVE]` section in `.agents/rules/monospace-tui.md`
     contains a verbatim `- **Original**:` quote from `standard.md`, `rendering.md`, or `patterns.md`, and all
     documentation links and keybinding tables stay synchronized.

## Audit report format

Group findings by severity:

* **Blocking violations**: Rules broken in `monospace-tui.md`, `standard.md`, or `rendering.md` with file path, line
  range, section reference, and concrete fix.
* **Non-blocking polish**: Minor layout, readability, or test coverage improvements prefixed with `Nit:`.
* **Verified compliant areas**: Summary of audited checks that passed.
