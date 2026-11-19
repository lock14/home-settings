"""Mise-aware Neovim RPC helpers, stale-CWD self-healing, and Editor/AI launch commands."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import time

from ide_lib.constants import TMUX_SEP, is_live_socket, is_socket_path
from ide_lib.tmux import (
    discover_pane_nvim_sockets,
    get_ide_var,
    resolve_role_pane,
    resolve_target_session,
    run_tmux,
    session_exists,
    set_ide_var,
    tmux_out,
)

_NVIM_BIN_CACHE: str | None = None
_NVIM_BIN_RESOLVED = False


def _version_sort_key(bin_path: Path) -> tuple[int, ...]:
    ver_str = bin_path.parent.parent.name
    if ver_str == "latest":
        return (999999,)
    nums = [int(x) for x in re.findall(r"[0-9]+", ver_str)]
    return tuple(nums) if nums else (0,)


def resolve_nvim_bin() -> str | None:
    """Resolve direct Neovim binary path, bypassing Mise shim overhead when installed under `mise`."""
    global _NVIM_BIN_CACHE, _NVIM_BIN_RESOLVED
    if _NVIM_BIN_RESOLVED:
        return _NVIM_BIN_CACHE
    _NVIM_BIN_RESOLVED = True
    cand = shutil.which("nvim")
    if cand:
        try:
            real = os.path.realpath(cand)
        except OSError:
            real = cand
        norm_cand = cand.replace("\\", "/")
        if "/mise/shims/" in norm_cand or os.path.basename(real) == "mise":
            mise_root = Path(cand).parent.parent
            installs_dir = mise_root / "installs" / "neovim"
            if installs_dir.is_dir():
                bins = sorted(installs_dir.glob("*/bin/nvim"), key=_version_sort_key)
                for b in reversed(bins):
                    if b.is_file() and os.access(b, os.X_OK):
                        _NVIM_BIN_CACHE = str(b)
                        return _NVIM_BIN_CACHE
            if shutil.which("mise"):
                env = os.environ.copy()
                if mise_root.is_dir() and "MISE_DATA_DIR" not in env:
                    env["MISE_DATA_DIR"] = str(mise_root)
                res = subprocess.run(
                    ["mise", "which", "nvim"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                    env=env,
                    check=False,
                )
                if res.returncode == 0:
                    p = res.stdout.strip()
                    if p and os.path.isfile(p) and os.access(p, os.X_OK):
                        _NVIM_BIN_CACHE = p
                        return _NVIM_BIN_CACHE
        _NVIM_BIN_CACHE = cand
        return _NVIM_BIN_CACHE
    if shutil.which("mise"):
        res = subprocess.run(
            ["mise", "which", "nvim"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
        if res.returncode == 0:
            p = res.stdout.strip()
            if p and os.path.isfile(p) and os.access(p, os.X_OK):
                _NVIM_BIN_CACHE = p
                return _NVIM_BIN_CACHE
    return None


def resolve_ai_cmd(cli: str) -> str | None:
    """Resolve shell-quoted AI CLI command string, falling back across `agy`, `claude`, `codex`."""
    if cli == "claude":
        found = shutil.which("claude")
        if found:
            return shlex.quote(found)
    elif cli in ("codex", "openai"):
        found = shutil.which("codex")
        if found:
            return shlex.quote(found)
    elif cli == "agy":
        found = shutil.which("agy")
        if found:
            return shlex.quote(found)
    elif cli:
        found_cli = shutil.which(cli)
        if found_cli and "/" not in cli:
            return shlex.quote(found_cli)
        if os.path.isfile(cli) and os.access(cli, os.X_OK):
            return shlex.quote(os.path.abspath(cli))
        if found_cli:
            return shlex.quote(found_cli)

    for fallback in ("agy", "claude", "codex"):
        found_fb = shutil.which(fallback)
        if found_fb:
            return shlex.quote(found_fb)
    return None


def _nvim_rpc_env() -> dict[str, str]:
    env = os.environ.copy()
    if not env.get("NVIM_LOG_FILE"):
        env["NVIM_LOG_FILE"] = "/dev/null"
    return env


def nvim_remote_expr(sock: str, expr: str) -> str:
    """Evaluate `expr` on a live Neovim server socket with a 5s timeout."""
    nvim_bin = resolve_nvim_bin()
    if not sock or not is_socket_path(sock) or not nvim_bin:
        return ""
    try:
        res = subprocess.run(
            [nvim_bin, "--headless", "--server", sock, "--remote-expr", expr],
            env=_nvim_rpc_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
            check=False,
        )
        return (res.stdout or "").strip()
    except subprocess.TimeoutExpired:
        return ""


def nvim_remote_send(sock: str, keys: str) -> bool:
    """Send `keys` to a live Neovim server socket with a 5s timeout."""
    nvim_bin = resolve_nvim_bin()
    if not sock or not is_socket_path(sock) or not nvim_bin:
        return False
    try:
        res = subprocess.run(
            [nvim_bin, "--headless", "--server", sock, "--remote-send", keys],
            env=_nvim_rpc_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
        return res.returncode == 0
    except subprocess.TimeoutExpired:
        return False


def _nvim_recover_cwd_ex(fallback_dir: str = "") -> str:
    fb_esc = (
        fallback_dir.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("'", "''")
    )
    return (
        '"if exists(\\"*luaeval\\") | silent! call luaeval(\'(function() '
        "local u=vim.uv or vim.loop; if not u then return end; "
        "local function rec() "
        f'for _,c in ipairs({{vim.env.PWD or \\"\\",vim.env.IDE_WORKDIR or \\"\\",vim.env.IDE_INITIAL_ROOT or \\"\\",\\"{fb_esc}\\",vim.env.HOME or \\"\\"}}) do '
        'if c and c~=\\"\\" and vim.fn.isdirectory(c)==1 then '
        'local d,s=u.fs_stat(\\".\\"),u.fs_stat(c); '
        "if not u.cwd() or not d or d.nlink==0 or (vim.fn.haslocaldir()==0 and vim.fn.haslocaldir(-1,0)==0 and s and (d.dev~=s.dev or d.ino~=s.ino)) then "
        "pcall(vim.fn.chdir,c); vim.env.PWD=c end; return c end end; return nil end; "
        "rec(); "
        'if vim.fs and type(vim.fs.abspath)==\\"function\\" and not vim.fs._hs_abspath_wrapped then '
        "local orig=vim.fs.abspath; vim.fs._hs_abspath_wrapped=true; "
        "vim.fs.abspath=function(p) "
        "if not u.cwd() then rec() end; "
        "local ok,r=pcall(orig,p); if ok then return r end; "
        'local fb=rec() or vim.env.HOME or \\"/\\"; '
        'if type(p)==\\"string\\" then '
        'if p:sub(1,1)==\\"~\\" then p=vim.fs.normalize(p) end; '
        'if p:sub(1,1)==\\"/\\" then return vim.fs.normalize(p) end; '
        'return vim.fs.normalize(fb:gsub(\\"/+$\\",\\"\\")..\\"/\\"..p) end; '
        "return orig(p) end end end)()') | endif\""
    )


def nvim_recover_and_checktime(sock: str, fallback_dir: str = "", extra_ex: str = "") -> None:
    """Heal any stale Neovim server working directory over RPC and trigger `checktime`."""
    steps = [_nvim_recover_cwd_ex(fallback_dir), '"silent! checktime"']
    if extra_ex:
        steps.append(f'"{extra_ex}"')
    nvim_remote_expr(sock, f"execute([{', '.join(steps)}])")


def nvim_remote_file(sock: str, filepath: str, line: str = "", fallback_dir: str = "") -> None:
    """Open `filepath` (at optional `line`) in Neovim over RPC, recording a single `m'` jump mark."""
    escaped = filepath.replace("'", "''")
    fb_dir = fallback_dir
    if not fb_dir and filepath.startswith("/"):
        cand_dir = os.path.dirname(filepath)
        if os.path.isdir(cand_dir):
            fb_dir = cand_dir
    line_num = int(line) if line.isdigit() and int(line) > 0 else 0
    line_step = (
        f", 'keepjumps silent! call cursor({line_num}, 1) | silent! normal! zz'"
        if line_num > 0
        else ""
    )
    nvim_remote_expr(
        sock,
        "execute(["
        f"{_nvim_recover_cwd_ex(fb_dir)}, "
        '"if exists(\\"*luaeval\\") | silent! call luaeval(\'package.loaded[\\"mini.files\\"] and require(\\"mini.files\\").close()\') | endif", '
        '"if &filetype ==# \'netrw\' && winnr(\'\\$\') > 1 | wincmd p | endif", '
        '"stopinsert", '
        '"silent! normal! m\'", '
        f"'if fnamemodify(bufname(\"%\"), \":p\") !=# fnamemodify(' . string('{escaped}') . ', \":p\") | keepjumps silent! edit ' . fnameescape('{escaped}') . ' | endif'"
        f"{line_step}])",
    )


def nvim_modified_buf_count(sock: str) -> int:
    """Return the number of non-empty modified file buffers open in the Neovim server at `sock`."""
    if not sock or not is_socket_path(sock) or not resolve_nvim_bin():
        return 0
    mod_expr = (
        'len(filter(getbufinfo({"bufmodified": 1}), '
        '"getbufvar(v:val.bufnr, \\"&buftype\\") ==# \\"\\" && '
        '(!empty(v:val.name) || join(getbufline(v:val.bufnr, 1, \\"$\\"), \\"\\") !~# \\"^\\\\\\\\s*$\\")"))'
    )
    raw_mod = re.sub(r"[^0-9]", "", nvim_remote_expr(sock, mod_expr))
    return int(raw_mod) if raw_mod else 0


def send_editor_launch_keys(pane_id: str, sock: str, initial_file: str = "") -> None:
    """Send leading-space `nvim --listen <sock>` (or `vim` fallback) launch command to `pane_id`."""
    nvim_bin = resolve_nvim_bin()
    if nvim_bin:
        if sock:
            sock_parent = os.path.dirname(sock)
            if sock_parent and not os.path.isdir(sock_parent):
                try:
                    os.makedirs(sock_parent, mode=0o700, exist_ok=True)
                except OSError:
                    pass
            if is_socket_path(sock) and not is_live_socket(sock):
                try:
                    os.unlink(sock)
                except OSError:
                    pass
        run_tmux("set-option", "-p", "-t", pane_id, "@ide_nvim_launch_ts", str(int(time.time())))
        path_nvim = shutil.which("nvim")
        use_bare = os.path.basename(nvim_bin) == "nvim" and "/mise/" not in nvim_bin and nvim_bin == path_nvim
        cmd_name = "nvim" if use_bare else shlex.quote(nvim_bin)
        if initial_file:
            run_tmux("send-keys", "-t", pane_id, f" {cmd_name} --listen {shlex.quote(sock)} {shlex.quote(initial_file)}", "C-m")
        else:
            run_tmux("send-keys", "-t", pane_id, f" {cmd_name} --listen {shlex.quote(sock)}", "C-m")
    elif shutil.which("vim"):
        run_tmux("set-option", "-p", "-t", pane_id, "@ide_nvim_launch_ts", str(int(time.time())))
        run_tmux("send-keys", "-t", pane_id, " vim", "C-m")


def bind_nvim_server_socket(cand_sock: str, target_sock: str, sess: str = "") -> bool:
    """Bind `target_sock` onto the running Neovim server at `cand_sock` via `serverstart()`."""
    if not cand_sock or not target_sock or not resolve_nvim_bin():
        return False
    if is_live_socket(target_sock):
        return True
    sock_parent = os.path.dirname(target_sock)
    if sock_parent and not os.path.isdir(sock_parent):
        try:
            os.makedirs(sock_parent, mode=0o700, exist_ok=True)
        except OSError:
            return False
    if is_socket_path(target_sock):
        try:
            os.unlink(target_sock)
        except OSError:
            pass
    esc_s = target_sock.replace("\\", "\\\\").replace("'", "\\'")
    esc_n = sess.replace("\\", "\\\\").replace("'", "\\'")
    lua_fn = (
        "(function(s, n) "
        "if (vim.env.NVIM or '') ~= '' then return '0' end; "
        "if #vim.api.nvim_list_uis() == 0 then "
        "local argv = vim.v.argv or {}; "
        "for _, a in ipairs(argv) do "
        "if a == '--headless' or a == '-es' or a == '-Es' or a == '-e' or a == '-E' then return '0' end "
        "end; "
        "vim.wait(400, function() return #vim.api.nvim_list_uis() > 0 end, 15); "
        "if #vim.api.nvim_list_uis() == 0 then return '0' end "
        "end; "
        "local u = vim.uv or vim.loop; "
        "for _, srv in ipairs(vim.fn.serverlist()) do "
        "if srv == s then "
        "if u and u.fs_stat(s) then vim.env.NVIM_IDE_SOCKET = s; "
        "if n ~= '' then vim.env.IDE_SESSION = n end; return '1' end; "
        "pcall(vim.fn.serverstop, s); break end end; "
        "local ok, res = pcall(vim.fn.serverstart, s); "
        "if ok and res == s then vim.env.NVIM_IDE_SOCKET = s; "
        "if n ~= '' then vim.env.IDE_SESSION = n end; return '1' end; "
        f"return '0' end)('{esc_s}', '{esc_n}')"
    )
    expr = 'luaeval("' + lua_fn.replace("\\", "\\\\").replace('"', '\\"') + '")'
    out = nvim_remote_expr(cand_sock, expr)
    return out == "1" and is_live_socket(target_sock)


def heal_editor_nvim_socket(
    editor_pane: str,
    sock: str,
    sess: str = "",
    pane_pid_hint: str = "",
) -> bool:
    """Ensure `@ide_socket` (`sock`) is bound if Neovim is already running inside `editor_pane`."""
    if not sock:
        return False
    if is_live_socket(sock):
        return True
    if not editor_pane or not resolve_nvim_bin():
        return False
    pane_pid = (
        pane_pid_hint.strip()
        if pane_pid_hint
        else tmux_out("display-message", "-p", "-t", editor_pane, "#{pane_pid}").strip()
    )
    if not pane_pid:
        return False
    for cand in discover_pane_nvim_sockets(pane_pid, sock_hint=sock):
        if bind_nvim_server_socket(cand, sock, sess=sess):
            if sess:
                set_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET", sock)
            return True
    return False


def ensure_session_editor_socket(sess: str, sock: str = "", editor_pane: str = "") -> str:
    """Return `sess`'s `@ide_socket`, self-healing it over RPC if Editor Neovim is running."""
    if not sess:
        return sock
    if not sock:
        sock = get_ide_var(sess, "@ide_socket", "NVIM_IDE_SOCKET")
    if not sock:
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        sock = f"{runtime_dir}/nvim-ide-{sess}.sock"
    if is_live_socket(sock):
        return sock
    ed_pane = editor_pane or resolve_role_pane(sess, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
    if ed_pane:
        heal_editor_nvim_socket(ed_pane, sock, sess=sess)
    return sock


def heal_target_session_socket(target_arg: str = "") -> int:
    """Heal `@ide_socket` for `target_arg` (or the caller's IDE session) without changing focus."""
    sess = resolve_target_session(target_arg)
    if not sess or not session_exists(sess):
        return 1
    sock = ensure_session_editor_socket(sess)
    return 0 if (sock and is_live_socket(sock)) else 1


def wait_for_editor_socket(sess: str, sock: str = "", timeout_s: float = 3.0) -> str:
    """Return `sess`'s live `@ide_socket`, awaiting freshly launched `nvim --listen` when starting up."""
    if sock and is_live_socket(sock):
        return sock
    if not sess or not resolve_nvim_bin():
        return sock
    ed_pane = resolve_role_pane(sess, "editor", "@ide_editor_pane", "NVIM_IDE_PANE")
    sock = ensure_session_editor_socket(sess, sock, editor_pane=ed_pane)
    if sock and is_live_socket(sock):
        return sock
    if not ed_pane or not sock:
        return sock
    launch_ts = tmux_out("display-message", "-p", "-t", ed_pane, "#{@ide_nvim_launch_ts}").strip()
    if not (launch_ts.isdigit() and (int(time.time()) - int(launch_ts)) < 5):
        return sock
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        time.sleep(0.025)
        if is_live_socket(sock):
            return sock
    return ensure_session_editor_socket(sess, sock, editor_pane=ed_pane)


def ensure_editor_nvim_running(
    editor_pane: str,
    sock: str,
    initial_file: str = "",
    cached_cmd_ts: tuple[str, str] | None = None,
    sess: str = "",
    pane_pid_hint: str = "",
) -> bool:
    """Heal `@ide_socket` on a running Editor Neovim, or relaunch if exited back to a shell."""
    if not editor_pane or not sock:
        return False
    if is_live_socket(sock):
        return False
    if not resolve_nvim_bin():
        return False
    if cached_cmd_ts is not None and pane_pid_hint:
        cmd, launch_ts, pane_pid = cached_cmd_ts[0].strip(), cached_cmd_ts[1].strip(), pane_pid_hint.strip()
    elif cached_cmd_ts is not None:
        cmd, launch_ts = cached_cmd_ts[0].strip(), cached_cmd_ts[1].strip()
        pane_pid = tmux_out("display-message", "-p", "-t", editor_pane, "#{pane_pid}").strip()
    else:
        info = tmux_out(
            "display-message",
            "-p",
            "-t",
            editor_pane,
            TMUX_SEP.join(["#{pane_current_command}", "#{@ide_nvim_launch_ts}", "#{pane_pid}"]),
        )
        parts = (info.split(TMUX_SEP) + ["", "", ""])[:3]
        cmd, launch_ts, pane_pid = parts[0].strip(), parts[1].strip(), parts[2].strip()
    if pane_pid and heal_editor_nvim_socket(editor_pane, sock, sess=sess, pane_pid_hint=pane_pid):
        return False
    if not cmd or "nvim" in cmd or cmd in ("vim", "vi"):
        return False
    if launch_ts.isdigit() and (int(time.time()) - int(launch_ts)) < 5:
        return False
    if is_socket_path(sock):
        try:
            os.unlink(sock)
        except OSError:
            pass
    send_editor_launch_keys(editor_pane, sock, initial_file)
    return True
