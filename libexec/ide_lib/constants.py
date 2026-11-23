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

USAGE_TEXT = """Usage:
  ide [OPTIONS] [DIR | SESSION]
  ide <COMMAND> [ARGS...]

Launch or attach to a Solarized Dark Tmux + Neovim + AI IDE workspace, or manage active sessions.

Launch Options:
  --2pane                  Launch 2-pane side-by-side layout (default: 3-pane inverted-T)
  --agent <CLI>            Select AI CLI agent: agy (default), claude, or codex (overrides $IDE_AI_CLI)
  -d, --detach             Create or update workspace session in background without attaching
  -h, --help               Show help (pass after a command for command-specific help)

Workspace & Fleet Commands:
  list [--plain | --json]  List active IDE sessions (status table, raw names, or JSON array)
  switch, -s [SESSION]     Open interactive multi-session IDE workspace switcher (Alt+s)
  new, -n [NAME]           Create a new workspace via hook or mkdir and launch IDE (Alt+n)
  dir, -o [QUERY]          Open interactive existing-directory workspace picker (Alt+o)
  agent [<CLI>|restart] [SESSION]
                           Switch or restart an IDE session's AI Agent CLI (agy, claude, codex)
  next [SESSION]           Jump to oldest IDE session waiting for AI attention (Alt+Shift+S)
  cd [DIR | --reset]       Set working directory across Editor and Shell panes
  refresh [SESSION]        Refresh Tmux chrome, Editor themes, and CWDs across IDE sessions
  quit [-f | --force] [SESSION...]
                           Safely close IDE session(s) after checking unsaved Neovim buffers

Agent & Editor RPC Commands:
  open [-p | --preview] <FILE>[:LINE] [SESSION]
                           Open or focusless-preview a file in the Main Editor pane via RPC
  send [--stdin | --ref <PATH>[:L1[-L2]] | --text <TEXT>] [--no-focus | --switch] [SESSION]
                           Stage prompt context into an IDE session's AI Agent pane
  state <STATE> [-m | --message <TEXT>] [SESSION]
                           Record AI lifecycle state: running, approval, quota, done, or idle
  ack [SESSION...]         Acknowledge AI attention across one or more IDE sessions
  pr [SESSION]             Open cached pull or merge request URL for an IDE session

Utilities:
  keys                     Display interactive IDE keybinding cheatsheet (Alt+? / F1)
  monitor                  Launch system monitor with btop, htop, or top fallback (Alt+m)

Without SESSION, session commands act only on the ide session of the calling pane
(outside tmux: the current directory's session), never on any other tmux session.

Environment Variables:
  IDE_AI_CLI               AI CLI tool for the AI Agent pane: agy (default), claude, or codex
  IDE_BROWSER              Optional browser executable for opening http(s):// links
  IDE_NOTIFY               Local desktop banner policy: 0 (default), 1 / unfocused, or always
  IDE_NERD_FONTS           Set to 0 / off to omit Nerd Font PUA icons across ide TUI surfaces (auto-disabled on TERM=dumb)
  IDE_WORKSPACE_PARENT     Parent directory for newly created bare workspace names (default: $HOME)
  IDE_WORKSPACE_DIRS       Optional colon-separated workspace directories surfaced in launcher and completions
  IDE_LINK_RULES           Untracked Ctrl+click link, workspace, session-naming, notification, and VCS hooks (default: ${XDG_CONFIG_HOME:-~/.config}/ide/links.sh)
                           defining `ide_create_workspace`, `ide_resolve_link`, `ide_session_name`, `ide_workspace_dirs`, `ide_resolve_workspace`, `ide_notify`, or `ide_vcs_summary`"""

