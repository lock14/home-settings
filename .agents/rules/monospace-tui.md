---
trigger: glob
globs: bin/ide, libexec/ide_lib/**/*.py, libexec/theme_lib/{generators,preview}.py, dotfiles/.tmux.conf, dotfiles/.config/nvim/lua/solarized/{ide,plugins}.lua
---

# Monospace TUI design standard and project rules

When designing, implementing, refactoring, or reviewing terminal UI surfaces in `bin/ide`, `libexec/ide_lib/`,
`libexec/theme_lib/{generators,preview}.py`, `dotfiles/.tmux.conf`, or `dotfiles/.config/nvim/lua/solarized/{ide,plugins}.lua`, follow the
embedded Monospace Design TUI (`mono-tui v0.2.5`) specification alongside the project overrides and conventions
declared in this file.

## Reference hierarchy

Consult these documents in precedence order (higher overrides lower when rules conflict):

1. **Project overrides and conventions**: The `[OVERRIDE]`, `[WAIVE]`, and `[P#]` entries in this file.
2. **Design and interaction standard**: [standard.md](../skills/mono-tui-design/references/standard.md) for screen
   and workflow archetypes, keyboard ergonomics, focus navigation, elevation, layout responsiveness, and content
   formatting.
3. **Rendering and implementation reference**: [rendering.md](../skills/mono-tui-design/references/rendering.md) for
   Unicode box-drawing tables, layout geometry, ANSI color tiers, component measurements, and color capability
   degradation.
4. **Canonical pattern library**: [patterns.md](../skills/mono-tui-design/references/patterns.md) for reusable
   interaction patterns (`Footer Command Bar`, `Focused Surface`, `Master-Detail`, `Expand-to-Focus`,
   `Object-Local Actions`, `Selection Grammar`, and `Live Drill-Down`) and audit checklists.
5. **Skill workflows**: [mono-tui-design](../skills/mono-tui-design/SKILL.md) for designing and implementing TUI
   features, and [mono-tui-audit](../skills/mono-tui-audit/SKILL.md) for auditing existing TUI views.

## Screen and workflow archetype mapping

The `bin/ide` terminal workspace, multi-session fleet switcher, and status chrome map to the following `mono-tui`
archetypes:

*   **Workspace multiplexer shell** (`dotfiles/.tmux.conf` and `libexec/ide_lib/layout.py`): `§11.1` dashboard and
    operational cockpit header (`status-position top` with `Focused Surface` `▸` role pills for `AI`, `Editor`, and
    `Shell`, inline mode-contextual `PREFIX` and `COPY` key hints, and clickable urgent attention and fleet counters)
    framing non-overlapping Level 1 panes for the AI Agent CLI, `§11.4` Neovim `Editor`, and interactive `Shell` in
    single-window Inverted-T (3-pane default) or side-by-side (`--2pane`) geometry.
*   **Multi-session workspace switcher** (`ide -s` or `ide switch` in `libexec/ide_lib/switcher.py`, `sessions.py`,
    `preview.py`, and `dock.py`): `§11.5` fuzzy finder paired with a responsive `Master-Detail` split view
    (`§12.4` search-act and `§12.3` monitor-respond workflows). On terminals at or above `90` columns, the left pane
    renders the urgency-ordered `fzf` session list above a live-streaming workspace metadata card while the right pane
    streams a read-only ANSI viewport preview (`[PREVIEW]`) with zero `swap-pane` or `SIGWINCH`, lazily docking the
    live `@ide_ai_pane` (`[LIVE]`) on demand when focused via `Alt+l`, `Alt+a`, or mouse click and undocking on
    `Alt+h`. Pressing `Alt+n` enters an `Expand-to-Focus` full-pane directory picker (`New IDE >`).
*   **Keybinding cheatsheet and fleet status table** (`ide keys` in `bin/ide` and `ide list` in
    `libexec/ide_lib/sessions.py`): Contextual two-column modal overlay (`Alt+?`, `Space ?`, `Prefix + ?`, or `F1`)
    rendering a spacious `108×34` (`<= 104×30` inner) sheet on standard and wide canvases with automatic `80×24`
    (`<= 76×22`) compact fallback, and `§R4.6` aligned fleet table pairing status colors with non-color markers
    (`▸` active, `󰂚` or `!` attention, `[unsaved]` dirty guard).

