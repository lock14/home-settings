"""Workspace file lookup, OSC 8 / wrapped URL link router, and AI prompt context dispatch."""

from __future__ import annotations

import os
import re
import subprocess
import sys

from ide_lib.constants import (
    TMUX_SEP,
    TMUX_WORD_SEPS,
    _SGR_RE,
    is_live_socket,
    is_switcher_session_name,
    safe_getcwd,
    which_executable,
)
from ide_lib.git_info import locate_git_dirs
from ide_lib.hooks import call_ide_hook
from ide_lib.nvim_rpc import (
    ensure_editor_nvim_running,
    ensure_session_editor_socket,
    nvim_remote_expr,
    nvim_remote_file,
    resolve_nvim_bin,
    wait_for_editor_socket,
)
from ide_lib.proc import pane_has_child_procs
from ide_lib.tmux import (
    current_ide_session,
    get_ide_var,
    missing_session_msg,
    normalize_pane_cwd,
    open_browser_url,
    pane_exists,
    pane_is_parked,
    resolve_main_win,
    resolve_role_pane,
    resolve_switcher_context,
    resolve_target_session,
    run_tmux,
    session_exists,
    tmux_out,
)

_RE_FILE_URI = re.compile(r"(file://[^()\s\]>\"'`\\]+(?:\([^()\s\]>\"'`\\]*\)[^()\s\]>\"'`\\]*)*)")
_RE_SCHEME = re.compile(r"(?:https?|file)://[A-Za-z0-9\-._~:/?#@!$&*+,;=%]+")
_WRAP_REF_RE = re.compile(r"(?:(?:https?|file):)?//[A-Za-z0-9\-._~:/?#@!$&*+,;=%]+")
_RE_LINE_COL = re.compile(r"^(.+?):[Ll]?([0-9]+)(:[0-9]+)?(-[Ll]?[0-9]+(:[0-9]+)?)?$")
_RE_HASH_LINE = re.compile(r"^(.+)#[Ll]?([0-9]+)(?::[0-9]+)?(?:[-:][Ll]?[0-9]+(?::[0-9]+)?)?$")
_RE_MD_LABEL = re.compile(r"\[(`[^`\r\n]+`|[^\[\]\r\n]+(?:\[[^\[\]\r\n]*\][^\[\]\r\n]*)*)\]\(")
_RE_MD_LINK = re.compile(
    r"\[(?:`[^`\r\n]+`|[^\[\]\r\n]*(?:\[[^\[\]\r\n]*\][^\[\]\r\n]*)*)\]\(([^()\s]+(?:\([^()\s]*\)[^()\s]*)*)\)"
)
_RE_MD_DEST_TAIL = re.compile(r"^[^(\[\s]*\]\(([^()\s]+(?:\([^()\s]*\)[^()\s]*)*)\)")
_RE_TOOL_CALL = re.compile(r"^(Read|Edit|Write|View|Update|Create|Bash)\((.+)$")
_RE_PCT_ENC = re.compile(r"%[0-9A-Fa-f]{2}")
_RE_FRAG_ID = re.compile(r"^[A-Za-z0-9_.:-]+$")

_URL_CHARS_RE = re.compile(r"^[A-Za-z0-9\-._~:/?#@!$&*+,;=%]+$")
_URL_TAIL_RE = re.compile(r"((?:(?:https?|file):)?//[A-Za-z0-9\-._~:/?#@!$&*+,;=%]+)[)\]>\"'`,;.]*$")

_SPLIT_OSC8_RE = re.compile(
    r"\x1b\]8;[^;\x1b]*;([^\x1b\r\n]+)\x1b\\([^\x1b\r\n]+)\x1b\]8;;\x1b\\([()\[\]{}<>\"'`,;*]*[^\x1b\s()\[\]{}<>\"'`,;*]+)"
)
_SUFFIX_OSC8_RE = re.compile(
    r"([^\x1b\s()\[\]{}<>\"'`,;*]+)\x1b\]8;[^;\x1b]*;([^\x1b\r\n\x07]+)(?:\x1b\\|\x07)([^\x1b\s()\[\]{}<>\"'`,;*]+)\x1b\]8;;(?:\x1b\\|\x07)"
)
_CONT_LINE_RE = re.compile(r"^[ \t]*\r?\n[ \t]*([^\x1b\s()\[\]{}<>\"'`,;*]+)")

_SEND_REF_SPEC_RE = re.compile(r"^(.*?)(?:[:#][Ll]?([0-9]+)(?:-[Ll]?([0-9]+))?)?$")
_BRACKETED_PASTE_ESC_RE = re.compile(r"(?:\x1b\[|\x9b)20[01]~")

_SKIP_WORKSPACE_SCAN_DIRS = frozenset({".git", ".hg", ".jj", ".svn", "node_modules", "__pycache__"})
_MAX_WORKSPACE_SCAN_ENTRIES = 128
_MAX_WORKSPACE_SCAN_DIRS = 128
_GIT_LS_TIMEOUT = 0.8


def _query_session_link_vars(sess: str, need_socket: bool = False) -> tuple[bool, str, str, str, str]:
    if not sess:
        return False, "", "", "", ""
    info = tmux_out(
        "display-message",
        "-p",
        "-t",
        f"={sess}:",
        f"#{{session_name}}{TMUX_SEP}#{{@ide_workdir}}{TMUX_SEP}#{{@ide_initial_root}}{TMUX_SEP}#{{@ide_socket}}{TMUX_SEP}#{{@ide_docked_in}}",
    )
    if TMUX_SEP not in info:
        if not session_exists(sess):
            return False, "", "", "", ""
        return (
            True,
            get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR"),
            get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT"),
            get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET") if need_socket else "",
            tmux_out("show-options", "-qv", "-t", f"={sess}:", "@ide_docked_in").strip(),
        )
    parts = info.split(TMUX_SEP)
    _, workdir, init_root, sock, docked_in = (parts + ["", "", "", "", ""])[:5]
    if not workdir:
        workdir = get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
    if not init_root:
        init_root = get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
    if need_socket and not sock:
        sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    return True, workdir, init_root, sock, docked_in.strip()


