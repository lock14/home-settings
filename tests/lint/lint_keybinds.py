#!/usr/bin/env python3
"""Cross-layer keybinding, TUI footer, theme artifact, and cheatsheet parity linter."""

from __future__ import annotations

from contextlib import contextmanager
import glob
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

TYPE_CHECKING = False
if TYPE_CHECKING:
    from collections.abc import Callable, Iterator
    from types import ModuleType

GHOSTTY_REQUIRED_KEYBINDS: tuple[str, ...] = (
    "keybind = ctrl+shift+d=new_split:auto",
    "keybind = ctrl+shift+w=close_surface",
    "keybind = ctrl+shift+enter=toggle_split_zoom",
    "keybind = ctrl+shift+h=goto_split:left",
    "keybind = ctrl+shift+j=goto_split:bottom",
    "keybind = ctrl+shift+k=goto_split:top",
    "keybind = ctrl+shift+l=goto_split:right",
    "keybind = ctrl+shift+t=new_tab",
    r"keybind = alt+left=text:\x1b[1;3D",
    r"keybind = alt+right=text:\x1b[1;3C",
    r"keybind = alt+up=text:\x1b[1;3A",
    r"keybind = alt+down=text:\x1b[1;3B",
    r"keybind = alt+shift+left=text:\x1b[1;4D",
    r"keybind = alt+shift+right=text:\x1b[1;4C",
    r"keybind = alt+shift+up=text:\x1b[1;4A",
    r"keybind = alt+shift+down=text:\x1b[1;4B",
)

FORBIDDEN_TMUX_ROOT_BINDS: tuple[str, ...] = (
    "C-h",
    "C-j",
    "C-k",
    "C-l",
    "M-1",
    "M-2",
    "M-3",
    "M-s",
    "M-S",
    "M-m",
    "M-Left",
    "M-Down",
    "M-Up",
    "M-Right",
    "WheelUpStatus",
    "WheelDownStatus",
)

FORBIDDEN_TMUX_COPY_BINDS: tuple[str, ...] = (
    "M-s",
    "M-S",
    "M-m",
    "M-Left",
    "M-Down",
    "M-Up",
    "M-Right",
)

EXPECTED_TMUX_PREFIX_BINDS: tuple[str, ...] = (
    "H", "J", "K", "L", "|", "-", "b", "?", "r", "v", "w", "s", "W", "S", "m", "q", "a",
)

CHEATSHEET_NVIM_LEADERS: tuple[str, ...] = (
    "Space ff", "Space fg", "Space gs", "Space a", "Space A",
    "Space t", "Space m", "Space e", "Space E",
    "Space il", "Space if", "Space ia", "Space id",
)

_SGR_RE = re.compile(r"\x1b\[[0-9;]*m")
_FORBIDDEN_CHEATSHEET_MOD_RE = re.compile(
    r"(?<![A-Za-z0-9])(M-[A-Za-z?]|C-[a-z]|Pfx\+|Alt\+S-|Prefix \+ )"
)


def _is_target_pkg(mod_name: str) -> bool:
    return (
        mod_name == "ide_lib"
        or mod_name.startswith("ide_lib.")
        or mod_name == "theme_lib"
        or mod_name.startswith("theme_lib.")
    )


@contextmanager
def _isolated_libexec_env(libexec_dir: Path) -> Iterator[None]:
    """Load `ide_lib` and `theme_lib` from `libexec_dir` under deterministic env without leaking `sys.path` or `sys.modules`."""
    saved_path = list(sys.path)
    saved_env = os.environ.copy()
    target_prefix = str(libexec_dir.resolve())
    prior_mods: dict[str, ModuleType] = {
        mod_name: mod_obj
        for mod_name, mod_obj in sys.modules.items()
        if _is_target_pkg(mod_name)
    }

    for mod_name, mod_obj in list(prior_mods.items()):
        mod_file = getattr(mod_obj, "__file__", "") or ""
        try:
            same_tree = bool(mod_file) and str(Path(mod_file).resolve()).startswith(target_prefix + os.sep)
        except OSError:
            same_tree = False
        if not same_tree:
            sys.modules.pop(mod_name, None)

    sys.path.insert(0, target_prefix)
    os.environ["TERM"] = "xterm-256color"
    os.environ["COLORTERM"] = "truecolor"
    os.environ.pop("NO_COLOR", None)
    os.environ.pop("IDE_ASCII", None)
    os.environ["IDE_NERD_FONTS"] = "1"
    try:
        yield
    finally:
        for mod_name in list(sys.modules):
            if _is_target_pkg(mod_name) and mod_name not in prior_mods:
                sys.modules.pop(mod_name, None)
        sys.modules.update(prior_mods)
        sys.path[:] = saved_path
        os.environ.clear()
        os.environ.update(saved_env)