SUBCOMMAND_USAGE: dict[str, str] = {
    "list": """Usage: ide list [--plain | --json]

List active IDE workspace sessions in urgency order (ATTN, DONE, WORKING, QUOTA, IDLE, SHELL).

Options:
  --plain    Print session names only (one per line)
  --json     Print machine-readable JSON array with keys:
             session, agent, state, state_label, state_ts, needs_attention, attention_ts,
             message, workdir, git_branch, git_dirty, git_detail, git_pr_url,
             worktree_root, worktree_peers, active_role, attached, is_current, quit_error""",
    "switch": """Usage: ide switch [OPTIONS] [SESSION]
Alias: ide -s [SESSION]

Open the interactive two-pane fzf IDE workspace switcher (opens 'ide dir' if zero sessions exist).

Options:
  --2pane          Use 2-pane layout when launching a new workspace
  --agent <CLI>    Select AI CLI (agy, claude, codex) when launching a new workspace
  -d, --detach     Create new workspace in background without attaching""",
    "new": """Usage: ide new [OPTIONS] [NAME]
Alias: ide -n [NAME]

Create a new workspace directory via `ide_create_workspace` in links.sh (or mkdir under
${IDE_WORKSPACE_PARENT:-$HOME}) and launch its IDE session. Omit NAME to open the interactive
New Workspace prompt card (Tab cycles agy/claude/codex; Alt+o flips to existing directories).

Options:
  --2pane          Launch new workspace in 2-pane layout
  --agent <CLI>    Select AI CLI (agy, claude, codex)
  -d, --detach     Create workspace session in background without attaching""",
    "dir": """Usage: ide dir [OPTIONS] [QUERY]
Alias: ide -o [QUERY]

Open the interactive fzf existing-directory picker across zoxide, workspace roots,
$IDE_WORKSPACE_PARENT, and $HOME subdirectories with VCS/file preview (Alt+n flips to New Workspace).

Options:
  --2pane          Launch selected workspace in 2-pane layout
  --agent <CLI>    Select AI CLI (agy, claude, codex)
  -d, --detach     Create workspace in background without attaching""",
    "agent": """Usage: ide agent [<CLI> | restart] [SESSION]

Switch an IDE session's AI Agent CLI (agy, claude, codex, or custom executable) or restart the
current agent CLI in place (recovering exited SHELL or QUOTA-blocked panes). Omit <CLI> in an
interactive terminal to open the AI Agent picker dialog.""",
    "next": """Usage: ide next [SESSION]

Jump to the oldest IDE session waiting for AI attention (ATTN blockers ahead of DONE in FIFO order).""",
    "cd": """Usage: ide cd [DIR | --reset] [SESSION]

Set the working directory across the session's Main Editor and Shell panes without restarting AI.
Pass --reset or ~ to return to the session's initial launch root.""",
    "refresh": """Usage: ide refresh [SESSION]

Reload Tmux top bar and theme config, heal Editor RPC sockets and CWDs, and reload Neovim themes.""",
    "quit": """Usage: ide quit [-f | --force] [SESSION...]

Safely close one or more IDE sessions after checking Neovim for unsaved buffer modifications.

Options:
  -f, --force    Skip the unsaved-buffer check and terminate immediately""",
    "open": """Usage: ide open [-p | --preview] <FILE>[:LINE] [+LINE] [SESSION]

Open a file (at optional line number) in the session's Main Neovim Editor pane over MsgPack-RPC.

Options:
  -p, --preview  Preview the file in the Main Editor without changing active pane focus""",
    "send": """Usage: ide send [SOURCE] [--no-focus | --switch] [SESSION]

Stage prompt text or file references into the target IDE session's AI Agent prompt without submitting.

Source Options:
  --stdin                    Read payload from standard input
  --ref <PATH>[:L1[-L2]]     Format a workspace-relative @file#L1-L2 reference
  --text <TEXT>              Send literal text (or pass <TEXT> positionally)

Focus Options:
  --no-focus                 Keep current pane focus instead of focusing the AI pane
  --switch                   Focus the target AI pane and switch client to SESSION""",
    "state": """Usage: ide state <STATE> [-m | --message <TEXT>] [SESSION]

Record deterministic AI lifecycle state: running, approval, quota, done, or idle.
Reads optional hook JSON from non-TTY stdin or trailing '{...}' arguments.""",
    "ack": """Usage: ide ack [SESSION...]

Acknowledge AI attention across one or more IDE sessions (DONE transitions to IDLE; ATTN mutes alert).""",
    "pr": """Usage: ide pr [SESSION]

Open the cached pull or merge request deliverable URL for an IDE session.""",
    "keys": """Usage: ide keys

Display the 80x24-fitted Solarized Dark IDE keybinding cheatsheet.""",
    "monitor": """Usage: ide monitor

Launch an interactive system monitor with btop, htop, and top fallback.""",
}

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
    """Return True when `sess` names an ephemeral 2-pane `ide switch` switcher session (`ai-sw-*`)."""
    return bool(sess) and sess.startswith(_SWITCHER_SESS_PREFIX)


