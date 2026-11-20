"""Shared constants, CLI usage specification, and pure string/path utilities."""

from __future__ import annotations

import os
import re
import stat
import sys

TYPE_CHECKING = False
if TYPE_CHECKING:
    from typing import TextIO

# Printable tab-framed field separator that survives tmux <= 3.4 utf8_stravis C0 octal escaping
# as well as literal tab characters inside workspace directory paths.
_TMUX_SEP = "\t__IDE_SEP__\t"
TMUX_SEP = _TMUX_SEP

_TMUX_WORD_SEPS = " ()[]{}<>\"'`,;*"
TMUX_WORD_SEPS = _TMUX_WORD_SEPS
_SWITCHER_SESS_PREFIX = "ai-sw-"

ROLE_PARK_VARS: dict[str, tuple[str, str]] = {
    "ai": ("@ide_ai_parked", "IDE_AI_PARKED"),
    "editor": ("@ide_ed_parked", "IDE_ED_PARKED"),
    "term": ("@ide_term_parked", "IDE_TERM_PARKED"),
}

DEFAULT_THEME_HEX: dict[str, str] = {
    "BASE03": "#002B36",
    "BASE02": "#073642",
    "BASE01": "#586E75",
    "BASE00": "#657B83",
    "BASE0": "#839496",
    "BASE1": "#93A1A1",
    "BASE2": "#EEE8D5",
    "BASE3": "#FDF6E3",
    "YELLOW": "#B58900",
    "ORANGE": "#CB4B16",
    "RED": "#DC322F",
    "MAGENTA": "#D33682",
    "VIOLET": "#6C71C4",
    "BLUE": "#268BD2",
    "CYAN": "#2AA198",
    "GREEN": "#859900",
}

USAGE_TEXT = """Usage: ide [OPTIONS] [DIRECTORY]

Launch or attach to a Solarized Dark Tmux + Neovim IDE workspace session.

Options:
  --3pane                  Launch default 3-pane layout (Top-Left 50%x75% AI, Top-Right 50%x75% Editor, Bottom 100%x25% Shell)
  --2pane                  Launch 2-pane layout (Left 50%x100% AI, Right 50%x100% Editor)
  --ai, --agent <CLI>      Select AI CLI agent: agy (default), claude, or codex (overrides $IDE_AI_CLI)
  --open <FILE> [LINE]     Open <FILE> in the Main Editor pane via RPC and focus Editor
  --preview <FILE> [LINE]  Preview <FILE> in the Main Editor pane via RPC without changing focus
  cd, --cd [DIR]           Dive into <DIR> (or --reset / ~ for initial root), setting Working Directory across Editor and Shell
  -s, --sessions [SESSION] Open interactive multi-session IDE workspace switcher (Alt+s / Prefix+s)
  -n, --new                Open interactive workspace directory picker to launch or switch to a session
  --next-attention [SESSION] Jump to oldest IDE session waiting for AI attention in urgency and FIFO order (Alt+Shift+S / Prefix+S)
  --agent-state <STATE> [--message <TEXT>] [SESSION] Record deterministic AI lifecycle state: running, approval, quota, done, or idle
  --ack-ai [SESSION...]    Acknowledge AI attention across one or more IDE sessions
  --open-pr [SESSION]      Open cached pull or merge request URL for an IDE session
  --send <PAYLOAD> [SESSION] Dispatch context (--stdin, --ref <PATH>[:L1[-L2]], --text <TEXT>, --no-focus, --switch) to AI Agent
  --toggle [SESSION]       Toggle focus between the AI Agent and the Text Editor (unparking if hidden)
  --show-editor [SESSION]  Focus the Text Editor pane (unparking if hidden), or bounce back if already focused
  --show-ai [SESSION]      Focus the AI Agent pane (unparking if hidden), or bounce back if already focused
  --show-term [SESSION]    Focus the Interactive Shell pane (unparking if hidden), or bounce back if already focused
  --toggle-editor [SESSION] Hide or reappear the Text Editor pane (Alt+Shift+E)
  --toggle-ai [SESSION]    Hide or reappear the AI Agent pane
  --toggle-term [SESSION]  Hide or reappear the Interactive Shell pane (Alt+Shift+T)
  --swap <DIR> [SESSION]   Swap the active pane with its neighbor in <DIR> (left|down|up|right, Alt+Shift+H/J/K/L)
  --monitor, --top         Launch interactive system monitor with btop -> htop -> top fallback (Alt+m / Prefix+m)
  --keys                   Display the Solarized Dark IDE keybinding cheatsheet (Alt+? / Prefix+?)
  refresh, -r, --refresh [NAME] Refresh tmux top bar and Editor themes and CWDs across all (or target) IDE sessions (Prefix+r)
  quit, -q, --quit [NAME...] Safely quit IDE session(s) NAME (checks for unsaved Neovim buffers first)
  -f, --force              Force-quit when used with --quit (discards unsaved Neovim buffers)
  --detach                 Create/update workspace session in background without attaching
  kill, --kill [NAME...]   Force-quit IDE session(s) NAME without the unsaved-buffer check
  --list [--plain]         List active IDE workspace sessions with agent CLI, state, Git branch, and directory
  -h, --help               Show this help message and exit

Without NAME / SESSION, session commands act only on the ide session of the calling pane
(outside tmux: the current directory's session), never on any other tmux session.

Environment Variables:
  IDE_AI_CLI               AI CLI tool for the AI Agent pane: agy (default), claude, or codex
  IDE_BROWSER              Optional browser executable for opening http(s):// links
  IDE_NOTIFY               Local desktop banner policy: 0 (default), 1 / unfocused, or always
  IDE_WORKSPACE_DIRS       Optional colon-separated workspace directories surfaced in launcher and completions
  IDE_LINK_RULES           Untracked Ctrl+click link, workspace, session-naming, notification, and VCS hooks (default: ${XDG_CONFIG_HOME:-~/.config}/ide/links.sh)
                           defining `ide_resolve_link`, `ide_session_name`, `ide_workspace_dirs`, `ide_resolve_workspace`, `ide_notify`, or `ide_vcs_summary`"""