def _extract_ide_show_usage(ide_text: str) -> str | None:
    m = re.search(
        r"show_usage\(\)\s*\{\s*cat <<'EOF'\n(.*?)\nEOF\s*\}",
        ide_text,
        flags=re.DOTALL,
    )
    return m.group(1) if m else None


def _has_mixed_modifiers(label: str) -> bool:
    has_full = ("Alt+" in label) or ("Ctrl+" in label)
    has_compact = bool(re.search(r"(?<![A-Za-z0-9])(M-|C-)", label))
    return has_full and has_compact


def _tmux_chord_to_binding(chord: str) -> tuple[str, str] | None:
    if chord.startswith("Prefix+"):
        key = chord[len("Prefix+"):]
        return ("prefix", key) if key else None
    if chord.startswith("Alt+Shift+"):
        rest = chord[len("Alt+Shift+"):]
        if len(rest) == 1 and rest.isalpha():
            return ("root", f"M-{rest.upper()}")
        if rest in ("Left", "Right", "Up", "Down"):
            return ("root", f"M-S-{rest}")
        return None
    if chord.startswith("Alt+"):
        rest = chord[len("Alt+"):]
        if len(rest) == 1 or rest in ("Left", "Right", "Up", "Down"):
            return ("root", f"M-{rest}")
        return None
    return None


def _check_cli_usage_parity(ide_path: Path, ide_text: str, usage_text: str, errors: list[str]) -> None:
    ide_usage = _extract_ide_show_usage(ide_text)
    if ide_usage is None:
        errors.append(f"{ide_path}: could not extract show_usage() heredoc")
    elif ide_usage != usage_text.rstrip("\n"):
        errors.append(
            f"{ide_path}: show_usage() heredoc drifted from libexec/ide_lib/constants.py USAGE_TEXT"
        )


def _check_theme_artifact_dedup(
    root: Path,
    sample_theme: dict[str, str],
    generate_tmux_theme_text: Callable[[dict[str, str]], str],
    generate_ghostty_config_text: Callable[[dict[str, str]], str],
    errors: list[str],
) -> None:
    tmux_gen = generate_tmux_theme_text(sample_theme)
    if not tmux_gen.startswith("# tmux-theme-v2\n"):
        errors.append("libexec/theme_lib/generators.py: generate_tmux_theme_text() missing '# tmux-theme-v2' header")
    for forbidden_tok in ("@ide_tab_", "window-status-current-format", "window-status-format", "status-right"):
        if forbidden_tok in tmux_gen:
            errors.append(
                f"libexec/theme_lib/generators.py: generate_tmux_theme_text() must not duplicate '{forbidden_tok}'"
            )

    ghostty_cfg_path = root / "dotfiles" / ".config" / "ghostty" / "config"
    ghostty_kb_path = root / "dotfiles" / ".config" / "ghostty" / "keybinds.conf"
    if not ghostty_cfg_path.is_file():
        errors.append(f"{ghostty_cfg_path}: missing Ghostty config")
    else:
        gcfg_lines = ghostty_cfg_path.read_text(encoding="utf-8").splitlines()
        if "config-file = keybinds.conf" not in gcfg_lines:
            errors.append(f"{ghostty_cfg_path}: missing 'config-file = keybinds.conf'")
        if any(ln.strip().startswith("keybind") for ln in gcfg_lines):
            errors.append(f"{ghostty_cfg_path}: inline 'keybind =' found; place all keybinds in keybinds.conf")

    if not ghostty_kb_path.is_file():
        errors.append(f"{ghostty_kb_path}: missing Ghostty keybinds.conf")
    else:
        gkb_lines = {
            ln.strip()
            for ln in ghostty_kb_path.read_text(encoding="utf-8").splitlines()
            if ln.strip().startswith("keybind")
        }
        for req_kb in GHOSTTY_REQUIRED_KEYBINDS:
            if req_kb not in gkb_lines:
                errors.append(f"{ghostty_kb_path}: missing required directive '{req_kb}'")

    ghostty_gen_lines = generate_ghostty_config_text(sample_theme).splitlines()
    if "config-file = keybinds.conf" not in ghostty_gen_lines:
        errors.append("libexec/theme_lib/generators.py: generate_ghostty_config_text() missing 'config-file = keybinds.conf'")
    if any(ln.strip().startswith("keybind") for ln in ghostty_gen_lines):
        errors.append("libexec/theme_lib/generators.py: generate_ghostty_config_text() must not inline 'keybind =' lines")

    reload_path = root / "libexec" / "theme_lib" / "reload.py"
    if not reload_path.is_file():
        errors.append(f"{reload_path}: missing reload.py")
    elif '"keybinds.conf"' not in reload_path.read_text(encoding="utf-8"):
        errors.append("libexec/theme_lib/reload.py: missing 'keybinds.conf' symlink materialization")


