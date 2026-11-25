"""Canonical Python TUI keybinding registry, width-fitted footers, and top-bar hitbox specs."""

from __future__ import annotations

from dataclasses import dataclass
import os

from ide_lib.constants import trunc_visible, visible_width

TYPE_CHECKING = False
if TYPE_CHECKING:
    from collections.abc import Mapping

__all__ = [
    "ACTION_BY_ID",
    "AGENT_MODAL_KEY",
    "AGENT_PICKER_CANCEL_TEXT",
    "ALL_SESSION_EXPECT_KEYS",
    "CREATE_WS_FLIP_OPEN_KEY",
    "CREATE_WS_LAYOUT_KEY",
    "DIALOG_CANCEL_KINDS",
    "DIR_PICKER_FLIP_NEW_KEY",
    "KeyAction",
    "NEW_WORKSPACE_PROMPT",
    "NO_MATCH_LAUNCHER_EXPECT_KEYS",
    "OPEN_DIR_PROMPT",
    "PANE_JUMP_MODE_BY_KEY",
    "SESSIONS_PROMPT",
    "SWITCHER_ABORT_KEY",
    "SWITCHER_FOCUS_AI_KEY",
    "SWITCHER_FOCUS_LIST_KEY",
    "SWITCHER_SESSION_ACTIONS",
    "TOPBAR_ROLE_SPECS",
    "TOPBAR_ZOOM_CHORD",
    "agent_picker_footer_hints",
    "build_action_fzf_binds",
    "create_workspace_footer_hints",
    "format_card_footer",
    "format_dir_picker_footer",
    "format_sessions_footer_label",
    "fzf_key_to_display_chord",
    "is_ascii_ui",
    "pane_jump_mode_for_key",
    "sessions_expect_spec",
    "switcher_pane_border_hints",
    "switcher_submodal_hint",
    "topbar_tab_suffix_widths",
    "ui_hint_sep",
]

SESSIONS_PROMPT = "IDE > "
NEW_WORKSPACE_PROMPT = "New IDE > "
OPEN_DIR_PROMPT = "Open IDE > "

SWITCHER_ABORT_KEY = "alt-w"
SWITCHER_FOCUS_LIST_KEY = "alt-h"
SWITCHER_FOCUS_AI_KEY = "alt-l"
DIR_PICKER_FLIP_NEW_KEY = "alt-n"
CREATE_WS_FLIP_OPEN_KEY = "alt-o"
CREATE_WS_LAYOUT_KEY = "alt-2"
AGENT_MODAL_KEY = "alt-r"

DIALOG_CANCEL_KINDS: frozenset[str] = frozenset({"esc", SWITCHER_ABORT_KEY, "ctrl-c", "eof"})
AGENT_PICKER_CANCEL_TEXT: frozenset[str] = frozenset({"q", "Q"})

PANE_JUMP_MODE_BY_KEY: dict[str, str] = {
    "ctrl-a": "focus-ai",
    "alt-a": "focus-ai",
    "ctrl-e": "focus-editor",
    "alt-e": "focus-editor",
    "ctrl-t": "focus-term",
    "alt-t": "focus-term",
}

# Canonical top-bar role chords: (focus_chord, park_chord, compact_park_badge)
TOPBAR_ROLE_SPECS: dict[str, tuple[str, str, str]] = {
    "ai": ("Alt+a", "Alt+A", "A"),
    "editor": ("Alt+e", "Alt+E", "E"),
    "term": ("Alt+t", "Alt+T", "T"),
}
TOPBAR_ZOOM_CHORD = "Alt+z"

_SPECIAL_KEY_DISPLAY: dict[str, str] = {
    "enter": "Enter",
    "tab": "Tab",
    "btab": "Shift+Tab",
    "esc": "Esc",
    "escape": "Esc",
    "space": "Space",
}