_SGR_RE = re.compile(r"\x1b\[[0-9;:]*m")
_ANSI_ESC_RE = re.compile(
    r"\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)|[P^_].*?\x1b\\|\[[0-?]*[ -/]*[@-~]|[@-_])|\x9b[0-?]*[ -/]*[@-~]",
    re.DOTALL,
)
_CTL_WS_RE = re.compile(r"[\x00-\x1f\x7f-\x9f]")
_SAFE_HTTP_URL_RE = re.compile(r"^https?://[^\s\x00-\x1f\x7f]+$", re.IGNORECASE)


def usage(file: TextIO = sys.stdout) -> None:
    """Print the CLI usage specification to `file`."""
    print(USAGE_TEXT, file=file)


def is_socket_path(path: str | os.PathLike[str]) -> bool:
    """Return True when `path` exists on disk as a Unix domain socket."""
    try:
        st = os.stat(path)
        return stat.S_ISSOCK(st.st_mode)
    except OSError:
        return False


def is_live_socket(path: str | os.PathLike[str]) -> bool:
    """Return True when `path` is a Unix domain socket with an active listener."""
    if not is_socket_path(path):
        return False
    import errno
    import socket

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.2)
    try:
        s.connect(os.fspath(path))
        return True
    except (TimeoutError, socket.timeout):
        return True
    except OSError as exc:
        return exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINPROGRESS)
    finally:
        try:
            s.close()
        except OSError:
            pass