def _logical_tmux_lines(tmux_txt: str) -> list[str]:
    """Join backslash-continued lines in `dotfiles/.tmux.conf`, skipping comments and blank lines."""
    logical: list[str] = []
    buf = ""
    for raw_ln in tmux_txt.splitlines():
        stripped = raw_ln.strip()
        if not buf and (not stripped or stripped.startswith("#")):
            continue
        if raw_ln.endswith("\\") and not raw_ln.endswith("\\\\"):
            buf += raw_ln[:-1] + " "
            continue
        full = (buf + raw_ln).strip()
        buf = ""
        if full and not full.startswith("#"):
            logical.append(full)
    if buf.strip() and not buf.lstrip().startswith("#"):
        logical.append(buf.strip())
    return logical


def _parse_tmux_bind_tokens(ln: str) -> tuple[bool, str, str] | None:
    """Return `(is_unbind, table, key)` for a `tmux` `bind`/`unbind` directive, or `None`."""
    head = ln.split(None, 1)[0] if ln else ""
    if head not in ("bind", "bind-key", "unbind", "unbind-key"):
        return None
    try:
        tokens = shlex.split(ln, posix=True)
    except ValueError:
        tokens = ln.split()
    if len(tokens) < 2:
        return None
    is_unbind = tokens[0] in ("unbind", "unbind-key")
    table = "prefix"
    idx = 1
    while idx < len(tokens):
        tok = tokens[idx]
        if tok == "--":
            idx += 1
            break
        if tok == "-" or not tok.startswith("-"):
            break
        if tok in ("-T", "-N"):
            if tok == "-T" and idx + 1 < len(tokens):
                table = tokens[idx + 1]
            idx += 2
            continue
        flags = tok[1:]
        if flags and all(ch in ("n", "r", "e", "a", "q") for ch in flags):
            if "n" in flags:
                table = "root"
            idx += 1
            continue
        break
    if idx >= len(tokens):
        return None
    return (is_unbind, table, tokens[idx])


def _parse_label_fzf_keys(label: str) -> list[str]:
    """Parse the chord LHS of a `KeyAction` label (`Ctrl+a/e/t: pane`, `C-r/F5: reload`) into `fzf` key names."""
    lhs = label.split(":", 1)[0].strip()
    if not lhs:
        return []
    out: list[str] = []
    inherited_mod = ""
    for part in lhs.split("/"):
        tok = part.strip()
        if not tok:
            continue
        low = tok.lower()
        if low in ("enter", "tab", "esc", "escape", "space"):
            inherited_mod = ""
            out.append("esc" if low == "escape" else low)
        elif low.startswith("f") and low[1:].isdigit():
            inherited_mod = ""
            out.append(low)
        elif tok.startswith("Alt+") and len(tok) > 4:
            inherited_mod = "alt-"
            out.append(f"alt-{tok[4:].lower()}")
        elif tok.startswith("M-") and len(tok) > 2:
            inherited_mod = "alt-"
            out.append(f"alt-{tok[2:].lower()}")
        elif tok.startswith("Ctrl+") and len(tok) > 5:
            inherited_mod = "ctrl-"
            out.append(f"ctrl-{tok[5:].lower()}")
        elif tok.startswith("C-") and len(tok) > 2:
            inherited_mod = "ctrl-"
            out.append(f"ctrl-{tok[2:].lower()}")
        elif inherited_mod and len(tok) == 1:
            out.append(f"{inherited_mod}{tok.lower()}")
        else:
            out.append(low)
    return out