def _git_ls_files_unique_match(git_root: str, cand: str) -> str:
    if not which_executable("git"):
        return ""
    suffix = "/" + cand
    for args in (
        ["ls-files", "--cached"],
        ["ls-files", "--others", "--exclude-standard"],
    ):
        try:
            ls_res = subprocess.run(
                ["git", "-C", git_root, *args],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=_GIT_LS_TIMEOUT,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if ls_res.returncode != 0:
            continue
        matches: list[str] = []
        for rel in ls_res.stdout.splitlines():
            if rel == cand or rel.endswith(suffix):
                p = os.path.join(git_root, rel)
                if p not in matches and os.path.isfile(p):
                    matches.append(p)
                    if len(matches) > 1:
                        break
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            return ""
    return ""


def resolve_private_link(link_word: str, link_cwd: str, target_arg: str = "") -> str:
    """Resolve `link_word` through untracked `ide_resolve_link` hook if configured."""
    sess = ""
    if not os.environ.get("IDE_WORKDIR") or not os.environ.get("IDE_INITIAL_ROOT") or (link_cwd and not os.path.isdir(link_cwd)):
        sess = resolve_target_session(target_arg) if (os.environ.get("TMUX") or target_arg) else ""
        if sess and session_exists(sess):
            wdir = get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
            init_root = get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
            if wdir and not os.environ.get("IDE_WORKDIR"):
                os.environ["IDE_WORKDIR"] = wdir
            if init_root and not os.environ.get("IDE_INITIAL_ROOT"):
                os.environ["IDE_INITIAL_ROOT"] = init_root
    link_cwd = normalize_pane_cwd(link_cwd, sess=sess, target_arg=target_arg)
    return call_ide_hook("ide_resolve_link", link_word, link_cwd)


def parse_file_target(raw: str, cwd: str = "") -> tuple[str, str]:
    """Extract `(filepath, line_str)` from `file://`, `#L<N>`, or `:line[:col]` targets."""
    import urllib.parse

    def _exists(p: str) -> bool:
        if not p:
            return False
        if os.path.exists(p):
            return True
        if cwd and not p.startswith("/"):
            return os.path.exists(os.path.join(cwd, p))
        return False

    line = ""
    had_file_scheme = raw.startswith("file://")
    if had_file_scheme:
        raw = raw[7:]
        if raw.startswith("localhost/"):
            raw = raw[9:]
        elif not raw.startswith("/") and "/" in raw:
            raw = raw[raw.index("/"):]

    m_hash = _RE_HASH_LINE.match(raw)
    if m_hash:
        raw, line = m_hash.group(1), m_hash.group(2)
    elif "#" in os.path.basename(raw) and not _exists(raw) and not _exists(urllib.parse.unquote(raw)):
        base_raw, frag = raw.rsplit("#", 1)
        base_unq = urllib.parse.unquote(base_raw)
        if _exists(base_raw) or _exists(base_unq):
            raw = base_raw
        elif had_file_scheme and not _exists(urllib.parse.unquote(raw).rsplit(":", 1)[0]):
            raw = base_raw
        elif (
            os.path.splitext(base_unq)[1]
            and not os.path.splitext(frag.split(":", 1)[0])[1]
            and _RE_FRAG_ID.match(frag)
        ):
            raw = base_raw

    if not _exists(raw) and _RE_PCT_ENC.search(raw):
        raw = urllib.parse.unquote(raw)
        if not line and "#" in os.path.basename(raw) and not _exists(raw):
            m_hash2 = _RE_HASH_LINE.match(raw)
            if m_hash2:
                raw, line = m_hash2.group(1), m_hash2.group(2)

    if not line and not _exists(raw):
        m_col = _RE_LINE_COL.match(raw)
        if m_col:
            raw, line = m_col.group(1), m_col.group(2)

    if not _exists(raw) and _RE_PCT_ENC.search(raw):
        raw = urllib.parse.unquote(raw)
    return raw, line


def strip_token_wrappers(s: str) -> str:
    """Strip surrounding punctuation and balanced brackets around clicked terminal words."""
    s = s.lstrip("([{\"<'`")
    while s:
        if s.startswith("//") and s.endswith(("/...", "/..")):
            break
        if s[-1] in ">\"'`,;.:":
            s = s[:-1]
        elif s[-1] == ")" and s.count(")") > s.count("("):
            s = s[:-1]
        elif s[-1] == "]" and s.count("]") > s.count("["):
            s = s[:-1]
        elif s[-1] == "}" and s.count("}") > s.count("{"):
            s = s[:-1]
        else:
            break
    return s


def _direct_workspace_path(
    cand: str,
    cwd: str,
    workdir: str = "",
    init_root: str = "",
) -> str:
    if not cand or cand.startswith(("//", "file://")):
        return ""
    if cand.startswith("~/"):
        cand = os.path.expanduser(cand)
    if cand.startswith("/"):
        return cand if (os.path.isfile(cand) or os.path.isdir(cand)) else ""
    for base_dir in (cwd, workdir, init_root):
        if base_dir:
            full = os.path.join(base_dir, cand)
            if os.path.isfile(full) or os.path.isdir(full):
                return full
    return ""


def resolve_workspace_file(cand: str, cwd: str, target_arg: str) -> str:
    """Locate `cand` across `cwd`, `@ide_workdir`, `@ide_initial_root`, Git index, or bounded `os.scandir`."""
    if not cand:
        return ""
    if cand.startswith("~/"):
        cand = os.path.expanduser(cand)
    if cand.startswith("/"):
        return cand if (os.path.isfile(cand) or os.path.isdir(cand)) else ""

    sess = resolve_target_session(target_arg) if (os.environ.get("TMUX") or target_arg) else ""
    _, workdir, init_root, _, _ = _query_session_link_vars(sess)

    direct = _direct_workspace_path(cand, cwd, workdir, init_root)
    if direct:
        return direct

    seen_git_bases: set[str] = set()
    for base_dir in (cwd, workdir, init_root):
        if not base_dir or base_dir in seen_git_bases or not os.path.isdir(base_dir):
            continue
        seen_git_bases.add(base_dir)
        git_root, gitdir, _ = locate_git_dirs(base_dir)
        if not gitdir or not git_root:
            continue
        full = os.path.join(git_root, cand)
        if os.path.isfile(full) or os.path.isdir(full):
            return full
        if "/" in cand:
            stripped = cand.split("/", 1)[1]
            full2 = os.path.join(git_root, stripped)
            if os.path.isfile(full2) or os.path.isdir(full2):
                return full2
        git_match = _git_ls_files_unique_match(git_root, cand)
        if git_match:
            return git_match
        break

    cand_norm = os.path.normpath(cand.replace("\\", "/"))
    if cand_norm.startswith("..") or os.path.isabs(cand_norm):
        return ""
    parts = [p for p in cand_norm.split("/") if p and p != "."]
    if not parts:
        return ""
    first_seg = parts[0]
    rest_rel = os.path.join(*parts[1:]) if len(parts) > 1 else ""

    visited_dirs = 0
    seen_scan_bases: set[str] = set()
    for base_dir in (init_root, workdir, cwd):
        if not base_dir or base_dir in seen_scan_bases or not os.path.isdir(base_dir):
            continue
        seen_scan_bases.add(base_dir)
        if visited_dirs >= _MAX_WORKSPACE_SCAN_DIRS:
            break
        visited_dirs += 1
        root_entries = []
        root_capped = False
        try:
            with os.scandir(base_dir) as it:
                for entry in it:
                    if len(root_entries) >= _MAX_WORKSPACE_SCAN_ENTRIES:
                        root_capped = True
                        break
                    root_entries.append(entry)
        except OSError:
            continue
        if root_capped:
            continue

        cur_level: list[str] = []
        for entry in root_entries:
            if entry.name in _SKIP_WORKSPACE_SCAN_DIRS:
                continue
            try:
                if entry.is_dir():
                    cur_level.append(entry.path)
            except OSError:
                pass

        glob_matches: list[str] = []
        for depth in (1, 2, 3):
            if not cur_level or visited_dirs >= _MAX_WORKSPACE_SCAN_DIRS or len(glob_matches) > 1:
                break
            next_level: list[str] = []
            for d_path in cur_level:
                if visited_dirs >= _MAX_WORKSPACE_SCAN_DIRS:
                    break
                visited_dirs += 1
                d_entries = []
                d_capped = False
                try:
                    with os.scandir(d_path) as it:
                        for entry in it:
                            if len(d_entries) >= _MAX_WORKSPACE_SCAN_ENTRIES:
                                d_capped = True
                                break
                            d_entries.append(entry)
                except OSError:
                    continue
                for entry in d_entries:
                    if entry.name == first_seg:
                        if not rest_rel:
                            try:
                                if entry.is_file():
                                    glob_matches.append(entry.path)
                            except OSError:
                                pass
                        else:
                            try:
                                if entry.is_dir():
                                    cand_full = os.path.join(entry.path, rest_rel)
                                    if os.path.isfile(cand_full):
                                        glob_matches.append(cand_full)
                            except OSError:
                                pass
                        if len(glob_matches) > 1:
                            break
                    if not d_capped and depth < 3 and entry.name not in _SKIP_WORKSPACE_SCAN_DIRS:
                        try:
                            if entry.is_dir():
                                next_level.append(entry.path)
                        except OSError:
                            pass
                if len(glob_matches) > 1:
                    break
            cur_level = next_level

        if len(glob_matches) == 1:
            return glob_matches[0]
        break

    return ""


def open_in_editor(filepath: str, focus: bool, target_arg: str, line: str = "") -> int:
    """Open or preview `filepath` (at optional `line`) in the session's Main Neovim Editor via RPC."""
    from ide_lib.dock import close_switcher_session, pane_in_switcher_session, undock_switcher_session
    from ide_lib.layout import toggle_main_pane, unpark_role_pane

    sw_to_close = ""
    sw_client = ""
    sw_res_file = ""
    if is_switcher_session_name(target_arg):
        docked_s, sw_cl, sw_rf = resolve_switcher_context(target_arg)
        if not docked_s:
            return 0
        sw_to_close = target_arg
        sw_client = sw_cl
        sw_res_file = sw_rf
        target_arg = docked_s

    cwd = normalize_pane_cwd(safe_getcwd(), target_arg=target_arg)
    if filepath.startswith("~/"):
        filepath = os.path.expanduser(filepath)

    sess = resolve_target_session(target_arg)
    sess_ok, workdir, init_root, sock, docked_in = _query_session_link_vars(sess, need_socket=True)
    if not sess_ok:
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    if not sw_to_close and focus and is_switcher_session_name(docked_in) and pane_in_switcher_session(docked_in):
        _, sw_cl2, sw_rf2 = resolve_switcher_context(docked_in)
        sw_to_close = docked_in
        sw_client = sw_cl2
        sw_res_file = sw_rf2
        target_arg = sess

    if sw_to_close and focus:
        undock_switcher_session(sw_to_close)

    direct_match = _direct_workspace_path(filepath, cwd, workdir, init_root)
    if direct_match:
        filepath = direct_match
    else:
        private_url = resolve_private_link(filepath, cwd, target_arg)
        if private_url and private_url.startswith("file://"):
            p_path, p_line = parse_file_target(private_url, cwd)
            if p_path:
                filepath = p_path
                if not line and p_line:
                    line = p_line
        elif filepath.startswith("file://") or not os.path.exists(filepath):
            p_path, p_line = parse_file_target(filepath, cwd)
            if p_path:
                filepath = p_path
                if not line and p_line:
                    line = p_line

    if not filepath.startswith("/"):
        ws_resolved = (
            _direct_workspace_path(filepath, cwd, workdir, init_root)
            or resolve_workspace_file(filepath, cwd, target_arg)
        )
        if ws_resolved:
            d = os.path.dirname(ws_resolved) or "."
            b = os.path.basename(ws_resolved)
            filepath = os.path.join(os.path.realpath(d), b) if os.path.isdir(d) else ws_resolved
        else:
            d = os.path.dirname(filepath) or "."
            b = os.path.basename(filepath)
            if os.path.isdir(d):
                filepath = os.path.join(os.path.realpath(d), b)
            else:
                rel = filepath[2:] if filepath.startswith("./") else filepath
                filepath = os.path.join(cwd, rel)

    if not sock:
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        sock = f"{runtime_dir}/nvim-ide-{sess}.sock"
    prev_pane = "" if focus else tmux_out("display-message", "-p", "-t", f"={sess}:", "#{pane_id}")
    if focus:
        toggle_main_pane("focus-editor", target_arg, skip_checktime=True)
    else:
        editor_pane = resolve_role_pane(sess, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
        ai_pane = resolve_role_pane(sess, "ai", "@ide_ai_pane", "IDE_AI_PANE")
        term_pane = resolve_role_pane(sess, "term", "@ide_term_pane", "IDE_TERM_PANE")
        main_win = resolve_main_win(sess, editor_pane, ai_pane, term_pane)
        if pane_is_parked(editor_pane, main_win):
            unpark_role_pane(sess, "editor", main_win, ai_pane, editor_pane, term_pane, "")
            ensure_editor_nvim_running(editor_pane, sock, sess=sess)
        elif not pane_exists(editor_pane):
            toggle_main_pane("focus-editor", target_arg, skip_checktime=True)
        else:
            ensure_editor_nvim_running(editor_pane, sock, sess=sess)

    if resolve_nvim_bin():
        sock = wait_for_editor_socket(sess, sock)
    elif not sock:
        sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    if sock and is_live_socket(sock) and resolve_nvim_bin():
        ws_dir = (
            workdir
            or init_root
            or get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
            or get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
            or cwd
        )
        nvim_remote_file(sock, filepath, line, fallback_dir=ws_dir)
    if focus and sw_to_close:
        close_switcher_session(
            sw_to_close,
            action="switch",
            target=sess,
            pressed="",
            res_file_hint=sw_res_file,
        )
        if not sw_res_file and sw_client:
            run_tmux("switch-client", "-c", sw_client, "-t", f"={sess}")
    elif not focus and pane_exists(prev_pane):
        run_tmux("select-pane", "-t", prev_pane)
    return 0


def open_file_or_dir_target(fpath: str, line: str, target_arg: str) -> bool:
    """Open `fpath` in Editor if it is a file or dive into it if it is a directory."""
    if os.path.isfile(fpath):
        open_in_editor(fpath, True, target_arg, line)
        return True
    if os.path.isdir(fpath):
        from ide_lib.dock import caller_switcher_session, close_switcher_session, undock_switcher_session
        from ide_lib.layout import cd_ide_workspace

        sw_sess = caller_switcher_session(target_arg)
        if sw_sess:
            docked_s, sw_cl, sw_rf = resolve_switcher_context(sw_sess)
            if not docked_s:
                return False
            undock_switcher_session(sw_sess)
            cd_ide_workspace(fpath, docked_s)
            close_switcher_session(sw_sess, action="switch", target=docked_s, res_file_hint=sw_rf)
            if not sw_rf and sw_cl:
                run_tmux("switch-client", "-c", sw_cl, "-t", f"={docked_s}")
            return True
        cd_ide_workspace(fpath, target_arg)
        return True
    return False


def resolve_and_open_target(raw_target: str, cwd: str, target_arg: str, fallback_line: str = "") -> bool:
    """Parse `raw_target`, resolve across workspace roots, and open in Editor or dive."""
    parse_path, parse_line = parse_file_target(raw_target, cwd)
    if not parse_line and fallback_line:
        parse_line = fallback_line
    if not parse_path:
        return False
    if not parse_path.startswith("/") and not parse_path.startswith("~/"):
        resolved = resolve_workspace_file(parse_path, cwd, target_arg)
        if resolved:
            return open_file_or_dir_target(resolved, parse_line, target_arg)
        return open_file_or_dir_target(parse_path, parse_line, target_arg)
    if open_file_or_dir_target(parse_path, parse_line, target_arg):
        return True
    resolved = resolve_workspace_file(parse_path, cwd, target_arg)
    if resolved:
        return open_file_or_dir_target(resolved, parse_line, target_arg)
    return False


def _resolve_capture_pane_targets(target_arg: str = "") -> list[list[str]]:
    if not which_executable("tmux"):
        return []
    if not (os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or target_arg):
        return []
    if target_arg and target_arg.startswith("%"):
        return [["-t", target_arg]]
    sw_targets: list[list[str]] = []
    if is_switcher_session_name(target_arg):
        sw_rows = tmux_out(
            "list-panes",
            "-t",
            f"={target_arg}:",
            "-F",
            "#{pane_active}\t#{pane_id}\t#{@ide_sw_role}\t#{@ide_sw_placeholder}",
        ).splitlines()
        sw_active: list[list[str]] = []
        sw_other: list[list[str]] = []
        sw_placeholder: list[list[str]] = []
        for srow in sw_rows:
            sparts = (srow.split("\t") + ["", "", "", ""])[:4]
            s_act, s_pid, s_role, s_ph = sparts[0], sparts[1].strip(), sparts[2].strip(), sparts[3].strip()
            if not s_pid or s_role == "list":
                continue
            stgt = ["-t", s_pid]
            if s_ph == "1":
                if stgt not in sw_placeholder:
                    sw_placeholder.append(stgt)
                continue
            if s_act == "1":
                if stgt not in sw_active:
                    sw_active.append(stgt)
            elif stgt not in sw_other:
                sw_other.append(stgt)
        sw_targets = sw_active + sw_other
    else:
        sw_placeholder = []
    sess = resolve_target_session(target_arg)
    if sess:
        rows = tmux_out(
            "list-panes",
            "-s",
            "-t",
            f"={sess}:",
            "-F",
            "#{pane_active}\t#{pane_id}\t#{@ide_sw_placeholder}\t#{window_name}",
        ).splitlines()
        active_targets: list[list[str]] = []
        other_targets: list[list[str]] = []
        parked_targets: list[list[str]] = []
        for row in rows:
            if "\t" not in row:
                continue
            rparts = (row.split("\t") + ["", "", "", ""])[:4]
            is_active, pid, r_ph, r_wname = rparts[0], rparts[1].strip(), rparts[2].strip(), rparts[3].strip()
            if not pid or r_ph == "1":
                continue
            target = ["-t", pid]
            if r_wname.startswith("_ide_park_"):
                if target not in sw_targets and target not in parked_targets:
                    parked_targets.append(target)
                continue
            if is_active == "1":
                if target not in sw_targets and target not in active_targets:
                    active_targets.append(target)
            elif target not in sw_targets and target not in other_targets:
                other_targets.append(target)
        docked_in = tmux_out("show-options", "-qv", "-t", f"={sess}:", "@ide_docked_in").strip()
        if is_switcher_session_name(docked_in):
            dp = tmux_out("show-options", "-qv", "-t", f"={docked_in}:", "@ide_sw_docked_pane").strip()
            if dp:
                dtgt = ["-t", dp]
                if dtgt not in sw_targets and dtgt not in active_targets and dtgt not in other_targets:
                    other_targets.insert(0, dtgt)
        combined = sw_targets + active_targets + other_targets + parked_targets + sw_placeholder
        if combined:
            return combined
        if session_exists(sess):
            return [["-t", f"={sess}:"]]
    if sw_targets or sw_placeholder:
        return sw_targets + sw_placeholder
    if os.environ.get("TMUX_PANE"):
        return [["-t", os.environ["TMUX_PANE"]]]
    return []


def unsplit_wrapped_url(word: str, target_arg: str = "") -> str:
    """Stitch soft-wrapped or indented multi-line URLs back together across visible session panes."""
    if not word:
        return word
    pane_targets = _resolve_capture_pane_targets(target_arg)
    for pt in pane_targets:
        joined_out = tmux_out("capture-pane", "-p", "-J", "-S", "-200", *pt)
        if not joined_out:
            continue
        for m in _WRAP_REF_RE.finditer(joined_out):
            full = strip_token_wrappers(m.group(0))
            if len(full) > len(word) and (full.startswith(word) or full.endswith(word)):
                return full
        if word not in joined_out or not _WRAP_REF_RE.search(joined_out):
            continue
        raw_lines = tmux_out("capture-pane", "-p", "-S", "-200", *pt).splitlines()
        for idx, line in enumerate(raw_lines):
            m_tail = _URL_TAIL_RE.search(line.strip())
            if not m_tail:
                continue
            first_frag = strip_token_wrappers(m_tail.group(1))
            frags = [first_frag]
            cur_line = line.rstrip()
            j = idx + 1
            while j < len(raw_lines) and (
                frags[-1].endswith(("-", "/", "_", "=", "?", "&", "#")) or len(cur_line) >= 60
            ):
                next_s = raw_lines[j].strip()
                if not next_s:
                    break
                first_tok = next_s.split()[0]
                cont = strip_token_wrappers(first_tok)
                if not cont or cont.startswith(("http://", "https://", "file://", "//")) or not _URL_CHARS_RE.match(cont):
                    break
                frags.append(cont)
                cur_line = raw_lines[j].rstrip()
                if len(next_s.split()) > 1:
                    break
                j += 1
            if len(frags) > 1:
                full = "".join(frags)
                if word in frags or full.startswith(word) or full.endswith(word):
                    return full
    return word


def _unwrap_tool_or_token(word: str) -> str:
    word = strip_token_wrappers(word)
    m_tool = _RE_TOOL_CALL.match(word)
    if m_tool:
        word = m_tool.group(2)
        if word.endswith(")"):
            word = word[:-1]
        word = strip_token_wrappers(word)
    return word


def _extract_word_target(raw_word: str, cwd: str = "") -> tuple[str, str]:
    w = raw_word.strip()
    m_lbl = _RE_MD_LABEL.search(w)
    if m_lbl:
        w = m_lbl.group(1)
    return parse_file_target(_unwrap_tool_or_token(w), cwd)


def recover_split_osc8_href(word: str, target_arg: str = "") -> str:
    """Recover OSC 8 hyperlink href when only the first character or `<branch>@<N>` suffix was wrapped."""
    clean_word = strip_token_wrappers(word.strip())
    if not clean_word:
        return ""
    clean_word_nostar = clean_word.rstrip("*")
    pane_targets = _resolve_capture_pane_targets(target_arg)
    for pt in pane_targets:
        esc_out = tmux_out("capture-pane", "-e", "-p", "-J", "-S", "-500", *pt)
        if not esc_out:
            continue
        clean_esc = _SGR_RE.sub("", esc_out)
        matches = list(_SPLIT_OSC8_RE.finditer(clean_esc))
        for m in reversed(matches):
            cand_href, pfx, sfx = m.group(1), m.group(2), m.group(3)
            combined = pfx + sfx
            if combined == clean_word or strip_token_wrappers(combined) == clean_word:
                return cand_href
        sfx_matches = list(_SUFFIX_OSC8_RE.finditer(clean_esc))
        for m in reversed(sfx_matches):
            pfx, cand_href, sfx = m.group(1), m.group(2), m.group(3)
            combined = pfx + sfx
            if (
                combined in (clean_word, clean_word_nostar)
                or strip_token_wrappers(combined) in (clean_word, clean_word_nostar)
                or pfx in (clean_word, clean_word_nostar)
                or strip_token_wrappers(pfx) in (clean_word, clean_word_nostar)
            ):
                return cand_href
        for m in reversed(matches):
            cand_href, pfx, sfx = m.group(1), m.group(2), m.group(3)
            combined = pfx + sfx
            sfx_stripped = sfx.lstrip(TMUX_WORD_SEPS)
            if len(pfx) == 1 and len(sfx_stripped) >= 2 and (
                sfx_stripped == clean_word or strip_token_wrappers(sfx_stripped) == clean_word
            ):
                return cand_href
            if parse_file_target(strip_token_wrappers(combined))[0] == clean_word:
                return cand_href
            if sfx.endswith(("-", "_", ".", "/", ":")):
                m_cont = _CONT_LINE_RE.match(clean_esc[m.end():])
                if m_cont:
                    cont = strip_token_wrappers(m_cont.group(1))
                    full_comb = strip_token_wrappers(combined + cont)
                    if full_comb == clean_word or (len(cont) >= 3 and cont == clean_word):
                        return cand_href
    return ""


def _jump_nvim_markdown_anchor(anchor: str, target_arg: str, focus: bool = True) -> bool:
    import urllib.parse

    from ide_lib.dock import caller_switcher_session, close_switcher_session, undock_switcher_session
    from ide_lib.layout import toggle_main_pane

    slug = urllib.parse.unquote(anchor.lstrip("#").strip()).lower()
    if not slug:
        return False
    sw_to_close = ""
    sw_client = ""
    sw_res_file = ""
    cand_sw = caller_switcher_session(target_arg) if focus else ""
    if cand_sw:
        docked_s, sw_cl, sw_rf = resolve_switcher_context(cand_sw)
        if not docked_s:
            return False
        sw_to_close = cand_sw
        sw_client = sw_cl
        sw_res_file = sw_rf
        target_arg = docked_s
    sess = resolve_target_session(target_arg)
    if not sess or not session_exists(sess):
        return False
    if sw_to_close and focus:
        undock_switcher_session(sw_to_close)
    if focus:
        toggle_main_pane("focus-editor", sess, skip_checktime=True)
    sock = (
        ensure_session_editor_socket(sess)
        if resolve_nvim_bin()
        else get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    )
    if not sock or not is_live_socket(sock) or not resolve_nvim_bin():
        return False
    esc_slug = slug.replace("\\", "\\\\").replace("'", "\\'")
    lua_expr = (
        f"(function() local s = '{esc_slug}'; "
        "local ok, p = pcall(vim.treesitter.get_parser, 0, 'markdown'); "
        "if not ok or not p then return 0 end; "
        "local t = (p:parse() or {})[1]; "
        "if not t then return 0 end; "
        "local q = vim.treesitter.query.parse('markdown', '(atx_heading (inline) @h)'); "
        "local seen = {}; "
        "for _, n in q:iter_captures(t:root(), 0) do "
        "local h = vim.treesitter.get_node_text(n, 0):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%[(.-)%]%b()', '%1'):gsub('%[(.-)%]%b[]', '%1'):gsub('<[^>]+>', ''):gsub('–', ''):gsub('—', ''):gsub('‘', ''):gsub('’', ''):gsub('“', ''):gsub('”', ''); "
        "h = vim.fn.tolower(h):gsub('%p', function(c) return (c == '-' or c == '_') and c or '' end):gsub(' ', '-'); "
        "local c = seen[h] or 0; seen[h] = c + 1; "
        "if (c == 0 and h == s) or (string.format('%s-%d', h, c) == s) then "
        "local l = (n:range()) + 1; "
        "vim.cmd(\"normal! m'\"); "
        "vim.cmd(string.format('keepjumps call cursor(%d, 1) | normal! ^zz', l)); "
        "return l end end; return 0 end)()"
    )
    out = nvim_remote_expr(sock, f'luaeval("{lua_expr.replace(chr(34), chr(92) + chr(34))}")')
    jumped = bool(out and out != "0")
    if jumped and focus and sw_to_close:
        close_switcher_session(
            sw_to_close,
            action="switch",
            target=sess,
            pressed="",
            res_file_hint=sw_res_file,
        )
        if not sw_res_file and sw_client:
            run_tmux("switch-client", "-c", sw_client, "-t", f"={sess}")
    return jumped


def _open_osc8_href(href: str, word: str, cwd: str, target_arg: str) -> int | None:
    if href.startswith("#"):
        return 0 if _jump_nvim_markdown_anchor(href, target_arg) else None
    if not href.startswith("file://"):
        private_url = resolve_private_link(href, cwd, target_arg)
        if private_url:
            href = private_url
    if href.startswith("file://") or not _RE_SCHEME.match(href):
        href_path, href_line = parse_file_target(href, cwd)
        if not href_line and word:
            word_path, word_line = _extract_word_target(word, cwd)
            if word_line and os.path.basename(href_path) == os.path.basename(word_path):
                href_line = word_line
        frag = href.rsplit("#", 1)[1] if (not href_line and "#" in href) else ""
        if resolve_and_open_target(href, cwd, target_arg, fallback_line=href_line):
            if frag:
                _jump_nvim_markdown_anchor(frag, target_arg, focus=False)
            return 0
    elif href.startswith(("http://", "https://")):
        return 0 if open_browser_url(href, target_arg) else 1
    return None


def _open_embedded_file_uri(word: str, lbl_path: str, lbl_line: str, cwd: str, target_arg: str) -> bool:
    m_file_url = _RE_FILE_URI.search(word)
    if not m_file_url:
        return False
    embedded_href = unsplit_wrapped_url(m_file_url.group(1), target_arg)
    while embedded_href and embedded_href[-1] in ",;." and not os.path.exists(embedded_href[7:]):
        embedded_href = embedded_href[:-1]
    emb_path, emb_line = parse_file_target(embedded_href, cwd)
    fb_line = lbl_line if (not emb_line and lbl_line and os.path.basename(emb_path) == os.path.basename(lbl_path)) else ""
    return resolve_and_open_target(embedded_href, cwd, target_arg, fallback_line=fb_line)


def _normalize_clicked_word(word: str) -> str:
    m_md_link = _RE_MD_LINK.search(word)
    if m_md_link:
        word = m_md_link.group(1)
    else:
        m_dest = _RE_MD_DEST_TAIL.match(word)
        if m_dest:
            word = m_dest.group(1)
    return _unwrap_tool_or_token(word)


def open_ide_link(href: str, word: str, cwd: str, target_arg: str) -> int:
    """Route `Ctrl+Click` or `Alt+Click` OSC 8 / plain-text token into Neovim or the browser."""
    if is_switcher_session_name(target_arg):
        dp_chk = tmux_out("show-options", "-qv", "-t", f"={target_arg}:", "@ide_sw_docked_pane").strip()
        if not dp_chk:
            sel_s = resolve_target_session(target_arg)
            if sel_s:
                cwd = (
                    get_ide_var(sel_s, "@ide_workdir", "IDE_WORKDIR")
                    or get_ide_var(sel_s, "@ide_initial_root", "IDE_INITIAL_ROOT")
                    or cwd
                )
    cwd = normalize_pane_cwd(cwd, target_arg=target_arg)
    if os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or target_arg:
        run_tmux("set-option", "-gq", "word-separators", TMUX_WORD_SEPS)

    if not href and word:
        href = recover_split_osc8_href(word, target_arg)

    if href:
        osc8_rc = _open_osc8_href(href, word, cwd, target_arg)
        if osc8_rc is not None:
            return osc8_rc

    word = word.strip()
    if not word:
        return 0

    bracket_label = ""
    lbl_path = ""
    lbl_line = ""
    m_lbl = _RE_MD_LABEL.search(word)
    if m_lbl:
        bracket_label = strip_token_wrappers(m_lbl.group(1))
        lbl_path, lbl_line = parse_file_target(bracket_label, cwd)

    if _open_embedded_file_uri(word, lbl_path, lbl_line, cwd, target_arg):
        return 0

    word = _normalize_clicked_word(word)
    if not word:
        return 0

    word = unsplit_wrapped_url(word, target_arg)
    private_url = resolve_private_link(word, cwd, target_arg)
    if private_url:
        if private_url.startswith("file://"):
            priv_path, priv_line = parse_file_target(private_url, cwd)
            fb_priv_line = (
                lbl_line
                if (not priv_line and lbl_line and os.path.basename(priv_path) == os.path.basename(lbl_path))
                else ""
            )
            priv_frag = private_url.rsplit("#", 1)[1] if (not priv_line and not fb_priv_line and "#" in private_url) else ""
            if resolve_and_open_target(private_url, cwd, target_arg, fallback_line=fb_priv_line):
                if priv_frag:
                    _jump_nvim_markdown_anchor(priv_frag, target_arg, focus=False)
                return 0
        return 0 if open_browser_url(private_url, target_arg) else 1

    if word.startswith(("http://", "https://")):
        return 0 if open_browser_url(word, target_arg) else 1

    word_path_cand, word_line_cand = parse_file_target(word, cwd)
    fb_word_line = (
        lbl_line
        if (not word_line_cand and lbl_line and os.path.basename(word_path_cand) == os.path.basename(lbl_path))
        else ""
    )
    if resolve_and_open_target(word, cwd, target_arg, fallback_line=fb_word_line):
        return 0

    if "..." in word and "/" in word:
        trunc_base = word.rsplit("/", 1)[-1]
        if trunc_base and trunc_base != word and resolve_and_open_target(trunc_base, cwd, target_arg, fallback_line=lbl_line):
            return 0

    if bracket_label and bracket_label != word:
        lbl_priv = resolve_private_link(bracket_label, cwd, target_arg)
        if lbl_priv and lbl_priv.startswith("file://") and resolve_and_open_target(lbl_priv, cwd, target_arg):
            return 0
        if resolve_and_open_target(bracket_label, cwd, target_arg):
            return 0

    return 0


def _format_ai_ref(raw_ref: str, sess: str, ai_pane: str) -> str:
    stripped = raw_ref.strip()
    raw_ai_cwd = tmux_out("display-message", "-p", "-t", ai_pane, "#{pane_current_path}").strip()
    ai_cwd = normalize_pane_cwd(raw_ai_cwd, sess=sess)
    workdir = get_ide_var(sess, "@ide_workdir", "IDE_WORKDIR")
    init_root = get_ide_var(sess, "@ide_initial_root", "IDE_INITIAL_ROOT")
    cand_roots = [r for r in (ai_cwd, workdir, init_root) if r]
    base_cwd = ai_cwd or workdir or init_root

    def _existing_target(path_str: str) -> str:
        if not path_str:
            return ""
        if os.path.isabs(path_str):
            return path_str if os.path.exists(path_str) else ""
        for root in cand_roots:
            joined = os.path.join(root, path_str)
            if os.path.exists(joined):
                return joined
        if os.path.exists(path_str):
            return os.path.abspath(path_str)
        return ""

    exact_existing = _existing_target(stripped)
    if exact_existing:
        raw_path, l1_s, l2_s = exact_existing, None, None
    else:
        m = _SEND_REF_SPEC_RE.match(stripped)
        if not m:
            return f"@{stripped} "
        raw_path, l1_s, l2_s = m.group(1), m.group(2), m.group(3)
        if not raw_path:
            raw_path = stripped
            l1_s = l2_s = None

    suffix = ""
    if l1_s and l2_s:
        lo, hi = max(1, min(int(l1_s), int(l2_s))), max(1, max(int(l1_s), int(l2_s)))
        suffix = f"#L{lo}" if lo == hi else f"#L{lo}-L{hi}"
    elif l1_s:
        suffix = f"#L{max(1, int(l1_s))}"

    resolved_existing = _existing_target(raw_path)
    if resolved_existing:
        abs_path = os.path.abspath(resolved_existing)
    elif os.path.isabs(raw_path):
        abs_path = os.path.abspath(raw_path)
    elif base_cwd:
        abs_path = os.path.abspath(os.path.join(base_cwd, raw_path))
    else:
        abs_path = os.path.abspath(raw_path)

    if os.path.exists(abs_path):
        real_file = os.path.realpath(abs_path)
    else:
        parent_dir = os.path.dirname(abs_path)
        real_parent = os.path.realpath(parent_dir) if os.path.isdir(parent_dir) else parent_dir
        real_file = os.path.join(real_parent, os.path.basename(abs_path))

    real_base = os.path.realpath(base_cwd) if base_cwd and os.path.isdir(base_cwd) else base_cwd

    in_workspace = False
    for cand_root in cand_roots:
        real_root = os.path.realpath(cand_root) if os.path.isdir(cand_root) else os.path.abspath(cand_root)
        if real_root == "/":
            continue
        try:
            if os.path.commonpath([real_file, real_root]) == real_root:
                in_workspace = True
                break
        except ValueError:
            pass

    if in_workspace and real_base:
        try:
            display_path = os.path.relpath(real_file, real_base)
        except ValueError:
            display_path = real_file
    else:
        display_path = real_file

    return f"@{display_path}{suffix} "


def _strip_bracketed_paste_escapes(text: str) -> str:
    cleaned = text
    while _BRACKETED_PASTE_ESC_RE.search(cleaned):
        cleaned = _BRACKETED_PASTE_ESC_RE.sub("", cleaned)
    return cleaned


def send_to_ai(
    send_mode: str,
    send_payload: str,
    no_focus: bool,
    switch_session: bool,
    target_arg: str,
) -> int:
    """Stage context into the target AI Agent prompt via dedicated `_ide_send_<pid>` buffer without Enter."""
    from ide_lib.dock import switch_or_attach_session
    from ide_lib.fleet import ack_ai_session
    from ide_lib.layout import toggle_main_pane, unpark_role_pane

    if not send_mode:
        print("Error: '--send' requires '--stdin', '--ref <PATH>', or '--text <TEXT>'.", file=sys.stderr)
        return 1

    origin_sess = current_ide_session() if os.environ.get("TMUX") else ""
    sess = resolve_target_session(target_arg)
    if not sess or not session_exists(sess):
        print(f"Error: {missing_session_msg(sess)}", file=sys.stderr)
        return 1

    stdin_text = ""
    if send_mode == "stdin":
        stdin_text = sys.stdin.buffer.read().decode("utf-8", errors="replace")
        if not stdin_text:
            return 0
    elif send_mode == "ref":
        if not send_payload.strip():
            return 0
    elif not send_payload:
        return 0

    ai_pane = resolve_role_pane(sess, "ai", "@ide_ai_pane", "IDE_AI_PANE")
    if not pane_exists(ai_pane):
        err_msg = f"Refused to send to '{sess}': AI pane is not running an AI CLI."
        run_tmux("display-message", "-d", "4000", "-t", f"={sess}:", err_msg)
        print(f"Error: {err_msg}", file=sys.stderr)
        return 1
    ai_info = tmux_out(
        "display-message",
        "-p",
        "-t",
        ai_pane,
        TMUX_SEP.join(["#{pane_pid}", "#{pane_current_command}"]),
    )
    ai_pid, ai_cmd = (ai_info.split(TMUX_SEP, 1) + [""])[:2]
    if not pane_has_child_procs(ai_pid, ai_cmd):
        err_msg = f"Refused to send to '{sess}': AI pane is at an idle shell prompt (launch an AI CLI first)."
        run_tmux("display-message", "-d", "4000", "-t", f"={sess}:", err_msg)
        print(f"Error: {err_msg}", file=sys.stderr)
        return 1

    eff_no_focus = False if switch_session else no_focus
    in_sw_target = is_switcher_session_name(target_arg) and not switch_session
    prev_pane = tmux_out("display-message", "-p", "-t", f"={sess}:", "#{pane_id}") if eff_no_focus else ""
    if not eff_no_focus:
        toggle_main_pane("focus-ai", target_arg if in_sw_target else sess)
        ai_pane = resolve_role_pane(sess, "ai", "@ide_ai_pane", "IDE_AI_PANE")
    else:
        editor_pane = resolve_role_pane(sess, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
        term_pane = resolve_role_pane(sess, "term", "@ide_term_pane", "IDE_TERM_PANE")
        main_win = resolve_main_win(sess, editor_pane, ai_pane, term_pane)
        if pane_is_parked(ai_pane, main_win):
            unpark_role_pane(sess, "ai", main_win, ai_pane, editor_pane, term_pane, "")
            if pane_exists(prev_pane):
                run_tmux("select-pane", "-t", prev_pane)

    if not pane_exists(ai_pane):
        print(f"Error: Could not resolve AI pane for session '{sess}'.", file=sys.stderr)
        return 1

    if send_mode == "stdin":
        payload = stdin_text
    elif send_mode == "ref":
        payload = _format_ai_ref(send_payload, sess, ai_pane)
    else:
        payload = send_payload

    payload = _strip_bracketed_paste_escapes(payload)
    if not payload:
        return 0

    import tempfile

    buf_name = f"_ide_send_{os.getpid()}"
    with tempfile.NamedTemporaryFile(prefix="ide-send.", delete=False) as tf:
        tf.write(payload.encode("utf-8"))
        tmp_path = tf.name
    try:
        if run_tmux("load-buffer", "-b", buf_name, tmp_path).returncode == 0:
            if tmux_out("display-message", "-p", "-t", ai_pane, "#{pane_in_mode}") == "1":
                run_tmux("copy-mode", "-q", "-t", ai_pane)
            paste_res = run_tmux("paste-buffer", "-p", "-d", "-b", buf_name, "-t", ai_pane)
            if paste_res.returncode != 0:
                run_tmux("paste-buffer", "-d", "-b", buf_name, "-t", ai_pane)
            run_tmux("delete-buffer", "-b", buf_name)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    if switch_session:
        rc = switch_or_attach_session(sess, origin_sess)
        ack_ai_session([sess], from_hook=True, refresh_always=False)
        return rc
    return 0