def safe_getcwd() -> str:
    """Return a live working directory path, healing stale or unlinked descriptors."""
    pwd = os.environ.get("PWD") or ""
    try:
        cwd = os.getcwd()
        st_dot = os.stat(".")
        if pwd.startswith("/") and os.path.isdir(pwd):
            st_pwd = os.stat(pwd)
            if st_dot.st_dev != st_pwd.st_dev or st_dot.st_ino != st_pwd.st_ino:
                os.chdir(pwd)
                return pwd
        if st_dot.st_nlink > 0:
            return cwd
    except OSError:
        pass
    for cand in (
        pwd,
        os.environ.get("IDE_WORKDIR") or "",
        os.environ.get("IDE_INITIAL_ROOT") or "",
        os.path.expanduser("~"),
        "/",
    ):
        if cand and cand.startswith("/") and os.path.isdir(cand):
            try:
                os.chdir(cand)
            except OSError:
                pass
            return cand
    return "/"


def sanitize_name_token(raw: str) -> str:
    """Normalize an arbitrary string into a safe tmux session name token."""
    cleaned = re.sub(r"[.: ]", "-", raw)
    cleaned = re.sub(r"[^A-Za-z0-9_-]", "", cleaned).lstrip("-")
    return cleaned or "workspace"


def shorten_home(path: str) -> str:
    """Replace a leading `$HOME` prefix with `~` for display."""
    if not path:
        return "-"
    home = os.path.expanduser("~").rstrip("/")
    if home and (path == home or path.startswith(home + "/")):
        return "~" + path[len(home):]
    return path


def sanitize_http_url(raw_url: str) -> str:
    """Return `raw_url` stripped if it is a safe `http(s)://` URL, otherwise empty."""
    cand = raw_url.strip()
    return cand if (cand and _SAFE_HTTP_URL_RE.match(cand)) else ""


def sanitize_agent_msg(raw: str, max_chars: int = 160) -> str:
    """Strip ANSI/control sequences from `raw`, collapse whitespace, and cap length."""
    if not raw:
        return ""
    stripped = _CTL_WS_RE.sub(" ", _ANSI_ESC_RE.sub("", raw))
    collapsed = " ".join(stripped.split())
    if len(collapsed) > max_chars:
        return collapsed[: max_chars - 1] + "…"
    return collapsed


def char_cell_width(ch: str) -> int:
    """Return terminal column width of a single character (Nerd Font PUA = 1 cell)."""
    cp = ord(ch)
    if 0x20 <= cp < 0x7F:
        return 1
    if 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0x10FFFF:
        return 1
    import unicodedata

    if unicodedata.combining(ch):
        return 0
    if cp >= 0x1F300 or unicodedata.east_asian_width(ch) in ("W", "F"):
        return 2
    return 1


def visible_width(text: str) -> int:
    """Return terminal column width of `text` after stripping SGR escape sequences."""
    clean = _SGR_RE.sub("", text)
    return sum(char_cell_width(ch) for ch in clean)


def pad_visible(text: str, width: int) -> str:
    """Right-pad `text` with spaces to `width` visible terminal columns."""
    pad = max(0, width - visible_width(text))
    return text + (" " * pad)


def trunc_visible(text: str, max_w: int, suffix: str = "…") -> str:
    """Truncate `text` to at most `max_w` visible terminal columns."""
    if visible_width(text) <= max_w:
        return text
    sfx_w = visible_width(suffix)
    budget = max(0, max_w - sfx_w)
    out: list[str] = []
    used = 0
    for ch in text:
        cw = char_cell_width(ch)
        if used + cw > budget:
            break
        out.append(ch)
        used += cw
    return "".join(out) + suffix


def is_switcher_session_name(sess: str) -> bool:
    """Return True when `sess` names an ephemeral 2-pane `ide --sessions` switcher session (`ai-sw-*`)."""
    return bool(sess) and sess.startswith(_SWITCHER_SESS_PREFIX)