def _check_tmux_bindings_and_chrome(
    root: Path,
    topbar_specs: dict[str, tuple[str, str, str]],
    zoom_chord: str,
    errors: list[str],
) -> set[str]:
    tmux_conf_path = root / "dotfiles" / ".tmux.conf"
    if not tmux_conf_path.is_file():
        errors.append(f"{tmux_conf_path}: missing dotfiles/.tmux.conf")
        return set()
    tmux_txt = tmux_conf_path.read_text(encoding="utf-8")
    if "# tmux-theme-v2" not in tmux_txt:
        errors.append(f"{tmux_conf_path}: missing '# tmux-theme-v2' source-file guard")

    layout_path = root / "libexec" / "ide_lib" / "layout.py"
    if not layout_path.is_file():
        errors.append(f"{layout_path}: missing layout.py")
    elif '"#{T:status-left}"' not in layout_path.read_text(encoding="utf-8"):
        errors.append("libexec/ide_lib/layout.py: status_click must query '#{T:status-left}' so #{@hs_session_icon} expands")

    root_binds: set[str] = set()
    prefix_binds: set[str] = set()
    copy_binds: set[str] = set()
    root_unbinds: set[str] = set()
    copy_unbinds: set[str] = set()

    for logical_ln in _logical_tmux_lines(tmux_txt):
        parsed = _parse_tmux_bind_tokens(logical_ln)
        if parsed is None:
            continue
        is_unbind, table, key_name = parsed
        if is_unbind:
            if table == "root":
                root_unbinds.add(key_name)
            elif table == "copy-mode-vi":
                copy_unbinds.add(key_name)
        else:
            if table == "root":
                root_binds.add(key_name)
            elif table == "copy-mode-vi":
                copy_binds.add(key_name)
            elif table == "prefix":
                prefix_binds.add(key_name)

    for forbidden_root in FORBIDDEN_TMUX_ROOT_BINDS:
        if forbidden_root in root_binds:
            errors.append(f"{tmux_conf_path}: forbidden root binding 'bind -n {forbidden_root}'")
        if forbidden_root not in root_unbinds:
            errors.append(f"{tmux_conf_path}: missing explicit 'unbind -n {forbidden_root}' guard")

    for forbidden_copy in FORBIDDEN_TMUX_COPY_BINDS:
        if forbidden_copy in copy_binds:
            errors.append(f"{tmux_conf_path}: forbidden copy-mode-vi binding '{forbidden_copy}'")
        if forbidden_copy not in copy_unbinds:
            errors.append(f"{tmux_conf_path}: missing explicit 'unbind -T copy-mode-vi {forbidden_copy}' guard")

    for rk in sorted(root_binds):
        if rk.startswith("M-") and rk not in copy_binds:
            errors.append(
                f"{tmux_conf_path}: root binding '{rk}' missing matching 'bind -T copy-mode-vi {rk}' parity"
            )

    for role_key, (focus_ch, park_ch, badge_ch) in topbar_specs.items():
        tmux_focus = "M-" + focus_ch.split("+", 1)[1]
        tmux_park = "M-" + park_ch.split("+", 1)[1]
        if tmux_focus not in root_binds:
            errors.append(f"{tmux_conf_path}: top-bar {role_key} chord '{focus_ch}' lacks 'bind -n {tmux_focus}'")
        if tmux_park not in root_binds:
            errors.append(f"{tmux_conf_path}: top-bar {role_key} park chord '{park_ch}' lacks 'bind -n {tmux_park}'")
        if f"({focus_ch})" not in tmux_txt or f"[{park_ch}]" not in tmux_txt or f"[{badge_ch}]" not in tmux_txt:
            errors.append(f"{tmux_conf_path}: @ide_tab_* drifted from TOPBAR_ROLE_SPECS[{role_key!r}]")

    zoom_tmux = "M-" + zoom_chord.split("+", 1)[1]
    if zoom_tmux not in root_binds or f"({zoom_chord})" not in tmux_txt:
        errors.append(f"{tmux_conf_path}: zoom pill chord '{zoom_chord}' drifted from root binds")

    non_comment_tmux = "\n".join(_logical_tmux_lines(tmux_txt))
    for m_label in re.findall(r"[\(\[](Alt\+[^\)\]\s]+|Prefix\+[^\)\]\s]+)[\)\]]", non_comment_tmux):
        spec = _tmux_chord_to_binding(m_label)
        if spec is None:
            errors.append(f"{tmux_conf_path}: unrecognized advertised chord '{m_label}'")
            continue
        tbl, kname = spec
        active_set = root_binds if tbl == "root" else prefix_binds
        if kname not in active_set:
            errors.append(f"{tmux_conf_path}: advertised chord '{m_label}' has no active {tbl} binding '{kname}'")

    for pfx_k in EXPECTED_TMUX_PREFIX_BINDS:
        if pfx_k not in prefix_binds:
            errors.append(f"{tmux_conf_path}: expected prefix binding '{pfx_k}' missing")
    for cpy_k in ("a", "M-c", "Escape"):
        if cpy_k not in copy_binds:
            errors.append(f"{tmux_conf_path}: status-right COPY hint '{cpy_k}' missing from copy-mode-vi")
    return root_binds