## Project overrides and conventions

The sections below document every intentional `[OVERRIDE]` and `[WAIVE]` against the upstream `mono-tui v0.2.5`
specification alongside `home-settings` project conventions (`[P1]` through `[P4]`).

### [OVERRIDE] §6.1 single-line calm workspace borders and rounded popup borders

*   **Original**: Applications MUST NOT use double-line borders for Level 0–2 elements. Applications MUST NOT use single-line borders for Level 3–4 elements.
*   **Project rule**: Both main `ide` workspace split panes (`AI`, `Editor`, `Shell`) and two-pane `ai-sw-*` modal
    switcher splits keep `pane-border-style` and `pane-active-border-style` unified in calm single-line `BASE01`
    (`dotfiles/.tmux.conf`, `libexec/ide_lib/switcher.py`, and `WinSeparator` in Neovim) so structural box-drawing lines
    never render two-tone half-colored border seams or compete with content (`AGENTS.md` Pillar I and Rule 37). Active
    pane focus is communicated through the top status bar `▸` role indicator in workspaces and through left-aligned `▸`
    and `[LIVE]` versus `[PREVIEW]` top-border title badges inside `ai-sw-*`. Level 3 and Level 4 `tmux` popups
    (`popup-border-lines rounded`) and `fzf` frames (`--border=rounded` with `border`, `separator`, and `label` pinned
    to `BASE01`, and `spinner` colored `CYAN` only while `WORKING` previews stream, masked to `BASE03` under
    `NO_MOTION=1` or `REDUCE_MOTION=1` per `§10.3`) use single-line rounded borders (`╭╮╰╯`) rather than double-line
    `═║╔╗╚╝` characters.
*   **Reason**: Eliminates high-chroma border distraction and `tmux` shared-border color splits while maintaining
    unmistakable `Focused Surface` label differentiation (`§5.5` and `§9.6`).

### [OVERRIDE] §6.3 left-aligned pane border titles with explicit preview versus live mode