def write_switcher_result(res_path: str, action: str, target: str = "", pressed: str = "") -> None:
    """Atomically record the user's switcher selection (`switch`, `launch`, or `none`) to `res_path`."""
    if not res_path:
        return
    import json

    tmp_p = f"{res_path}.tmp.{os.getpid()}"
    payload = json.dumps({"action": action, "target": target, "pressed": pressed})
    try:
        fd = os.open(tmp_p, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
        try:
            os.write(fd, (payload + "\n").encode("utf-8"))
        finally:
            os.close(fd)
        os.replace(tmp_p, res_path)
    except OSError:
        try:
            os.unlink(tmp_p)
        except OSError:
            pass


def read_switcher_result(res_path: str) -> tuple[str, str, str] | None:
    """Read `(action, target, pressed)` from `res_path`, returning `None` if absent or invalid."""
    if not res_path or not os.path.isfile(res_path):
        return None
    import json

    try:
        with open(res_path, "r", encoding="utf-8") as fh:
            data = json.loads(fh.read())
        if isinstance(data, dict):
            return (
                str(data.get("action") or ""),
                str(data.get("target") or ""),
                str(data.get("pressed") or ""),
            )
    except (OSError, ValueError):
        pass
    return None


_MISE_TOOL_BIN_CACHE: dict[tuple[str, str, str], str | None] = {}
_MISE_VER_NUM_RE = re.compile(r"[0-9]+")


def _mise_ver_sort_key(ver_name: str) -> tuple[int, ...]:
    if ver_name == "latest":
        return (999999,)
    nums = [int(x) for x in _MISE_VER_NUM_RE.findall(ver_name)]
    return tuple(nums) if nums else (0,)


def _find_mise_installed_bin(mise_root: str, pkg_name: str, tool_name: str) -> str | None:
    pkg_dir = os.path.join(mise_root, "installs", pkg_name)
    if not os.path.isdir(pkg_dir):
        return None
    ver_dirs: list[tuple[tuple[int, ...], str]] = []
    try:
        with os.scandir(pkg_dir) as it:
            for dent in it:
                if dent.name.startswith("."):
                    continue
                try:
                    if dent.is_dir():
                        ver_dirs.append((_mise_ver_sort_key(dent.name), dent.path))
                except OSError:
                    pass
    except OSError:
        return None
    ver_dirs.sort(key=lambda x: x[0], reverse=True)
    for _, vdir in ver_dirs:
        for sub in (os.path.join(vdir, "bin", tool_name), os.path.join(vdir, tool_name)):
            if os.path.isfile(sub) and os.access(sub, os.X_OK):
                return sub
    return None


def resolve_mise_tool_bin(
    tool_name: str,
    install_dir_name: str = "",
    env_override: str = "",
) -> str | None:
    """Resolve `tool_name` on `PATH`, bypassing `mise/shims` overhead when installed under `mise/installs`."""
    import shutil

    if env_override:
        raw_ovr = (os.environ.get(env_override) or "").strip()
        if raw_ovr:
            if os.path.isfile(raw_ovr) and os.access(raw_ovr, os.X_OK):
                return raw_ovr
            return shutil.which(raw_ovr)
    env_mise = (os.environ.get("MISE_DATA_DIR") or "").strip()
    cache_key = (
        tool_name,
        install_dir_name,
        f"{os.environ.get('PATH', '')}\0{env_mise}",
    )
    if cache_key in _MISE_TOOL_BIN_CACHE:
        return _MISE_TOOL_BIN_CACHE[cache_key]

    cand = shutil.which(tool_name)
    if cand:
        try:
            real = os.path.realpath(cand)
        except OSError:
            real = cand
        norm_cand = cand.replace("\\", "/")
        if "/mise/shims/" in norm_cand or os.path.basename(real) == "mise":
            shim_root = os.path.dirname(os.path.dirname(os.path.abspath(cand)))
            pkg_name = install_dir_name or tool_name
            seen_roots: set[str] = set()
            for m_root in (shim_root, env_mise):
                clean_root = m_root.rstrip("/") if m_root and m_root != "/" else m_root
                if not clean_root or clean_root in seen_roots:
                    continue
                seen_roots.add(clean_root)
                direct = _find_mise_installed_bin(clean_root, pkg_name, tool_name)
                if direct:
                    _MISE_TOOL_BIN_CACHE[cache_key] = direct
                    return direct
        _MISE_TOOL_BIN_CACHE[cache_key] = cand
        return cand
    _MISE_TOOL_BIN_CACHE[cache_key] = None
    return None