def is_ascii_ui(env: Mapping[str, str] | None = None) -> bool:
    """Return True on monochrome (`TERM=dumb`) or ASCII (`TERM=linux`, `IDE_ASCII=1`) terminals."""
    src = os.environ if env is None else env
    term_lc = (src.get("TERM") or "").strip().lower()
    asc_lc = (src.get("IDE_ASCII") or "").strip().lower()
    return term_lc in ("dumb", "linux") or asc_lc in ("1", "true", "on", "yes")


def ui_hint_sep(env: Mapping[str, str] | None = None) -> str:
    """Return `' | '` on monochrome (`TERM=dumb`) or ASCII (`TERM=linux`, `IDE_ASCII=1`) terminals, else `' · '`."""
    return " | " if is_ascii_ui(env) else " · "


def _trunc_sfx(sep: str) -> str:
    return "." if sep == " | " else "…"


def fzf_key_to_display_chord(fzf_key: str, *, compact: bool = False) -> str:
    """Convert a canonical `fzf` key token (`alt-o`, `ctrl-y`, `f1`) to display notation (`Alt+o` or `M-o`)."""
    raw = fzf_key.strip().lower()
    if raw in _SPECIAL_KEY_DISPLAY:
        return _SPECIAL_KEY_DISPLAY[raw]
    if raw.startswith("f") and raw[1:].isdigit():
        return raw.upper()
    if raw.startswith("alt-") and len(raw) > 4:
        tail = fzf_key.strip()[4:]
        return f"M-{tail}" if compact else f"Alt+{tail}"
    if raw.startswith("ctrl-") and len(raw) > 5:
        tail = fzf_key.strip()[5:]
        return f"C-{tail}" if compact else f"Ctrl+{tail}"
    return fzf_key.strip()


def pane_jump_mode_for_key(pressed: str) -> str | None:
    """Map a session-switcher pane-jump key (`ctrl-a/e/t` or `alt-a/e/t`) to its `toggle_main_pane` mode."""
    return PANE_JUMP_MODE_BY_KEY.get(pressed)


@dataclass(frozen=True)
class KeyAction:
    """Single source of truth for a Python TUI shortcut's labels, priority, and `fzf` bindings."""

    action_id: str
    full_label: str
    compact_label: str
    tiny_label: str
    priority_1p: int | None
    priority_2p: int | None
    fzf_expect_1p: tuple[str, ...] = ()
    fzf_expect_2p: tuple[str, ...] = ()
    fzf_keys: tuple[str, ...] = ()

    def label_for_width(self, pane_w: int) -> str:
        """Select the modifier-consistent label tier for `pane_w`."""
        if pane_w >= 58:
            return self.full_label
        if pane_w >= 54:
            return self.compact_label
        return self.tiny_label