def _check_python_tui_keymap(
    root: Path,
    sample_palette: dict[str, str],
    tmux_root_binds: set[str],
    errors: list[str],
) -> None:
    from ide_lib.constants import visible_width
    from ide_lib.keymap import (
        OPEN_DIR_PROMPT,
        SWITCHER_SESSION_ACTIONS,
        agent_picker_footer_hints,
        format_card_footer,
        format_dir_picker_footer,
        format_sessions_footer_label,
        pane_jump_mode_for_key,
        sessions_expect_spec,
        switcher_pane_border_hints,
        switcher_submodal_hint,
        ui_hint_sep,
    )
    from ide_lib.launcher import _decode_csi_u_or_mod_other
    from ide_lib.switcher import build_sessions_fzf_args

    for act in SWITCHER_SESSION_ACTIONS:
        bound_keys = set(act.fzf_keys) | set(act.fzf_expect_1p) | set(act.fzf_expect_2p)
        for attr_name in ("full_label", "compact_label", "tiny_label"):
            lbl = getattr(act, attr_name)
            if ":" not in lbl:
                errors.append(f"keymap.py: {act.action_id}.{attr_name} ({lbl!r}) missing ':' separator")
                continue
            parsed_keys = _parse_label_fzf_keys(lbl)
            if not parsed_keys:
                errors.append(f"keymap.py: {act.action_id}.{attr_name} ({lbl!r}) has no recognizable key chord")
            for pk in parsed_keys:
                if pk not in bound_keys:
                    errors.append(
                        f"keymap.py: {act.action_id}.{attr_name} ({lbl!r}) advertises '{pk}' not bound in {sorted(bound_keys)}"
                    )
        if re.search(r"(?<![A-Za-z0-9])(M-|C-)", act.full_label):
            errors.append(f"keymap.py: {act.action_id}.full_label ({act.full_label!r}) must use Alt+/Ctrl+ notation")
        for attr_name in ("compact_label", "tiny_label"):
            lbl = getattr(act, attr_name)
            if "Alt+" in lbl or "Ctrl+" in lbl:
                errors.append(f"keymap.py: {act.action_id}.{attr_name} ({lbl!r}) must use compact M-/C- notation")

    for in_2p in (False, True):
        for pw in (4, 6, 12, 20, 28, 36, 40, 46, 54, 58, 62, 80, 90, 120, 160, 190):
            ftr = format_sessions_footer_label(pane_w=pw, in_two_pane=in_2p)
            budget = 0 if pw < 5 else min(pw - 2, max(4, pw - 4))
            if visible_width(ftr) > budget:
                errors.append(f"keymap.py: footer overflowed budget at pane_w={pw}, 2p={in_2p}: {ftr!r}")
            if _has_mixed_modifiers(ftr):
                errors.append(f"keymap.py: mixed modifier notation at pane_w={pw}, 2p={in_2p}: {ftr!r}")
            if pw >= 36:
                for tok in ftr.strip().split(" · "):
                    if ":" not in tok:
                        errors.append(f"keymap.py: malformed footer token {tok!r} at pane_w={pw}, 2p={in_2p}")
            if pw >= 46 and "F1:" not in ftr:
                errors.append(f"keymap.py: F1 help dropped at pane_w={pw}, 2p={in_2p}: {ftr!r}")

    if ui_hint_sep({"TERM": "dumb"}) != " | " or ui_hint_sep({"IDE_ASCII": "1"}) != " | ":
        errors.append("keymap.py: ui_hint_sep() must degrade to ' | ' on monochrome/ASCII terminals")
    if ui_hint_sep({"TERM": "xterm-256color"}) != " · ":
        errors.append("keymap.py: ui_hint_sep() must return ' · ' on standard UTF-8 terminals")
    for iw in (3, 4, 5, 10):
        cftr = format_card_footer(["Enter: create", "Esc: cancel"], iw)
        max_card_ftr = 0 if iw < 4 else (iw - 1 if iw == 4 else iw - 2)
        if visible_width(cftr) > max_card_ftr:
            errors.append(f"keymap.py: format_card_footer() overflowed inner_w={iw} budget: {cftr!r}")
    if pane_jump_mode_for_key("ctrl-e") != "focus-editor" or pane_jump_mode_for_key("alt-t") != "focus-term":
        errors.append("keymap.py: pane_jump_mode_for_key() drifted from expected focus modes")

    if tmux_root_binds:
        for bdr_h in switcher_pane_border_hints():
            for bdr_ch in re.findall(r"Alt\+[^\)\]\s:/]+", bdr_h):
                bdr_spec = _tmux_chord_to_binding(bdr_ch)
                if bdr_spec is None or bdr_spec[1] not in tmux_root_binds:
                    errors.append(f"keymap.py: switcher border chord '{bdr_ch}' missing from .tmux.conf root binds")

    args_1p = "\n".join(build_sessions_fzf_args("fzf", "/bin/ide", "ws", sample_palette, True, sw_sess="", pane_w=120))
    args_2p = "\n".join(build_sessions_fzf_args("fzf", "/bin/ide", "ws", sample_palette, True, sw_sess="ai-sw-1-1", pane_w=62))
    if f"--expect={sessions_expect_spec(False)}" not in args_1p:
        errors.append("switcher.py: 1-pane --expect drifted from keymap.sessions_expect_spec(False)")
    if f"--expect={sessions_expect_spec(True)}" not in args_2p:
        errors.append("switcher.py: 2-pane --expect drifted from keymap.sessions_expect_spec(True)")
    for act in SWITCHER_SESSION_ACTIONS:
        for fk in act.fzf_keys:
            if fk in ("enter", "tab"):
                continue
            target_blob = args_2p if act.priority_1p is None else (args_1p + "\n" + args_2p)
            if f"--bind={fk}:" not in target_blob:
                errors.append(f"switcher.py: keymap action {act.action_id!r} fzf key {fk!r} not bound in build_sessions_fzf_args")

    if OPEN_DIR_PROMPT != "Open IDE > ":
        errors.append(f"keymap.py: expected OPEN_DIR_PROMPT == 'Open IDE > ', got {OPEN_DIR_PROMPT!r}")
    if "Alt+n" in format_dir_picker_footer(120, True, allow_flip_new=False):
        errors.append("keymap.py: format_dir_picker_footer(..., allow_flip_new=False) must omit unbound 'Alt+n'")
    if "Alt+o" not in switcher_submodal_hint("new", allow_flip=True) or "Alt+n" in switcher_submodal_hint("new", allow_flip=True):
        errors.append("keymap.py: switcher_submodal_hint('new') must advertise Alt+o without Alt+n")
    if "Alt+n" not in switcher_submodal_hint("dir", allow_flip=True) or "Alt+o" in switcher_submodal_hint("dir", allow_flip=True):
        errors.append("keymap.py: switcher_submodal_hint('dir') must advertise Alt+n without Alt+o")
    if "Alt+" in switcher_submodal_hint("agent", allow_flip=False):
        errors.append("keymap.py: switcher_submodal_hint('agent') must not advertise Alt+n/o")
    if "Enter/1-4: apply" not in agent_picker_footer_hints(back_label="cancel", num_options=4):
        errors.append("keymap.py: agent_picker_footer_hints(num_options=4) must reflect dynamic option count")

    if (
        _decode_csi_u_or_mod_other("111;3u") != ("alt-o", "")
        or _decode_csi_u_or_mod_other("50;3u") != ("alt-2", "")
        or _decode_csi_u_or_mod_other("27u") != ("esc", "")
        or _decode_csi_u_or_mod_other("9;2u") != ("shift-tab", "")
        or _decode_csi_u_or_mod_other("27;3;119~") != ("alt-w", "")
    ):
        errors.append("launcher.py: _decode_csi_u_or_mod_other() failed CSI-u / modifyOtherKeys decoding")

    switcher_path = root / "libexec" / "ide_lib" / "switcher.py"
    if switcher_path.is_file() and "switcher_pane_border_hints" not in switcher_path.read_text(encoding="utf-8"):
        errors.append("switcher.py: must derive pane-border-format hints via keymap.switcher_pane_border_hints()")

    launcher_path = root / "libexec" / "ide_lib" / "launcher.py"
    if launcher_path.is_file():
        launcher_txt = launcher_path.read_text(encoding="utf-8")
        for req_sym in ("CREATE_WS_FLIP_OPEN_KEY", "CREATE_WS_LAYOUT_KEY", "IDE_SWITCHER_SESSION"):
            if req_sym not in launcher_txt:
                errors.append(f"launcher.py: missing {req_sym} keymap/modal integration")
        for raw_dup in ('"alt-o"', '"alt-n"', '"alt-w"', '"alt-2"'):
            if raw_dup in launcher_txt:
                errors.append(f"launcher.py: hardcoded key literal {raw_dup} must come from keymap.py / generic Alt decoder")

    theme_prev_path = root / "libexec" / "theme_lib" / "preview.py"
    if theme_prev_path.is_file():
        tp_txt = theme_prev_path.read_text(encoding="utf-8")
        if "--border-label-pos=bottom" not in tp_txt or "resize:refresh-preview" not in tp_txt or "--header=" in tp_txt:
            errors.append("libexec/theme_lib/preview.py: theme picker must use bottom --border-label and resize:refresh-preview")

    bash_theme_path = root / "dotfiles" / ".config" / "shell" / "bash-theme-cli.sh"
    if bash_theme_path.is_file():
        bt_txt = bash_theme_path.read_text(encoding="utf-8")
        if "--border-label-pos=bottom" not in bt_txt or "resize:refresh-preview" not in bt_txt or "--header=" in bt_txt:
            errors.append("dotfiles/.config/shell/bash-theme-cli.sh: standalone theme picker must use bottom --border-label and resize:refresh-preview")

    bash_hist_path = root / "dotfiles" / ".config" / "shell" / "bash-history-drawer.sh"
    if bash_hist_path.is_file():
        bh_txt = bash_hist_path.read_text(encoding="utf-8")
        if "Enter/Tab: place, Esc: cancel" in bh_txt or '" Enter/Tab: place"' not in bh_txt:
            errors.append("dotfiles/.config/shell/bash-history-drawer.sh: history drawer must render bottom command-bar hints without comma separator")