def use_nerd_fonts() -> bool:
    """Return False when `IDE_NERD_FONTS=0|off|false|no|ascii`, `IDE_ASCII=1`, or `TERM=dumb`."""
    nf = (os.environ.get("IDE_NERD_FONTS") or "").strip().lower()
    if nf in ("0", "false", "off", "no", "ascii"):
        return False
    if (os.environ.get("IDE_ASCII") or "").strip().lower() in ("1", "true", "on", "yes"):
        return False
    if (os.environ.get("TERM") or "").strip().lower() == "dumb":
        return False
    return True


def write_switcher_result(
    res_path: str,
    action: str,
    target: str = "",
    pressed: str = "",
    agent: str = "",
    layout: str = "",
) -> None:
    """Atomically record the user's switcher selection (`switch`, `launch`, or `none`) to `res_path`."""
    if not res_path:
        return
    import json

    tmp_p = f"{res_path}.tmp.{os.getpid()}"
    data: dict[str, str] = {"action": action, "target": target, "pressed": pressed}
    if agent:
        data["agent"] = agent
    if layout:
        data["layout"] = layout
    payload = json.dumps(data)
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


def read_switcher_launch_opts(res_path: str) -> tuple[str, str]:
    """Read optional `(agent, layout)` overrides recorded in `res_path`."""
    if not res_path or not os.path.isfile(res_path):
        return ("", "")
    import json

    try:
        with open(res_path, "r", encoding="utf-8") as fh:
            data = json.loads(fh.read())
        if isinstance(data, dict):
            return (
                str(data.get("agent") or ""),
                str(data.get("layout") or ""),
            )
    except (OSError, ValueError):
        pass
    return ("", "")


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


def which_executable(cmd: str) -> str | None:
    """Locate executable `cmd` on `PATH` using pure `os` syscalls without importing `shutil`."""
    if not cmd:
        return None
    if os.sep in cmd or (os.altsep and os.altsep in cmd):
        return cmd if (os.path.isfile(cmd) and os.access(cmd, os.X_OK)) else None
    raw_path = os.environ.get("PATH")
    if raw_path is None:
        raw_path = os.defpath
    if not raw_path:
        return None
    seen: set[str] = set()
    for entry in raw_path.split(os.pathsep):
        d = entry or "."
        if d in seen:
            continue
        seen.add(d)
        cand = os.path.join(d, cmd)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def resolve_mise_tool_bin(
    tool_name: str,
    install_dir_name: str = "",
    env_override: str = "",
) -> str | None:
    """Resolve `tool_name` on `PATH`, bypassing `mise/shims` overhead when installed under `mise/installs`."""
    if env_override:
        raw_ovr = (os.environ.get(env_override) or "").strip()
        if raw_ovr:
            if os.path.isfile(raw_ovr) and os.access(raw_ovr, os.X_OK):
                return raw_ovr
            return which_executable(raw_ovr)
    env_mise = (os.environ.get("MISE_DATA_DIR") or "").strip()
    cache_key = (
        tool_name,
        install_dir_name,
        f"{os.environ.get('PATH', '')}\0{env_mise}",
    )
    if cache_key in _MISE_TOOL_BIN_CACHE:
        return _MISE_TOOL_BIN_CACHE[cache_key]

    cand = which_executable(tool_name)
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