SWITCHER_SESSION_ACTIONS: tuple[KeyAction, ...] = (
    KeyAction(
        action_id="switch",
        full_label="Enter: switch",
        compact_label="Enter: switch",
        tiny_label="Enter: go",
        priority_1p=0,
        priority_2p=0,
        fzf_keys=("enter",),
    ),
    KeyAction(
        action_id="focus_ai",
        full_label="Alt+l: AI",
        compact_label="M-l: AI",
        tiny_label="M-l: AI",
        priority_1p=None,
        priority_2p=1,
        fzf_keys=(SWITCHER_FOCUS_AI_KEY,),
    ),
    KeyAction(
        action_id="select",
        full_label="Tab: select",
        compact_label="Tab: sel",
        tiny_label="Tab: sel",
        priority_1p=10,
        priority_2p=11,
        fzf_keys=("tab",),
    ),
    KeyAction(
        action_id="pane",
        full_label="Ctrl+a/e/t: pane",
        compact_label="C-a/e/t: pane",
        tiny_label="C-a/e/t: pane",
        priority_1p=8,
        priority_2p=12,
        fzf_expect_1p=tuple(PANE_JUMP_MODE_BY_KEY.keys()),
        fzf_expect_2p=("ctrl-a", "ctrl-e", "ctrl-t"),
    ),
    KeyAction(
        action_id="ack",
        full_label="Ctrl+y: ack",
        compact_label="C-y: ack",
        tiny_label="C-y: ack",
        priority_1p=3,
        priority_2p=4,
        fzf_keys=("ctrl-y",),
    ),
    KeyAction(
        action_id="pr",
        full_label="Ctrl+o: PR",
        compact_label="C-o: PR",
        tiny_label="C-o: PR",
        priority_1p=9,
        priority_2p=9,
        fzf_keys=("ctrl-o",),
    ),
    KeyAction(
        action_id="new",
        full_label="Alt+n: new",
        compact_label="M-n: new",
        tiny_label="M-n: new",
        priority_1p=4,
        priority_2p=5,
        fzf_expect_1p=(DIR_PICKER_FLIP_NEW_KEY,),
        fzf_expect_2p=(DIR_PICKER_FLIP_NEW_KEY,),
    ),
    KeyAction(
        action_id="open",
        full_label="Alt+o: open",
        compact_label="M-o: open",
        tiny_label="M-o: open",
        priority_1p=5,
        priority_2p=6,
        fzf_expect_1p=(CREATE_WS_FLIP_OPEN_KEY,),
        fzf_expect_2p=(CREATE_WS_FLIP_OPEN_KEY,),
    ),
    KeyAction(
        action_id="agent",
        full_label="Alt+r: agent",
        compact_label="M-r: agent",
        tiny_label="M-r: agent",
        priority_1p=7,
        priority_2p=8,
        fzf_expect_1p=(AGENT_MODAL_KEY,),
        fzf_expect_2p=(AGENT_MODAL_KEY,),
    ),
    KeyAction(
        action_id="quit",
        full_label="Ctrl+x: quit",
        compact_label="C-x: quit",
        tiny_label="C-x: quit",
        priority_1p=6,
        priority_2p=7,
        fzf_keys=("ctrl-x",),
    ),
    KeyAction(
        action_id="reload",
        full_label="Ctrl+r/F5: reload",
        compact_label="C-r/F5: reload",
        tiny_label="F5: sync",
        priority_1p=11,
        priority_2p=10,
        fzf_keys=("ctrl-r", "f5"),
    ),
    KeyAction(
        action_id="help",
        full_label="F1: help",
        compact_label="F1: help",
        tiny_label="F1: ?",
        priority_1p=2,
        priority_2p=3,
        fzf_keys=("f1", "alt-?"),
    ),
    KeyAction(
        action_id="close",
        full_label="Alt+w: close",
        compact_label="M-w: close",
        tiny_label="M-w: close",
        priority_1p=1,
        priority_2p=2,
        fzf_keys=(SWITCHER_ABORT_KEY,),
    ),
)

ACTION_BY_ID: dict[str, KeyAction] = {act.action_id: act for act in SWITCHER_SESSION_ACTIONS}

ALL_SESSION_EXPECT_KEYS: frozenset[str] = frozenset(
    {"", "enter"}
    | {k for act in SWITCHER_SESSION_ACTIONS for k in act.fzf_expect_1p}
    | {k for act in SWITCHER_SESSION_ACTIONS for k in act.fzf_expect_2p}
)

NO_MATCH_LAUNCHER_EXPECT_KEYS: frozenset[str] = frozenset(
    k
    for act in SWITCHER_SESSION_ACTIONS
    if act.action_id in ("new", "open")
    for k in act.fzf_expect_2p
)


def build_action_fzf_binds(action_id: str, rhs: str) -> list[str]:
    """Build `--bind=<key>:<rhs>` flags for every `fzf_keys` chord registered on `action_id`."""
    return [f"--bind={k}:{rhs}" for k in ACTION_BY_ID[action_id].fzf_keys]


def sessions_expect_spec(in_two_pane: bool) -> str:
    """Return comma-separated `fzf --expect=...` key list for 1-pane or 2-pane session switcher."""
    keys: list[str] = []
    for act in SWITCHER_SESSION_ACTIONS:
        seq = act.fzf_expect_2p if in_two_pane else act.fzf_expect_1p
        for k in seq:
            if k not in keys:
                keys.append(k)
    return ",".join(keys)