def _check_editor_and_hooks_docs_parity(root: Path, errors: list[str]) -> set[str]:
    readme_path = root / "README.md"
    readme_txt = readme_path.read_text(encoding="utf-8") if readme_path.is_file() else ""
    readme_tables = "\n".join(ln for ln in readme_txt.splitlines() if ln.strip().startswith("|"))
    readme_prose = "\n".join(ln for ln in readme_txt.splitlines() if not ln.strip().startswith("|"))

    nvim_leader_set: set[str] = set()
    nvim_lua_files = sorted(
        glob.glob(str(root / "dotfiles" / ".config" / "nvim" / "lua" / "**" / "*.lua"), recursive=True)
    ) + sorted(glob.glob(str(root / "dotfiles" / ".config" / "nvim" / "ftplugin" / "*.lua")))
    for lf in nvim_lua_files:
        ltxt = "\n".join(
            ln for ln in Path(lf).read_text(encoding="utf-8").splitlines() if not ln.lstrip().startswith("--")
        )
        for suffix in re.findall(r"""['"]<leader>([^'"]+)['"]""", ltxt):
            lbl = f"Space {suffix}"
            nvim_leader_set.add(lbl)
            if lbl not in readme_prose or lbl not in readme_tables:
                errors.append(f"{lf}: Neovim leader mapping '{lbl}' missing dual representation in README.md")

    vimrc_path = root / "dotfiles" / ".vimrc"
    if vimrc_path.is_file():
        vtxt = vimrc_path.read_text(encoding="utf-8")
        for req_vim in ("<leader>w", "<leader>h", "<M-h>", "<M-j>", "<M-k>", "<M-l>", "<Home>"):
            if req_vim not in vtxt:
                errors.append(f"{vimrc_path}: portable .vimrc missing core mapping '{req_vim}'")

    hooks_sh = root / "setup" / "modules" / "75-ai-hooks.sh"
    if hooks_sh.is_file() and "alt+g" in hooks_sh.read_text(encoding="utf-8"):
        if "alt+g" not in readme_prose.lower() or "alt+g" not in readme_tables.lower():
            errors.append("setup/modules/75-ai-hooks.sh: 'alt+g' override missing dual representation in README.md")

    return nvim_leader_set