*   **Original**: Window and panel titles MUST be centered in the top border row:
*   **Project rule**: `pane-border-format` in `libexec/ide_lib/switcher.py` left-aligns pane titles in the top border of
    each switcher pane (`▸ Sessions` on the left; `[PREVIEW]` when streaming read-only ANSI output versus `▸ ... [LIVE]`
    when the target workspace's `@ide_ai_pane` is docked interactively on the right).
*   **Reason**: Anchors scan lines to the left margin above left-aligned session rows and makes lazy-docked state
    immediately legible before typing (`patterns.md` `Focused Surface`).

### [OVERRIDE] §6.6 rounded corners for interactive popup and fuzzy-finder containers

*   **Original**: Rounded corner characters (`╭╮╰╯`) MAY be used for cosmetic, non-interactive containers (e.g., decorative cards, informational callouts). Rounded corners MUST NOT be used for interactive windows, dialogs, or panels that participate in the elevation system.
*   **Project rule**: Interactive `tmux` `display-popup` modals (`popup-border-lines rounded` in `dotfiles/.tmux.conf`)
    and `fzf` pickers (`--border=rounded` in `libexec/ide_lib/switcher.py`, `sessions.py`, and `theme.py`) use rounded
    `╭╮╰╯` corners as the workstation's unified overlay frame geometry.
*   **Reason**: Visually separates transient overlay modals (`Alt+s`, `Alt+n`, `Alt+m`, `Alt+?`) from the rectilinear
    `─│` pane splits of the underlying `ide` workspace.

### [OVERRIDE] §1.6 90-column side-by-side split breakpoint for the workspace switcher

*   **Original**: | Compact | 40–79 | Region A collapses; Region C hidden or stacked below B; footer reduces to single row |
*   **Project rule**: `SIDE_BY_SIDE_MIN_COLS = 90` in `libexec/ide_lib/switcher.py` and `run_fzf_picker` in
    `libexec/theme_lib/preview.py` gate two-pane side-by-side layouts on `>= 90` columns. Below `90` columns (including
    `80×24` minimum viable terminals, `§1.5`, and `50%` split panes), `ide switch` (`down:50%:wrap:noinfo`) and
    `bin/theme` (`down:58%:nowrap:noinfo`) automatically stack their preview pane below the `fzf` list. Inside Neovim
    (`dotfiles/.config/nvim/lua/solarized/plugins.lua`), Telescope uses `layout_strategy = "flex"` (`flip_columns = 110`)
    to stack file paths and code previews vertically inside narrow Editor splits, while `mini.files` scales `width_focus`
    below `80` columns so split Editor panes retain their right-hand preview window down to `42` columns.
*   **Reason**: Side-by-side horizontal splits below `90`–`110` columns crush multi-column tables, file paths, and code
    previews into `< 38` columns, whereas vertical stacking and proportional split scaling preserve full legibility.

### [OVERRIDE] §1.4 and §R4.11 top-bar mode hints and middle-dot-separated width-fitted fzf footers

*   **Original**: Format: `F1 Help  F5 Refresh  / Filter  q Quit` — key name followed by action label, separated by 2+ spaces. (CUA §1 function key area, Norton Commander F-key bar)
*   **Project rule**: In the main `ide` workspace, persistent bottom rows belong exclusively to inner applications
    (Powerlevel10k shell prompt and Neovim statusline), so workspace-level `PREFIX`, `COPY`, fleet, and `Help (Alt+?)`
    discoverability lives in the 1-row top `tmux` status shelf (`dotfiles/.tmux.conf` and `libexec/theme_lib/generators.py`,
    `AGENTS.md` Pillar VIII), scaling across `client_width >= 120` (full key hints), `105` (secondary SSH and subdir
    badges), and `95` (`80×24` compact role tabs and `[a]`, `[E]`, `[T]` parked markers). Inside `fzf` pickers
    (`libexec/ide_lib/switcher.py` and `sessions.py`), `format_sessions_footer_label` and `_format_new_picker_footer`
    render bottom `--border-label` hints joined with middle-dot separators (`" · "`, `U+00B7`) fitted to the exact pane
    width so narrow splits never clip an action mid-word.
*   **Reason**: Preserves zero-clutter bottom statuslines for shells and Neovim while keeping top-bar chrome and `fzf`
    command bars self-teaching and truncation-safe across all terminal widths.

### [OVERRIDE] §2.2 and §2.8 4-layer spatial Alt navigation, fzf Tab multi-select, and fuzzy input

*   **Original**: All single-letter key bindings MUST be case-insensitive — `r` and `R` trigger the same action, `d` and `D` trigger the same action, etc. Applications MUST bind both cases but MUST display only the lowercase form in the footer key strip.
*   **Project rule**: Inside `ide` workspaces, unmodified printable keys and `Ctrl+h/j/k/l` belong strictly to the
    active foreground application (`Layer 1`), while `Alt`-modified chords (`Alt+h/j/k/l`, `Alt+a/e/t`, `Alt+s`,
    `Alt+m`, `Alt+q`, `Alt+?`) and `Shift`-distinct counterparts (`Alt+Shift+H/J/K/L` swap, `Alt+Shift+E/T` park,
    `Alt+Shift+S` next attention, `Alt+Shift+Q` force-quit) govern workspace actions (`Layer 2`) across both normal
    panes and `tmux` `copy-mode-vi` (preserving active `scroll_position`). Inside `ide -s`
    (`§11.5` fuzzy layer), all printable characters feed the `fzf` filter, `Tab` toggles multi-session selection
    (`--multi`) for batch `Ctrl+y` acknowledgment and `Ctrl+x` quit while `Alt+l` and `Alt+h` switch focus between the
    list and live AI pane, `F5` and `Ctrl+r` reload the fleet list, and `F1` and `Alt+?` open the contextual keybinding
    cheatsheet (`ide keys`, which closes on `q`, `Q`, `Esc`, `?`, `Alt+?`, `F1`, `Space`, or `Enter`).
*   **Reason**: Prevents root-table `tmux` bindings from hijacking shell Readline, Neovim, or AI CLI keys while
    supporting multi-session batch triage in `fzf`.

### [OVERRIDE] §7.1 and §7.2 zero-bold monospace typography and pointer focus markers

*   **Original**: - Focused text MUST use reverse video (SGR 7).
*   **Project rule**: Across `dotfiles/.tmux.conf`, `libexec/theme_lib/generators.py`, and `libexec/ide_lib/`, UI labels and
    status pills keep `nobold` (`bold = false` in `solarized-dark` and daily-driver themes, `AGENTS.md` Pillar I) on
    TrueColor and 256-color terminals, indicating active pane, tab, and row focus via the `▸` (`U+25B8`) pointer glyph
    paired with `BASE1` / `BASE02` contrast (`--color=bg+:BASE02,fg+:BASE1,pointer:GREEN` in `fzf`) rather than full
    reverse-video bars (`SGR 7`), reserving `SGR 1` / `SGR 7` for `TERM=dumb` monochrome degradation (`§R3.4`).
*   **Reason**: Preserves zero-jitter monospace glyph widths and calm `60-30-10` Solarized luminance balance while
    retaining non-color glyph indicators (`▸`, `[LIVE]`, `[PREVIEW]`, `!`, `[unsaved]`) for accessibility (`§5.3`).

### [OVERRIDE] §R3.2 17-theme 14-slot semantic palette with 4-tier color degradation

*   **Original**: | Primary | 75 (light blue) | 17 (dark blue) | fg #5fafff, bg #00005f |
*   **Project rule**: All `bin/ide` and `tmux` colors derive from the active `home-settings` theme (`load_active_palette`
    in `libexec/ide_lib/theme.py` and `generate_tmux_theme_text` in `libexec/theme_lib/generators.py`) across 17 built-in
    themes and user `${XDG_CONFIG_HOME:-$HOME/.config}/home-settings/themes/*.theme` files, degrading across four
    capability tiers (`detect_color_tier` per `§5.6` and `§R7.1`): 24-bit TrueColor (`COLORTERM=truecolor|24bit` and
    modern TrueColor workstation `TERM` values `xterm-256color` / `tmux-256color`), 256-color (`COLORTERM=256color` or
    `TERM=screen-256color` / `rxvt-unicode-256color`), 16-color ANSI, and Monochrome / `NO_COLOR` (`TERM=dumb` SGR
    attributes or empty escapes under `NO_COLOR`).
*   **Reason**: Keeps `ide` visually unified with Neovim, `bat`, `delta`, `btop`, `eza`, and Powerlevel10k while
    remaining clean and operable on restricted SSH, serial, or `NO_COLOR` terminals.

### [OVERRIDE] §R1.7 single-character horizontal ellipsis for truncation

*   **Original**: | `⋯` | MIDLINE HORIZONTAL ELLIPSIS | U+22EF | Truncation indicator |
*   **Project rule**: `trunc_visible` and `sanitize_agent_msg` in `libexec/ide_lib/constants.py` use the single-column
    horizontal ellipsis `…` (`U+2026`) when truncating session names, branch labels, and hook summary messages.
*   **Reason**: `U+2026` has deterministic 1-cell width across standard monospace terminal fonts on Linux and macOS.

### [WAIVE] §6.4 drop shadows on tmux popups and switcher panes

*   **Original**: Shadows at Levels 2–4 MUST be rendered as a 2-column × 1-row offset below and to the right of the bordered element.
*   **Project rule**: Do not render `░` (`U+2591`) or custom character-cell drop shadows around `tmux` `display-popup`
    modals, `display-menu` menus, or `ai-sw-*` switcher panes.
*   **Reason**: Native `tmux` popup and menu primitives manage rectangular viewport compositing directly in C without
    exposing exterior shadow cells to child processes.

### [WAIVE] §6.5 background scrims behind tmux popups and Expand-to-Focus views

*   **Original**: Level 4 (modal overlay) MUST dim all background content behind the modal. The scrim MUST apply the dim attribute (SGR 2) to all non-modal cells while preserving their character content.
*   **Project rule**: Do not rewrite background pane buffers to simulate an `SGR 2` scrim when opening `tmux`
    `display-popup` overlays (`Alt+s`, `Alt+m`, `Alt+?`, `Alt+Shift+A`) or `Alt+n` `Expand-to-Focus` views.
*   **Reason**: Mutating live terminal pane buffers behind a `tmux` popup would corrupt running TUI applications;
    rounded `BASE01` popup borders clearly bound the modal surface.

### [P1] Nerd Font workstation icons with zero classic-theme emojis and ASCII opt-out

*   **Project rule**: On provisioned `home-settings` workstations (`MesloLGS Nerd Font Mono`), `tmux` and `bin/ide` use
    monotone Nerd Font PUA icons (``, `󰚩`, ``, ``, `󰂚`) and never emit fixed-bitmap color emojis in `solarized-dark`
    or any of the 9 classic daily-driver themes (`AGENTS.md` Rule 61). Whenever `IDE_NERD_FONTS=0` (or `IDE_ASCII=1` or
    `TERM=dumb`) is set (`use_nerd_fonts()` in `libexec/ide_lib/constants.py` and `bin/ide`), all `bin/ide` surfaces
    (`ide list`, `ide -s`, `ide _internal session-preview`, and `ide keys`) omit PUA codepoints and fall back to universal
    ASCII and standard Unicode markers (`▸`, `*`, `!`, `…`).
*   **Reason**: Preserves crisp monotone iconography on configured workstations while guaranteeing zero tofu (`□`) when
    inspecting sessions from unprovisioned remote or fallback terminals.

### [P2] ANSI-safe East Asian and tab-aware cell width math and responsive popup clamping

*   **Project rule**: All column alignment, truncation, preview tail fitting, and footer packing in `libexec/ide_lib/` and
    `libexec/theme_lib/preview.py` must measure visible cell widths via `visible_width` (`constants.py`),
    `_expanded_cell_widths` (`ide_lib/preview.py`), and `visible_len` (`theme_lib/preview.py`), accounting for ANSI
    escapes, tabs, combining marks, and 2-cell CJK or wide glyphs, terminate styled lines with `\033[0m`, fit interactive
    TTY table and preview outputs (`ide list`, `theme --list`, and strictly rectangular `theme --preview` cards) to the
    active viewport while leaving piped non-TTY output untruncated, and clamp popups (`ide keys` at `108×34` max `104×30`
    inner body on `>= 108×34` canvases, clamping and adapting to `<= 76×22` on `80×24` terminals; `ide -s` and `bin/theme`
    stacked below `90` cols) so `80×24` terminals and split panes never wrap borders or clip critical controls (`§1.5`).
*   **Reason**: Prevents right-edge wrap corruption, CJK and tab bottom-line clipping in `fzf` previews, and modal or
    table overflow on compact terminals and `50%` split panes.

### [P3] zero-polling tmux status chrome, lazy live AI docking, and cached previews

*   **Project rule**: Top `tmux` status chrome must evaluate 100% natively in C without `#(...)` shell polling
    (`AGENTS.md` Rule 60). Inside `ide -s`, browsing and filtering stream deduplicated ANSI frames (`write_slot_tty_viewport`
    and `_PreviewCache` throttling VCS checks to `vcs_interval = 1.6s`) onto the right placeholder PTY with zero
    `swap-pane` or `SIGWINCH`, docking the live `@ide_ai_pane` via `swap-pane -d` strictly on explicit right-pane focus
    (`Alt+l`, `Alt+a`, or mouse click) while saving and restoring `copy-mode` `scroll_position` and zoomed Editor
    `winsaveview()`.
*   **Reason**: Eliminates pane resize storms, scrollback resets, cursor jumps, and subprocess stutter during rapid
    fuzzy navigation.

### [P4] non-TTY, missing-fzf, and basic terminal graceful fallback

*   **Project rule**: When `fzf` is unavailable, `ide switch` degrades cleanly to `list_ide_fleet` (`ide list`)
    or prints `No active IDE sessions.` when empty; when non-interactive, `ide keys` prints the cheatsheet directly
    to `stdout` without blocking on `stty` raw key reads; when `btop` is absent, `ide monitor` falls back to `htop`
    and `top`.
*   **Reason**: Keeps every `ide` subcommand deterministic and scriptable across minimal containers, CI runners, and
    non-interactive shells.