def format_sessions_footer_label(
    pane_w: int = 120,
    in_two_pane: bool = False,
    sep: str = " · ",
) -> str:
    """Pack separator-joined key hints within `pane_w` using uniform modifier notation per width tier."""
    if 0 < pane_w < 5:
        return ""
    eff_w = pane_w if pane_w > 0 else 120
    active: list[tuple[int, int, KeyAction]] = []
    for idx, act in enumerate(SWITCHER_SESSION_ACTIONS):
        pri = act.priority_2p if in_two_pane else act.priority_1p
        if pri is not None:
            active.append((pri, idx, act))

    by_pri = sorted(active, key=lambda item: item[0])
    budget = min(eff_w - 2, max(4, eff_w - 4))
    chosen_orders: set[int] = set()
    label_by_order = {idx: act.label_for_width(eff_w) for _, idx, act in active}

    for _, order_idx, _ in by_pri:
        cand_orders = sorted([*chosen_orders, order_idx])
        cand_str = " " + sep.join(label_by_order[i] for i in cand_orders) + " "
        if visible_width(cand_str) <= budget or not chosen_orders:
            chosen_orders.add(order_idx)

    joined = sep.join(label_by_order[i] for i in sorted(chosen_orders))
    out = f" {joined} "
    if visible_width(out) > budget:
        return f" {trunc_visible(joined, max(1, budget - 2), suffix=_trunc_sfx(sep))} "
    return out


def switcher_pane_border_hints(sep: str = " · ") -> tuple[str, str, str, str, str]:
    """Return `(sessions_active, sessions_inactive, live_full, live_short, preview_full)` top-border hints."""
    ai_ch = fzf_key_to_display_chord(SWITCHER_FOCUS_AI_KEY)
    list_ch = fzf_key_to_display_chord(SWITCHER_FOCUS_LIST_KEY)
    close_ch = fzf_key_to_display_chord(SWITCHER_ABORT_KEY)
    return (
        f"({ai_ch}: interact)",
        f"({list_ch}: list)",
        f"({list_ch}: list{sep}{close_ch}: close)",
        f"({list_ch})",
        f"({ai_ch} / click: interact)",
    )


def switcher_submodal_hint(
    mode: str,
    *,
    allow_flip: bool = True,
    back_to_sessions: bool = True,
    sep: str = " · ",
) -> str:
    """Return context-accurate top-border hint for zoomed `ai-sw-*` sub-modals (`new`, `dir`, `agent`)."""
    esc = "Esc: back" if back_to_sessions else "Esc: cancel"
    if mode == "new" and allow_flip:
        open_ch = fzf_key_to_display_chord(CREATE_WS_FLIP_OPEN_KEY)
        return f"({open_ch}: open{sep}{esc})"
    if mode == "dir" and allow_flip:
        new_ch = fzf_key_to_display_chord(DIR_PICKER_FLIP_NEW_KEY)
        return f"({new_ch}: new{sep}{esc})"
    return f"({esc})"


def format_dir_picker_footer(
    cols: int,
    back_to_sessions: bool,
    allow_flip_new: bool = True,
    sep: str = " · ",
) -> str:
    """Pack bottom `--border-label` hints for `Open IDE >` within `cols`, honoring `allow_flip_new`."""
    if 0 < cols < 5:
        return ""
    full_esc = "Esc: back to sessions" if back_to_sessions else "Esc: cancel"
    short_esc = "Esc: back" if back_to_sessions else "Esc: cancel"
    new_ch = fzf_key_to_display_chord(DIR_PICKER_FLIP_NEW_KEY)
    if allow_flip_new:
        candidates: tuple[str, ...] = (
            f" Enter: launch{sep}{new_ch}: new{sep}{full_esc} ",
            f" Enter: launch{sep}{new_ch}: new{sep}{short_esc} ",
            f" Enter: launch{sep}{short_esc} ",
            f" Enter{sep}{new_ch}{sep}Esc ",
            f" Enter{sep}Esc ",
        )
    else:
        candidates = (
            f" Enter: launch{sep}{full_esc} ",
            f" Enter: launch{sep}{short_esc} ",
            f" Enter{sep}Esc ",
        )
    budget = min(cols - 2, max(4, cols - 4)) if cols > 0 else 116
    for cand in candidates:
        if visible_width(cand) <= budget:
            return cand
    fallback = f"Enter{sep}Esc"
    return f" {trunc_visible(fallback, max(1, budget - 2), suffix=_trunc_sfx(sep))} "