def _check_ide_keys_cheatsheet(
    ide_path: Path,
    visible_width_fn: Callable[[str], int],
    nvim_leader_set: set[str],
    errors: list[str],
) -> None:
    base_env = {
        **os.environ,
        "TMUX": "",
        "TMUX_PANE": "",
        "IDE_SWITCHER_SESSION": "",
        "IDE_KEYS_NO_WAIT": "1",
        "IDE_ASCII": "0",
        "TERM": "xterm-256color",
        "NO_COLOR": "1",
    }
    for style, max_lines, max_cols in (("spacious", 30, 104), ("compact", 22, 76)):
        for nf_val, expect_icon in (("1", True), ("0", False)):
            proc = subprocess.run(
                [str(ide_path), "keys"],
                env={**base_env, "IDE_KEYS_STYLE": style, "IDE_NERD_FONTS": nf_val},
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                errors.append(
                    f"bin/ide keys ({style}, nf={nf_val}): exited with status {proc.returncode}: {proc.stderr.strip()}"
                )
                continue
            lines = [_SGR_RE.sub("", ln) for ln in proc.stdout.splitlines()]
            if len(lines) > max_lines:
                errors.append(f"bin/ide keys ({style}, nf={nf_val}): {len(lines)} lines exceeds {max_lines}-line budget")
            for idx, ln in enumerate(lines, 1):
                vw = visible_width_fn(ln)
                if vw > max_cols:
                    errors.append(
                        f"bin/ide keys ({style}, nf={nf_val}) line {idx}: width {vw} exceeds {max_cols}-col budget: {ln!r}"
                    )
                if nf_val == "1":
                    bad_mod = _FORBIDDEN_CHEATSHEET_MOD_RE.search(ln)
                    if bad_mod:
                        errors.append(
                            f"bin/ide keys ({style}) line {idx}: non-uniform modifier '{bad_mod.group(1)}' in {ln!r}"
                        )
            joined = "\n".join(lines)
            if expect_icon and " " not in joined:
                errors.append(f"bin/ide keys ({style}): IDE_NERD_FONTS=1 stripped Nerd Font header icon")
            if not expect_icon and "" in joined:
                errors.append(f"bin/ide keys ({style}): IDE_NERD_FONTS=0 leaked Nerd Font header icon")
            if nf_val == "1":
                for req_phrase in ("Space gs / a / t", "Space a / A (Vis)", "Tab"):
                    if req_phrase not in joined:
                        errors.append(f"bin/ide keys ({style}): missing required entry {req_phrase!r}")
                if nvim_leader_set:
                    for req_ldr in CHEATSHEET_NVIM_LEADERS:
                        if req_ldr not in nvim_leader_set:
                            errors.append(f"bin/ide keys: cheatsheet advertises '{req_ldr}' not found in Neovim lua")


def lint_keybinds(root_dir: str) -> list[str]:
    """Validate cross-layer keybinding, artifact deduplication, and TUI label invariants."""
    errors: list[str] = []
    root = Path(root_dir).resolve()
    ide_path = root / "bin" / "ide"
    libexec_dir = root / "libexec"

    if not ide_path.is_file():
        errors.append(f"{ide_path}: missing bin/ide")
        return errors
    if not libexec_dir.is_dir():
        errors.append(f"{libexec_dir}: missing libexec directory")
        return errors

    ide_text = ide_path.read_text(encoding="utf-8")

    with _isolated_libexec_env(libexec_dir):
        from ide_lib.constants import USAGE_TEXT, visible_width
        from ide_lib.keymap import TOPBAR_ROLE_SPECS, TOPBAR_ZOOM_CHORD
        from theme_lib.generators import generate_ghostty_config_text, generate_tmux_theme_text
        from theme_lib.palette import SOLARIZED_DARK_DEFAULTS

        sample_theme = dict(SOLARIZED_DARK_DEFAULTS)
        _check_cli_usage_parity(ide_path, ide_text, USAGE_TEXT, errors)
        _check_theme_artifact_dedup(
            root, sample_theme, generate_tmux_theme_text, generate_ghostty_config_text, errors
        )
        tmux_root_binds = _check_tmux_bindings_and_chrome(
            root, TOPBAR_ROLE_SPECS, TOPBAR_ZOOM_CHORD, errors
        )
        _check_python_tui_keymap(root, sample_theme, tmux_root_binds, errors)
        nvim_leader_set = _check_editor_and_hooks_docs_parity(root, errors)
        _check_ide_keys_cheatsheet(ide_path, visible_width, nvim_leader_set, errors)

    return errors


def main() -> int:
    if not getattr(sys, "pycache_prefix", None):
        sys.dont_write_bytecode = True
    target = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    errs = lint_keybinds(target)
    if errs:
        for e in errs:
            print(f"Keybind lint error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