def create_workspace_footer_hints(*, allow_flip_open: bool, back_label: str) -> list[str]:
    """Return ordered bottom-border hints for `New IDE Workspace` (`Alt+n`)."""
    esc_short = "back" if back_label.startswith("back") else back_label
    open_ch = fzf_key_to_display_chord(CREATE_WS_FLIP_OPEN_KEY)
    layout_ch = fzf_key_to_display_chord(CREATE_WS_LAYOUT_KEY)
    hints = ["Enter: create", "Tab: agent"]
    if allow_flip_open:
        hints.append(f"{open_ch}: open")
    hints.append(f"{layout_ch}: layout")
    hints.append(f"Esc: {esc_short}")
    return hints


def agent_picker_footer_hints(*, back_label: str, num_options: int = 3) -> list[str]:
    """Return ordered bottom-border hints for `AI Agent` (`Alt+r` / `ide agent`)."""
    esc_short = "back" if back_label.startswith("back") else back_label
    num_part = f"1-{num_options}" if num_options > 1 else "1"
    return [f"Enter/{num_part}: apply", "j/k/Tab: select", f"Esc: {esc_short}"]


def format_card_footer(hints: list[str], inner_w: int, sep: str = " · ") -> str:
    """Pack dialog card footer hints within `inner_w`, keeping primary confirm and `Esc` visible."""
    if not hints or (0 < inner_w < 4):
        return ""
    if inner_w <= 0:
        budget = 116
    elif inner_w == 4:
        budget = 3
    elif inner_w < 14:
        budget = inner_w - 2
    else:
        budget = inner_w - 4
    n = len(hints)
    pri_order = list(range(n)) if n <= 2 else [0, n - 1, *range(1, n - 1)]
    chosen_idxs: set[int] = set()
    for idx in pri_order:
        cand_idxs = sorted([*chosen_idxs, idx])
        cand = " " + sep.join(hints[i] for i in cand_idxs) + " "
        if visible_width(cand) <= budget or not chosen_idxs:
            chosen_idxs.add(idx)
    joined = sep.join(hints[i] for i in sorted(chosen_idxs))
    out = f" {joined} "
    if visible_width(out) > budget:
        return f" {trunc_visible(joined, max(1, budget - 2), suffix=_trunc_sfx(sep))} "
    return out


def topbar_tab_suffix_widths(
    *,
    compact_tabs: bool,
    role: str,
    ai_parked: bool,
    ed_parked: bool,
    term_parked: bool,
) -> tuple[int, int, int, int]:
    """Return `(ai_sfx, ed_sfx, term_sfx, zoom_w)` matching `dotfiles/.tmux.conf` `@ide_tab_*` formatting."""
    ai_focus, _, ai_badge = TOPBAR_ROLE_SPECS["ai"]
    ed_focus, _, ed_badge = TOPBAR_ROLE_SPECS["editor"]
    tm_focus, _, tm_badge = TOPBAR_ROLE_SPECS["term"]
    if compact_tabs:
        ai_sfx = len(f" [{ai_badge}]") if (role != "ai" and ai_parked) else 0
        ed_sfx = len(f" [{ed_badge}]") if (role != "editor" and ed_parked) else 0
        term_sfx = len(f" [{tm_badge}] ") if (role != "term" and term_parked) else 1
        zoom_w = visible_width("󰁌 ZOOM ")
    else:
        ai_sfx = len(f" ({ai_focus})")
        ed_sfx = len(f" ({ed_focus})")
        term_sfx = len(f" ({tm_focus}) ")
        zoom_w = visible_width(f"󰁌 ZOOM ({TOPBAR_ZOOM_CHORD}) ")
    return (ai_sfx, ed_sfx, term_sfx, zoom_w)
