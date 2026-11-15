#!/usr/bin/env bash
# Test suite for bin/ide multi-session fleet switcher, AI lifecycle state machine, and context dispatch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
. "$SCRIPT_DIR/tests/test-helper.sh"

echo "========================================"
echo "Running IDE Fleet & Lifecycle Tests"
echo "========================================"

# End-to-end hermetic multi-session workspace switcher, parked-window exclusion, live ANSI preview, and context dispatch tests
if command -v tmux >/dev/null 2>&1; then
    FLEET_TEST_OUT="$(python3 - "$SCRIPT_DIR" 2>&1 <<'PY'
import fcntl
import os
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time

repo_dir = sys.argv[1]
ide_src = os.path.join(repo_dir, "bin", "ide")
tmux_conf_src = os.path.join(repo_dir, "dotfiles", ".tmux.conf")

root = tempfile.mkdtemp(prefix="ide-fleet-suite.")
client_proc = None
client_mfd = None
client2_proc = None
client2_mfd = None
base_env = {}

def run_cmd(args, env=None, input_text=None, check=True, cwd=None):
    e = dict(base_env if env is None else env)
    return subprocess.run(
        args,
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=e,
        cwd=cwd,
        check=check,
    )

def tmux(*args, check=False):
    return run_cmd(["tmux", *args], env={**base_env, "TMUX": "", "TMUX_PANE": ""}, check=check)

def tmux_out(*args):
    r = tmux(*args, check=False)
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""

def wait_until(pred, timeout=3.0, step=0.03):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        val = pred()
        if val:
            return val
        time.sleep(step)
    return pred()

def nvim_expr_eq(sock, expr, expected):
    if not os.path.exists(sock):
        return False
    try:
        r = subprocess.run(
            ["nvim", "--headless", "--server", sock, "--remote-expr", expr],
            env=base_env,
            text=True,
            capture_output=True,
            timeout=2,
            check=False,
        )
        return r.returncode == 0 and r.stdout.strip() == expected
    except Exception:
        return False

try:
    thome = os.path.join(root, "home")
    tmux_tmp = os.path.join(root, "tmux_tmp")
    xdg_cfg = os.path.join(thome, ".config")
    xdg_cache = os.path.join(thome, ".cache")
    xdg_run = os.path.join(root, "run")
    bin_dir = os.path.join(thome, ".local", "bin")
    for d in (thome, tmux_tmp, xdg_cfg, xdg_cache, xdg_run, bin_dir):
        os.makedirs(d, mode=0o700, exist_ok=True)

    ide_bin = os.path.join(bin_dir, "ide")
    os.symlink(ide_src, ide_bin)
    os.symlink(tmux_conf_src, os.path.join(thome, ".tmux.conf"))

    clean_path = f"{bin_dir}:{os.environ.get('PATH', '/usr/bin:/bin')}"
    _raw_lang = os.environ.get("LANG", "")
    _utf8_lang = (
        _raw_lang
        if ("UTF-8" in _raw_lang.upper() or "UTF8" in _raw_lang.upper())
        else ("en_US.UTF-8" if sys.platform == "darwin" else "C.UTF-8")
    )
    base_env = {
        "HOME": thome,
        "PATH": clean_path,
        "TMUX_TMPDIR": tmux_tmp,
        "XDG_CONFIG_HOME": xdg_cfg,
        "XDG_CACHE_HOME": xdg_cache,
        "XDG_RUNTIME_DIR": xdg_run,
        "TERM": "xterm-256color",
        "LANG": _utf8_lang,
        "NO_COLOR": "1",
    }

    # 1. Server-down safety for --list, --list --plain, --sessions, and --send error paths
    r_plain0 = run_cmd([ide_bin, "--list", "--plain"], env={**base_env, "TMUX": ""}, check=False)
    assert r_plain0.returncode == 0 and r_plain0.stdout.strip() == "", f"plain0={r_plain0}"
    r_list0 = run_cmd([ide_bin, "--list"], env={**base_env, "TMUX": ""}, check=False)
    assert r_list0.returncode == 0 and "No active IDE sessions." in r_list0.stdout, f"list0={r_list0.stdout}"
    r_sess0 = run_cmd([ide_bin, "--sessions"], env={**base_env, "TMUX": ""}, check=False)
    assert r_sess0.returncode == 0 and "No active IDE sessions." in r_sess0.stdout, f"sess0={r_sess0.stdout}"
    r_ref0 = run_cmd([ide_bin, "--refresh"], env={**base_env, "TMUX": ""}, check=False)
    assert r_ref0.returncode == 0 and "No active IDE sessions." in r_ref0.stdout, f"ref0={r_ref0.stdout}"
    r_ref_missing0 = run_cmd([ide_bin, "--refresh", "missing-sess"], env={**base_env, "TMUX": ""}, check=False)
    assert r_ref_missing0.returncode != 0, "expected non-zero when --refresh targets missing session with server down"
    r_send_missing_mode = run_cmd([ide_bin, "--send"], env={**base_env, "TMUX": ""}, check=False)
    assert r_send_missing_mode.returncode != 0, "expected non-zero when --send has no payload flag"
    r_send_missing_sess = run_cmd([ide_bin, "--send", "--text", "hi", "missing-sess"], env={**base_env, "TMUX": ""}, check=False)
    assert r_send_missing_sess.returncode != 0, "expected non-zero when --send targets missing session"

    # Boot isolated server with non-IDE session + ai-*/agy-* popup sessions (all must be excluded)
    tmux("-f", os.path.join(thome, ".tmux.conf"), "new-session", "-d", "-s", "plain-non-ide", "-x", "160", "-y", "48", "exec sleep 300", check=True)
    tmux("new-session", "-d", "-s", "ai-alpha-ws", "-x", "120", "-y", "40", "exec sleep 300", check=True)
    tmux("new-session", "-d", "-s", "agy-beta-ws", "-x", "120", "-y", "40", "exec sleep 300", check=True)
    tmux("set-option", "-q", "-t", "=ai-alpha-ws:", "@ide_session", "ai-alpha-ws", check=True)
    tmux("set-option", "-q", "-t", "=agy-beta-ws:", "@ide_session", "agy-beta-ws", check=True)

    def make_ws(name, ai_cmd="exec sleep 300", ed_cmd="exec sleep 300", ai_cli="agy", git_branch="", git_dirty=False, in_home=False):
        ws_parent = os.path.join(thome, "projects") if in_home else os.path.join(root, "ws")
        ws_dir = os.path.join(ws_parent, name)
        os.makedirs(os.path.join(ws_dir, "sub"), exist_ok=True)
        with open(os.path.join(ws_dir, "README.md"), "w", encoding="utf-8") as f:
            f.write(f"# {name}\nline2\nline3\n")
        with open(os.path.join(ws_dir, "sub", "mod.py"), "w", encoding="utf-8") as f:
            f.write("\n".join(f"line_{i}" for i in range(1, 25)) + "\n")
        if git_branch:
            run_cmd(["git", "-C", ws_dir, "init", "-q", "-b", git_branch], check=True)
            run_cmd(["git", "-C", ws_dir, "config", "user.email", "test@example.com"], check=True)
            run_cmd(["git", "-C", ws_dir, "config", "user.name", "Test User"], check=True)
            run_cmd(["git", "-C", ws_dir, "add", "."], check=True)
            run_cmd(["git", "-C", ws_dir, "commit", "-q", "-m", "init"], check=True)
            if git_dirty:
                with open(os.path.join(ws_dir, "README.md"), "a", encoding="utf-8") as f:
                    f.write("dirty\n")

        sock_path = os.path.join(xdg_run, f"nvim-ide-{name}.sock")
        env_flags = [
            "-e", f"IDE_SESSION={name}",
            "-e", f"IDE_AI_CLI={ai_cli}",
            "-e", f"NVIM_IDE_SOCKET={sock_path}",
            "-e", f"IDE_INITIAL_ROOT={ws_dir}",
        ]
        ai_shell = "/bin/sh" if ai_cmd == "exec /bin/sh" else f"/bin/sh -c {shlex.quote(ai_cmd + '; :')}"
        ed_shell = "exec sleep 300" if ed_cmd == "exec sleep 300" else f"/bin/sh -c {shlex.quote(ed_cmd + '; :')}"
        init = tmux_out(
            "new-session", "-d", "-P", "-F", "#{pane_id}\t#{window_id}",
            "-s", name, "-n", "ide", "-c", ws_dir, "-x", "160", "-y", "48",
            *env_flags, ai_shell,
        )
        p_ai, m_win = init.split("\t")
        p_ed = tmux_out("split-window", "-h", "-P", "-F", "#{pane_id}", "-t", p_ai, "-l", "50%", "-c", ws_dir, *env_flags, ed_shell)
        p_tm = tmux_out("split-window", "-f", "-v", "-P", "-F", "#{pane_id}", "-t", m_win, "-l", "25%", "-c", ws_dir, *env_flags, "exec /bin/sh")
        tmux(
            "set-option", "-w", "-t", m_win, "automatic-rename", "off", ";",
            "set-option", "-w", "-t", m_win, "allow-rename", "off", ";",
            "set-option", "-p", "-t", p_ai, "@ide_role", "ai", ";",
            "set-option", "-p", "-t", p_ed, "@ide_role", "editor", ";",
            "set-option", "-p", "-t", p_tm, "@ide_role", "term", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_session", name, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_cli", ai_cli, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_socket", sock_path, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_initial_root", ws_dir, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_workdir", ws_dir, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_main_win", m_win, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_pane", p_ai, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_editor_pane", p_ed, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_term_pane", p_tm, ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_layout_mode", "3pane", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ai_parked", "0", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_ed_parked", "0", ";",
            "set-option", "-q", "-t", f"={name}:", "@ide_term_parked", "0", ";",
            "set-environment", "-t", f"={name}", "IDE_SESSION", name, ";",
            "select-pane", "-t", p_ai,
            check=True,
        )
        return {"dir": ws_dir, "win": m_win, "ai": p_ai, "ed": p_ed, "tm": p_tm}

    def sess_env(sess, pane=""):
        meta = tmux_out("display-message", "-p", "-t", f"={sess}:", "#{socket_path},#{pid},#{session_id}\t#{pane_id}")
        t_env, p_id = meta.split("\t")
        return {**base_env, "TMUX": t_env, "TMUX_PANE": pane or p_id, "IDE_SESSION": sess}

    # 2. Create 3 IDE workspaces with distinct agents, Git states, and home-shortened vs non-home paths
    ws_alpha = make_ws(
        "alpha-ws",
        ai_cmd="printf '\\033[36mALPHA_AI_VIEWPORT_LINE\\033[0m\\n'; sleep 300",
        ed_cmd="printf 'ALPHA_EDITOR_VIEWPORT_LINE\\n'; sleep 300",
        ai_cli="claude",
        git_branch="feat/switcher",
        git_dirty=True,
        in_home=True,
    )
    ws_beta = make_ws(
        "beta-ws",
        ai_cmd="printf 'BETA_AI_READY\\n'; sleep 300",
        ed_cmd="printf 'BETA_EDITOR_VISIBLE_LINE\\n'; sleep 300",
        ai_cli="codex",
        git_branch="main",
        git_dirty=False,
        in_home=True,
    )
    ws_gamma = make_ws(
        "gamma-ws",
        ai_cmd="printf 'GAMMA_SHELL_VIEW\\n'; sleep 300",
        ai_cli="agy",
        git_branch="",
        in_home=False,
    )

    assert wait_until(
        lambda: "ALPHA_AI_VIEWPORT_LINE" in tmux_out("capture-pane", "-p", "-t", ws_alpha["ai"])
        and "BETA_EDITOR_VISIBLE_LINE" in tmux_out("capture-pane", "-p", "-t", ws_beta["ed"])
        and "GAMMA_SHELL_VIEW" in tmux_out("capture-pane", "-p", "-t", ws_gamma["ai"]),
        timeout=4.0,
    ), "timed out waiting for workspace pane viewports"

    # Wait past gamma-ws's integer timestamp so send-keys bumps beta-ws #{window_activity} deterministically
    gamma_ts = max(
        (int(x) for x in tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{session_activity} #{window_activity}").split() if x.isdigit()),
        default=int(time.time()),
    )
    while int(time.time()) <= gamma_ts:
        time.sleep(0.05)
    tmux("send-keys", "-t", ws_beta["tm"], "echo activity_bump", "C-m", check=True)
    assert wait_until(
        lambda: "activity_bump" in tmux_out("capture-pane", "-p", "-t", ws_beta["tm"])
        and int(tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{window_activity}") or "0") > gamma_ts
    )

    plain_lines = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("alpha-ws"), check=True).stdout.splitlines()
    assert plain_lines == ["alpha-ws", "beta-ws", "gamma-ws"], f"unexpected --list --plain order: {plain_lines}"
    assert "plain-non-ide" not in plain_lines and "ai-alpha-ws" not in plain_lines and "agy-beta-ws" not in plain_lines

    list_out = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws"), check=True).stdout
    list_lines = [ln for ln in list_out.splitlines() if ln.strip()]
    assert "SESSION" in list_lines[0] and "AGENT" in list_lines[0] and "STATE" in list_lines[0] and "BRANCH" in list_lines[0] and "WORKSPACE" in list_lines[0], f"bad header: {list_lines[0]}"
    assert list_lines[1].startswith("* alpha-ws") and "claude" in list_lines[1] and " - " in list_lines[1] and "feat/switcher*" in list_lines[1] and "~/projects/alpha-ws" in list_lines[1], f"bad row1: {list_lines[1]}"
    assert "beta-ws" in list_lines[2] and "codex" in list_lines[2] and " - " in list_lines[2] and "main" in list_lines[2] and "main*" not in list_lines[2] and "~/projects/beta-ws" in list_lines[2], f"bad row2: {list_lines[2]}"
    assert "gamma-ws" in list_lines[3] and "agy" in list_lines[3] and " - " in list_lines[3], f"bad row3: {list_lines[3]}"

    # 3. Live ANSI --session-preview & _ide_park_* exclusion
    prev_alpha = run_cmd([ide_bin, "--session-preview", "alpha-ws"], env={**sess_env("alpha-ws"), "NO_COLOR": ""}, check=True).stdout
    assert "alpha-ws" in prev_alpha and "claude" in prev_alpha and "State:" in prev_alpha and "feat/switcher (" in prev_alpha, f"bad alpha preview header: {prev_alpha}"
    assert "\x1b[36mALPHA_AI_VIEWPORT_LINE" in prev_alpha, f"expected live ANSI sequence from AI pane in preview: {prev_alpha!r}"

    # Park beta-ws AI pane into _ide_park_ai -> preview must skip _ide_park_ai and render visible Editor pane instead!
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    prev_beta_parked = run_cmd([ide_bin, "--session-preview", "beta-ws"], env=sess_env("alpha-ws"), check=True).stdout
    assert "BETA_EDITOR_VISIBLE_LINE" in prev_beta_parked and "BETA_AI_READY" not in prev_beta_parked, f"parked _ide_park_ai leaked into preview: {prev_beta_parked}"

    # Non-git preview uses calm BASE01 (#586E75 -> 88;110;117), never Green (#859900 -> 133;153;0)
    prev_gamma = run_cmd([ide_bin, "--session-preview", "gamma-ws"], env={**sess_env("alpha-ws"), "NO_COLOR": ""}, check=True).stdout
    git_line_gamma = next((ln for ln in prev_gamma.splitlines() if "Git      :" in ln), "")
    assert "not a git repository" in git_line_gamma and "38;2;88;110;117mnot a git repository" in git_line_gamma, f"non-git line wrong color: {git_line_gamma!r}"
    prev_missing = run_cmd([ide_bin, "--session-preview", "no-such-ws"], env=sess_env("alpha-ws"), check=True).stdout
    assert "Session is no longer active." in prev_missing

    # 4. Attach real PTY client to alpha-ws & verify status_click() column accuracy on calm 3-state status bar
    def set_ctty(sfd):
        os.setsid()
        fcntl.ioctl(sfd, termios.TIOCSCTTY, 0)

    client_mfd, client_sfd = pty.openpty()
    fcntl.ioctl(client_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
    client_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=alpha-ws"],
        stdin=client_sfd,
        stdout=client_sfd,
        stderr=client_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        close_fds=True,
        preexec_fn=lambda sfd=client_sfd: set_ctty(sfd),
    )
    os.close(client_sfd)

    def drain_pty():
        while True:
            r, _, _ = select.select([client_mfd], [], [], 0)
            if not r:
                break
            try:
                if not os.read(client_mfd, 8192):
                    break
            except OSError:
                break

    client_name = wait_until(lambda: (drain_pty() or tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_name}").strip()))
    assert client_name, "failed to attach PTY tmux client to alpha-ws"

    run_cmd([ide_bin, "--focus-editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    sleft_raw = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-left}")
    wcur_raw = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    strip_tags = lambda s: re.sub(r"#\[[^\]]*\]", "", s)
    sleft_plain = strip_tags(sleft_raw)
    wcur_plain = strip_tags(wcur_raw)
    ed_col = len(sleft_plain) + wcur_plain.index("Editor") + 2
    sh_col = len(sleft_plain) + wcur_plain.index("Shell") + 2

    run_cmd([ide_bin, "--status-click", str(sh_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd([ide_bin, "--status-click", str(ed_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["tm"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # 5. Interactive Workspace Switcher (ide -s / --sessions) with mock IDE_FZF_BIN (in-process + live display-popup)
    mock_fzf = os.path.join(root, "mock-fzf.py")
    with open(mock_fzf, "w", encoding="utf-8") as f:
        f.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "assert all('\\t' in l for l in lines), f'missing tab delimiter: {lines}'\n"
            "rc = int(os.environ.get('MOCK_FZF_EXIT', '0'))\n"
            "if rc != 0:\n"
            "    sys.exit(rc)\n"
            "target = os.environ.get('MOCK_FZF_TARGET', '')\n"
            "key = os.environ.get('MOCK_FZF_KEY', '')\n"
            "picked = next((l for l in lines if l.split('\\t', 1)[0] == target), lines[0])\n"
            "print(key)\n"
            "print(picked)\n"
        )
    os.chmod(mock_fzf, 0o755)

    # alt-s abort (exit 130) returns 0 cleanly without switching
    r_abort = run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_EXIT": "130", "IDE_CLIENT": client_name},
        check=False,
    )
    assert r_abort.returncode == 0
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # Enter (empty --expect key) switches session preserving target's focused pane
    run_cmd([ide_bin, "--focus-editor", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    run_cmd(
        [ide_bin, "-s", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "", "MOCK_FZF_TARGET": "gamma-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "editor"
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    drain_pty()

    # ctrl-e does NOT bounce when editor is already active
    run_cmd(
        [ide_bin, "-s", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-e", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # ctrl-t unparks parked Shell and does NOT bounce when Shell is already active
    run_cmd([ide_bin, "--toggle-term", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_term_parked") == "1"
    run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-t", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_term_parked") == "0"
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["tm"]), "IDE_NO_POPUP": "1", "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-t", "MOCK_FZF_TARGET": "alpha-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"

    # Live display-popup path: switches attached PTY client to beta-ws and unparks its parked AI pane via ctrl-a!
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    tmux("set-environment", "-g", "IDE_FZF_BIN", mock_fzf, check=True)
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "ctrl-a", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    run_cmd(
        [ide_bin, "--sessions", "alpha-ws"],
        env={**sess_env("alpha-ws", ws_alpha["tm"]), "IDE_FZF_BIN": mock_fzf, "MOCK_FZF_KEY": "ctrl-a", "MOCK_FZF_TARGET": "beta-ws", "IDE_CLIENT": client_name},
        check=True,
    )
    drain_pty()
    assert wait_until(lambda: (drain_pty() or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws")), "live display-popup --sessions did not switch client to beta-ws"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "0"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai"

    # 6. Context Dispatch (ide --send: --ref, L1==L2, empty no-op, after icd, external path, --text --no-focus, --stdin, live copy-mode-vi 'a', and untouched default tmux buffer)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("set-buffer", "SACRED_DEFAULT_BUFFER", check=True)
    recv_root = os.path.join(root, "ai_recv_root.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_root}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "--focus-editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)

    # Empty payloads (--stdin empty, --text "", --ref "   ") return 0 WITHOUT switching focus away from Editor!
    run_cmd([ide_bin, "--send", "--stdin", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), input_text="", check=True)
    run_cmd([ide_bin, "--send", "--text", "", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--ref", "   ", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "empty --send payload spuriously switched focus away from Editor"

    mod_file = os.path.join(ws_alpha["dir"], "sub", "mod.py")
    run_cmd([ide_bin, "--send", "--ref", f"{mod_file}:10-20", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "ai"

    # L1 == L2 normalizes to #L15
    run_cmd([ide_bin, "--send", "--ref", f"{mod_file}:15-15", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)

    # --no-focus keeps Editor focused
    run_cmd([ide_bin, "--focus-editor", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--text", "[NOFOCUS]", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # --stdin (all ide --send calls must leave default tmux buffer untouched)
    run_cmd([ide_bin, "--send", "--stdin", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), input_text="[STDIN_OK]", check=True)
    assert tmux_out("show-buffer") == "SACRED_DEFAULT_BUFFER", f"default tmux buffer clobbered by ide --send: {tmux_out('show-buffer')!r}"
    assert "_ide_send_" not in tmux_out("list-buffers"), "temporary _ide_send_ buffer leaked"

    # Live Tmux copy-mode-vi 'a' binding from Shell pane
    tmux("send-keys", "-t", ws_alpha["tm"], "echo COPY_MODE_PAYLOAD", "C-m", check=True)
    assert wait_until(lambda: "\nCOPY_MODE_PAYLOAD" in "\n" + tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"])), "missing COPY_MODE_PAYLOAD in Shell pane"
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("copy-mode", "-t", ws_alpha["tm"], check=True)
    drain_pty()
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "search-backward", "COPY_MODE_PAYLOAD", check=True)
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "begin-selection", check=True)
    tmux("send-keys", "-t", ws_alpha["tm"], "-X", "next-space-end", check=True)
    os.write(client_mfd, b"a")

    def root_recv_complete():
        drain_pty()
        if not os.path.isfile(recv_root):
            return False
        data = open(recv_root, encoding="utf-8", errors="replace").read()
        return "COPY_MODE_PAYLOAD" in data
    assert wait_until(root_recv_complete, timeout=3.0), f"copy-mode-vi 'a' payload never reached AI pane: {open(recv_root).read() if os.path.isfile(recv_root) else 'missing'}"
    got_root = open(recv_root, encoding="utf-8", errors="replace").read()
    clean_root = got_root.replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert "@sub/mod.py#L10-L20 @sub/mod.py#L15 [NOFOCUS][STDIN_OK]COPY_MODE_PAYLOAD" == clean_root, f"unexpected AI root stream: {clean_root!r}"
    assert "_ide_send_" not in tmux_out("list-buffers"), "temporary _ide_send_ buffer leaked after copy-mode-vi"

    # Relative path resolution after icd into subdirectory (<ws>/sub) + outside-workspace fallback
    recv_sub = os.path.join(root, "ai_recv_sub.txt")
    sub_dir = os.path.join(ws_alpha["dir"], "sub")
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_workdir", sub_dir, check=True)
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", sub_dir,
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_sub}'",
        check=True,
    )
    time.sleep(0.1)
    readme_file = os.path.join(ws_alpha["dir"], "README.md")
    ext_file = os.path.join(root, "outside-ws.txt")
    with open(ext_file, "w", encoding="utf-8") as f:
        f.write("ext\n")
    ext_real = os.path.realpath(ext_file)
    run_cmd([ide_bin, "--send", "--ref", f"{mod_file}:7", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--ref", f"{readme_file}:1-3", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    run_cmd([ide_bin, "--send", "--ref", f"{ext_file}:4", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert wait_until(lambda: os.path.isfile(recv_sub) and ext_real in open(recv_sub, encoding="utf-8").read()), "subdir --ref payloads did not arrive"
    clean_sub = open(recv_sub, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert clean_sub == f"@mod.py#L7 @../README.md#L1-L3 @{ext_real}#L4 ", f"unexpected AI subdir stream: {clean_sub!r}"

    # 7. Multi-client Alt+s isolation, non-IDE Alt+s, relative invocation, popup ctrl-x self-quit + reload highlight, --ref/--send edge cases, and dirty-buffer --quit guard
    popup_env_log = os.path.join(root, "popup_env.txt")
    with open(mock_fzf, "w", encoding="utf-8") as f:
        f.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"with open({popup_env_log!r}, 'w', encoding='utf-8') as out:\n"
            "    out.write(os.environ.get('IDE_CLIENT', '') + '\\t' + os.environ.get('FZF_DEFAULT_OPTS', '') + '\\t' + ' '.join(sys.argv[1:]))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "target = os.environ.get('MOCK_FZF_TARGET', '')\n"
            "key = os.environ.get('MOCK_FZF_KEY', '')\n"
            "picked = next((l for l in lines if l.split('\\t', 1)[0] == target), lines[0])\n"
            "print(key)\n"
            "print(picked)\n"
        )
    os.chmod(mock_fzf, 0o755)

    # (7a) Attach second PTY client (client2) to alpha-ws while client1 stays on alpha-ws; press real Alt+s (\x1bs) on client2
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    drain_pty()
    client2_mfd, client2_sfd = pty.openpty()
    fcntl.ioctl(client2_sfd, termios.TIOCSWINSZ, struct.pack("HHHH", 48, 160, 0, 0))
    client2_proc = subprocess.Popen(
        ["tmux", "attach-session", "-t", "=alpha-ws"],
        stdin=client2_sfd,
        stdout=client2_sfd,
        stderr=client2_sfd,
        env={**base_env, "TMUX": "", "TMUX_PANE": ""},
        close_fds=True,
        preexec_fn=lambda sfd=client2_sfd: set_ctty(sfd),
    )
    os.close(client2_sfd)

    def drain_pty_both():
        drain_pty()
        while True:
            r, _, _ = select.select([client2_mfd], [], [], 0)
            if not r:
                break
            try:
                if not os.read(client2_mfd, 8192):
                    break
            except OSError:
                break

    def find_client2():
        drain_pty_both()
        cls = [c.strip() for c in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_name}").splitlines() if c.strip() and c.strip() != client_name]
        return cls[0] if cls else ""

    client2_name = wait_until(find_client2)
    assert client2_name, "failed to attach second PTY client to alpha-ws"

    tmux("set-environment", "-g", "IDE_FZF_BIN", mock_fzf, check=True)
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    if os.path.exists(popup_env_log):
        os.unlink(popup_env_log)
    os.write(client2_mfd, b"\x1bs")
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "beta-ws")), "Alt+s on client2 did not switch client2 to beta-ws"
    time.sleep(0.2)
    drain_pty_both()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws", "Alt+s on client2 wrongly switched client1!"
    recorded_env = open(popup_env_log, encoding="utf-8").read()
    rec_client, rec_default_fzf, _ = recorded_env.split("\t", 2)
    assert rec_client == client2_name and "#{" not in recorded_env, f"unexpanded format or wrong IDE_CLIENT in popup: {recorded_env!r}"
    assert "spinner:#859900" in rec_default_fzf and "prompt:#B58900" in rec_default_fzf, f"unexpected default FZF_DEFAULT_OPTS palette: {rec_default_fzf!r}"

    # Real Alt+s from non-IDE session (plain-non-ide) switches client2 cleanly into gamma-ws
    tmux("switch-client", "-c", client2_name, "-t", "=plain-non-ide", check=True)
    time.sleep(0.1)
    drain_pty_both()
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "gamma-ws", check=True)
    os.write(client2_mfd, b"\x1bs")
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "gamma-ws")), "Alt+s on non-IDE session did not switch client2 to gamma-ws"
    time.sleep(0.2)
    drain_pty_both()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"

    # (7b) Relative invocation (./.local/bin/ide -s) + build_fzf_env single-quoted theme-env.sh overriding stale FZF_DEFAULT_OPTS
    hs_cfg_dir = os.path.join(thome, ".config", "home-settings")
    os.makedirs(hs_cfg_dir, exist_ok=True)
    theme_env_file = os.path.join(hs_cfg_dir, "theme-env.sh")
    with open(theme_env_file, "w", encoding="utf-8") as tf:
        tf.write("export FZF_DEFAULT_OPTS='--color=bg+:#313244,bg:#1E1E2E,spinner:#A6E3A1 --prompt='\\''WS> '\\'' --border=rounded'\n")
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "beta-ws", check=True)
    run_cmd(
        ["./.local/bin/ide", "-s", "gamma-ws"],
        env={
            **sess_env("gamma-ws", ws_gamma["ed"]),
            "FZF_DEFAULT_OPTS": "--color=bg+:#000000",
            "IDE_FZF_BIN": mock_fzf,
            "MOCK_FZF_KEY": "",
            "MOCK_FZF_TARGET": "beta-ws",
            "IDE_CLIENT": client2_name,
        },
        cwd=thome,
        check=True,
    )
    assert wait_until(lambda: (drain_pty_both() or tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}") == "beta-ws")), "relative ./ide -s popup failed"
    _, rel_fzf_opts, rel_fzf_args = open(popup_env_log, encoding="utf-8").read().split("\t", 2)
    os.unlink(theme_env_file)
    assert "--color=bg+:#313244" in rel_fzf_opts and "--prompt='WS> '" in rel_fzf_opts and "#000000" not in rel_fzf_opts, f"build_fzf_env failed to load single-quoted/escaped theme-env.sh over stale FZF_DEFAULT_OPTS: {rel_fzf_opts!r}"
    assert os.path.abspath(ide_bin) in rel_fzf_args or os.path.realpath(ide_bin) in rel_fzf_args, f"relative path leaked into fzf args: {rel_fzf_args}"
    assert "--multi" in rel_fzf_args and "--quit {+1}" in rel_fzf_args, f"expected --multi and --quit {{+1}} in fzf args: {rel_fzf_args}"
    assert (
        "--border=rounded" in rel_fzf_args
        and "--border-label-pos=bottom" in rel_fzf_args
        and "--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · C-x: quit · C-r: reload · Alt+s: close " in rel_fzf_args
        and "--color=label:#586E75" in rel_fzf_args
        and "--header=" not in rel_fzf_args
    ), f"expected bottom border-label in fzf args: {rel_fzf_args}"

    # Verify session_last_attached promotes recently visited gamma-ws above beta-ws
    beta_max_ts = max(
        (int(x) for x in tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{session_activity} #{session_last_attached} #{window_activity}").split() if x.isdigit()),
        default=int(time.time()),
    )
    while int(time.time()) <= beta_max_ts:
        time.sleep(0.05)
    tmux("switch-client", "-c", client2_name, "-t", "=gamma-ws", check=True)
    drain_pty_both()
    recency_after_switch = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("alpha-ws"), check=True).stdout.splitlines()
    assert recency_after_switch == ["alpha-ws", "gamma-ws", "beta-ws"], f"session_last_attached did not promote gamma-ws: {recency_after_switch}"

    # (7c) Quitting the active session from inside the popup (IDE_IN_POPUP=1, ctrl-x) switches attached client to the most recently active surviving IDE session, and --sessions-lines re-highlights the new session
    ws_killme = make_ws("killme-ws", ai_cmd="sleep 300")
    tmux("switch-client", "-c", client2_name, "-t", "=killme-ws", check=True)
    drain_pty_both()
    run_cmd([ide_bin, "--quit", "killme-ws"], env={**sess_env("killme-ws", ws_killme["ed"]), "IDE_IN_POPUP": "1", "IDE_CLIENT": client2_name}, check=True)
    drain_pty_both()
    surviving_sess = tmux_out("display-message", "-p", "-t", client2_name, "#{session_name}")
    assert surviving_sess in ("alpha-ws", "beta-ws", "gamma-ws"), f"popup self-quit switched to unexpected session: {surviving_sess!r}"
    reloaded_rows = run_cmd([ide_bin, "--sessions-lines", "killme-ws"], env={**base_env, "IDE_IN_POPUP": "1", "IDE_CLIENT": client2_name}, check=True).stdout.splitlines()
    assert reloaded_rows and reloaded_rows[0].split("\t", 1)[0] == surviving_sess and "▸" in reloaded_rows[0], f"reload after ctrl-x did not highlight new client session {surviving_sess}: {reloaded_rows}"

    # (7d) Relative --ref from outside workspace CWD, '#' in filename, reversed flag order (--ref ... --send), and '--' leading-dash text
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_workdir", ws_alpha["dir"], check=True)
    hash_file = os.path.join(ws_alpha["dir"], "sub", "issue#12")
    with open(hash_file, "w", encoding="utf-8") as f:
        f.write("tracked\n")
    recv_edge = os.path.join(root, "ai_recv_edge.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_edge}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "--ref", "sub/mod.py:4-4", "--send", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "--send", "--ref", "sub/issue#12", "--no-focus", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "--send", "--no-focus", "--text", "- leading-dash ", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    run_cmd([ide_bin, "--send", "--no-focus", "--", "--literal-end", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), cwd=root, check=True)
    assert wait_until(lambda: os.path.isfile(recv_edge) and "--literal-end" in open(recv_edge, encoding="utf-8").read()), "edge --send payloads did not arrive"
    clean_edge = open(recv_edge, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert clean_edge == "@sub/mod.py#L4 @sub/issue#12 - leading-dash --literal-end", f"unexpected edge --send stream: {clean_edge!r}"

    # (7e) ide --quit refuses to close workspace when Neovim server has unsaved changes (while closing clean sibling sessions); --quit --force closes it
    if shutil.which("nvim"):
        ws_dirty = make_ws("dirty-ws", ai_cmd="sleep 300")
        ws_clean_sib = make_ws("clean-sib-ws", ai_cmd="sleep 300")
        dirty_sock = tmux_out("show-options", "-qv", "-t", "=dirty-ws:", "@ide_socket")
        dirty_file = os.path.join(ws_dirty["dir"], "unsaved.txt")
        tmux(
            "respawn-pane", "-k", "-t", ws_dirty["ed"], "-c", ws_dirty["dir"],
            f"nvim --headless -u NONE -i NONE --listen {shlex.quote(dirty_sock)} -c {shlex.quote('edit ' + dirty_file)} -c \"call setline(1, 'dirty')\"",
            check=True,
        )
        assert wait_until(lambda: nvim_expr_eq(dirty_sock, "&modified", "1")), "dirty-ws nvim buffer did not become modified"
        r_dirty_quit = run_cmd([ide_bin, "--quit", "dirty-ws", "clean-sib-ws"], env={**base_env, "TMUX": ""}, check=False)
        assert r_dirty_quit.returncode != 0, f"expected ide --quit to refuse dirty buffer, got {r_dirty_quit}"
        assert tmux("has-session", "-t", "=dirty-ws", check=False).returncode == 0, "dirty-ws was killed despite unsaved buffer!"
        assert tmux("has-session", "-t", "=clean-sib-ws", check=False).returncode != 0, "clean-sib-ws should have been closed alongside dirty-ws check!"
        run_cmd([ide_bin, "--quit", "--force", "dirty-ws"], env={**base_env, "TMUX": ""}, check=True)
        assert tmux("has-session", "-t", "=dirty-ws", check=False).returncode != 0, "dirty-ws survived --quit --force"

    # 8. Deterministic Hook-Only AI Lifecycle State, Zero Heuristic Invention, FIFO --next-attention, Parked AI Preservation, Stale-Hook SHELL Guard, and Top-Bar Width Invariance
    ide_src = open(ide_bin, encoding="utf-8").read()
    for banned_heuristic in ("inspect_fleet_procs", "inspect_ai_viewport", "alert-bell", "--on-bell"):
        assert banned_heuristic not in ide_src, f"heuristic remnant {banned_heuristic!r} found in bin/ide"

    # Detach client2 so client_name is the sole attached viewer on alpha-ws Editor pane
    tmux("detach-client", "-t", client2_name, check=False)
    drain_pty_both()
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "/bin/sh -c 'sleep 300; :'", check=True)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    drain_pty()

    # (8a) Prompt-like text + terminal bell (\a) in gamma-ws AI pane MUST NOT invent WORKING or ATTN without hooks!
    tmux(
        "respawn-pane", "-k", "-t", ws_gamma["ai"], "-c", ws_gamma["dir"],
        "/bin/sh -c 'printf \"Allow tool execution? [Y/n] \\a\\n\"; sleep 300; :'",
        check=True,
    )
    assert wait_until(lambda: "Allow tool execution" in tmux_out("capture-pane", "-p", "-t", ws_gamma["ai"]))
    run_cmd([ide_bin, "--refresh-attn"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    assert tmux_out("show-options", "-gqv", "@ide_fleet_count") == "3"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"
    sright_idle = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|fleet]#[fg=#839496,bg=#073642,nobold] 3 · 0 active (Alt+s)" in sright_idle, f"bad idle fleet pill: {sright_idle!r}"

    # (8b) Unfocused @ide_tab_ai character width invariance across all 4 states:
    # neutral -> running (Cyan) -> unacknowledged done (Green) -> approval (Orange), both visible and parked!
    wcur_neutral = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wcur_running = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    sright_active = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|fleet]#[fg=#839496,bg=#073642,nobold] 3 · #[fg=#2AA198,bg=#073642,nobold]1 active#[fg=#839496,bg=#073642,nobold] (Alt+s)" in sright_active, f"bad active fleet pill: {sright_active!r}"

    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    wcur_done = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")

    run_cmd([ide_bin, "--agent-state", "quota", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "quota"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "0"
    wcur_quota = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")

    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wcur_approval = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert strip_tags(wcur_neutral) == strip_tags(wcur_running) == strip_tags(wcur_done) == strip_tags(wcur_quota) == strip_tags(wcur_approval), (
        f"@ide_tab_ai shifted character width! neutral={strip_tags(wcur_neutral)!r} running={strip_tags(wcur_running)!r} done={strip_tags(wcur_done)!r} quota={strip_tags(wcur_quota)!r} approval={strip_tags(wcur_approval)!r}"
    )
    assert "fg=#839496,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_neutral, f"expected Base0 neutral tint: {wcur_neutral!r}"
    assert "fg=#2AA198,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_running, f"expected Cyan running tint: {wcur_running!r}"
    assert "fg=#859900,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_done, f"expected Green unacknowledged done tint: {wcur_done!r}"
    assert "fg=#B58900,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_quota, f"expected Yellow quota tint: {wcur_quota!r}"
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 codex (Alt+a)" in wcur_approval, f"expected Orange approval tint: {wcur_approval!r}"

    # Verify parked [Alt+a] @ide_tab_ai across all 5 states as well (zero character width shift)
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    wpark_approval = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "idle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_neutral = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_running = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "quota", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_quota = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    wpark_done = tmux_out("display-message", "-p", "-t", ws_beta["ed"], "#{E:window-status-current-format}")
    assert strip_tags(wpark_neutral) == strip_tags(wpark_running) == strip_tags(wpark_quota) == strip_tags(wpark_done) == strip_tags(wpark_approval), (
        f"parked @ide_tab_ai shifted character width! neutral={strip_tags(wpark_neutral)!r} running={strip_tags(wpark_running)!r} quota={strip_tags(wpark_quota)!r} done={strip_tags(wpark_done)!r} approval={strip_tags(wpark_approval)!r}"
    )
    assert "fg=#586E75,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_neutral, f"expected Base01 parked neutral: {wpark_neutral!r}"
    assert "fg=#2AA198,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_running, f"expected Cyan parked running: {wpark_running!r}"
    assert "fg=#B58900,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_quota, f"expected Yellow parked quota: {wpark_quota!r}"
    assert "fg=#859900,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_done, f"expected Green parked done: {wpark_done!r}"
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 codex [Alt+a]" in wpark_approval, f"expected Orange parked approval: {wpark_approval!r}"
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)

    # Verify status_click still clicks Editor & Shell accurately when @ide_tab_ai is tinted!
    run_cmd([ide_bin, "--status-click", str(sh_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term"
    run_cmd([ide_bin, "--status-click", str(ed_col), "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["tm"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor"

    # (8c) Foreground done vs Background done + Mixed FIFO queue (beta-ws approval, gamma-ws background done)
    # Foreground done: when alpha-ws is attached and its AI pane IS focused, done sets @ide_ai_attn=0 (not queued)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    drain_pty()
    run_cmd([ide_bin, "--agent-state", "done", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "foreground done while viewing AI pane must not set @ide_ai_attn=1!"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn_ts") == ""
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws", "foreground done must not enter @ide_attn_summary!"
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    drain_pty()
    wcur_alpha_fg_done = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    assert "fg=#839496,bg=#073642,nobold]󰚩 claude (Alt+a)" in wcur_alpha_fg_done, f"acknowledged foreground done must stay neutral Base0: {wcur_alpha_fg_done!r}"
    list_fg_done = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout
    assert any("alpha-ws" in ln and "DONE" in ln for ln in list_fg_done.splitlines()), f"expected DONE for alpha-ws: {list_fg_done}"
    run_cmd([ide_bin, "--agent-state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    list_idle = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout
    assert any("alpha-ws" in ln and "IDLE" in ln for ln in list_idle.splitlines()), f"expected IDLE for alpha-ws: {list_idle}"

    # Background done: gamma-ws finishes turn while detached -> @ide_ai_attn=1, @ide_attn_summary == "beta-ws +1", FIFO order
    time.sleep(0.03)
    run_cmd([ide_bin, "--agent-state", "done", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws +1"
    sright_attn = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:status-right}")
    assert "range=user|attn]#[fg=#CB4B16,bg=#073642,nobold]󰂚 beta-ws +1 " in sright_attn, f"missing urgent attn pill: {sright_attn!r}"

    fifo_plain = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout.splitlines()
    assert fifo_plain == ["beta-ws", "gamma-ws", "alpha-ws"], f"mixed ATTN + background DONE FIFO sort failed: {fifo_plain}"

    list_mixed_plain = run_cmd([ide_bin, "--list"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True).stdout.splitlines()
    assert any(ln.lstrip().startswith("! ") and "beta-ws" in ln and "ATTN" in ln for ln in list_mixed_plain), f"missing ! ATTN row: {list_mixed_plain}"
    assert any(ln.lstrip().startswith("! ") and "gamma-ws" in ln and "DONE" in ln for ln in list_mixed_plain), f"missing ! DONE row: {list_mixed_plain}"

    color_env = {k: v for k, v in sess_env("alpha-ws", ws_alpha["ed"]).items() if k != "NO_COLOR"}
    slines_ansi = run_cmd([ide_bin, "--sessions-lines", "alpha-ws"], env=color_env, check=True).stdout.splitlines()
    beta_ansi = next(ln for ln in slines_ansi if ln.startswith("beta-ws\t"))
    gamma_ansi = next(ln for ln in slines_ansi if ln.startswith("gamma-ws\t"))
    assert "\x1b[38;2;203;75;22m󰂚\x1b[0m" in beta_ansi and "\x1b[38;2;203;75;22mbeta-ws" in beta_ansi, f"expected Orange bell & session on ATTN row: {beta_ansi!r}"
    assert "\x1b[38;2;133;153;0m󰂚\x1b[0m" in gamma_ansi and "\x1b[38;2;133;153;0mgamma-ws" in gamma_ansi and "\x1b[38;2;133;153;0mDONE" in gamma_ansi, f"expected Green bell, session & DONE on unacknowledged DONE row: {gamma_ansi!r}"
    l_mfd, l_sfd = pty.openpty()
    try:
        l_proc = subprocess.Popen([ide_bin, "--list"], stdin=subprocess.DEVNULL, stdout=l_sfd, stderr=l_sfd, env=color_env)
        os.close(l_sfd)
        l_chunks = []
        while True:
            try:
                chunk = os.read(l_mfd, 16384)
                if not chunk:
                    break
                l_chunks.append(chunk)
            except OSError:
                break
        assert l_proc.wait(timeout=5.0) == 0
    finally:
        try:
            os.close(l_mfd)
        except OSError:
            pass
    list_mixed_ansi = b"".join(l_chunks).decode("utf-8", "replace").splitlines()
    beta_list_ansi = next(ln for ln in list_mixed_ansi if "beta-ws" in ln)
    gamma_list_ansi = next(ln for ln in list_mixed_ansi if "gamma-ws" in ln)
    assert "\x1b[38;2;203;75;22m󰂚\x1b[0m" in beta_list_ansi and "\x1b[38;2;203;75;22mbeta-ws" in beta_list_ansi, f"expected Orange bell & session in TTY --list: {beta_list_ansi!r}"
    assert "\x1b[38;2;133;153;0m󰂚\x1b[0m" in gamma_list_ansi and "\x1b[38;2;133;153;0mgamma-ws" in gamma_list_ansi, f"expected Green bell & session in TTY --list: {gamma_list_ansi!r}"

    # (8d) ide --next-attention jumps to oldest needs_attn session (beta-ws approval), focuses AI pane, auto-acknowledges, and updates @ide_attn_summary -> "gamma-ws"
    run_cmd([ide_bin, "--next-attention", "alpha-ws"], env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_CLIENT": client_name}, check=True)
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "gamma-ws"

    # Real Alt+Shift+S (\x1bS) on attached PTY jumps to next needs_attn session (gamma-ws background done), transitions done -> idle, and clears @ide_attn_summary!
    os.write(client_mfd, b"\x1bS")
    assert wait_until(lambda: (drain_pty() or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws")), "Alt+Shift+S did not jump to background-done gamma-ws"
    assert wait_until(lambda: (drain_pty() or tmux_out("show-options", "-gqv", "@ide_attn_summary") == "")), "Alt+Shift+S focus hook did not clear @ide_attn_summary"
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_state") == "idle"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")

    # Attached session with Editor focused receiving --agent-state done ALSO queues attention & jumps to AI pane!
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    drain_pty()
    run_cmd([ide_bin, "--agent-state", "done", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "gamma-ws"
    run_cmd([ide_bin, "--next-attention", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_CLIENT": client_name}, check=True)
    drain_pty()
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{@ide_role}") == "ai"
    assert tmux_out("show-options", "-qv", "-t", "=gamma-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""

    # Calling --next-attention when queue is empty is a safe exit-0 no-op
    run_cmd([ide_bin, "--next-attention", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ai"]), "IDE_CLIENT": client_name}, check=True)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws"

    # Calling --next-attention outside tmux with TTY stdin but redirected stdout (IDE_NO_ATTACH=0) exits 0 without 'open terminal failed'
    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    na_mfd, na_sfd = pty.openpty()
    try:
        na_env = {**base_env, "TMUX": "", "TMUX_PANE": "", "IDE_CLIENT": "", "IDE_NO_ATTACH": "0"}
        na_res = subprocess.run([ide_bin, "--next-attention"], stdin=na_sfd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=na_env, text=True, check=False)
        assert na_res.returncode == 0, f"outside-tmux --next-attention with redirected stdout failed: {na_res.stderr!r}"
    finally:
        os.close(na_sfd)
        os.close(na_mfd)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")

    # (8e) Parked AI pane (_ide_park_ai) preserves live WORKING state
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_parked") == "1"
    list_parked_run = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True).stdout
    assert any("beta-ws" in ln and "WORKING" in ln for ln in list_parked_run.splitlines()), f"parked running AI lost WORKING state: {list_parked_run}"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    run_cmd([ide_bin, "--toggle-ai", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=True)

    # (8f) Stale-hook guard: if AI CLI exits back to bare shell (0 child processes), report SHELL and clear stale @ide_ai_state/@ide_ai_attn!
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(
        lambda: any("beta-ws" in ln and "SHELL" in ln for ln in run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True).stdout.splitlines()),
        timeout=3.0,
    ), "bare-shell AI pane did not transition to SHELL"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == ""
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0")
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"

    # (8g) Exec-launched childless foreground AI process (0 child PIDs, non-shell pane_current_command) retains hook state!
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep")
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "exec-launched childless AI lost approval state!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws", "exec-launched childless AI wiped from @ide_attn_summary!"

    # (8h) Real SGR mouse clicks on top status bar: Help (Alt+?) popup, #[range=user|attn], and #[range=user|fleet]
    import unicodedata as _ud
    _ansi_strip_re = re.compile(r"\x1b(?:\[[0-9;?]*[A-Za-z~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[()][A-Z0-9])")

    def _cell_w(text):
        total = 0
        for ch in text:
            cp = ord(ch)
            if 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0x10FFFF:
                total += 1
            elif cp >= 0x10000 or _ud.east_asian_width(ch) in ("W", "F"):
                total += 2
            elif not _ud.combining(ch):
                total += 1
        return total

    def _read_pty_chunk(sec=0.5):
        end_t = time.monotonic() + sec
        buf = []
        while time.monotonic() < end_t:
            rdy, _, _ = select.select([client_mfd], [], [], max(0.01, end_t - time.monotonic()))
            if rdy:
                try:
                    buf.append(os.read(client_mfd, 65536))
                except OSError:
                    break
        return b"".join(buf)

    def _pump_pty(sec=0.05):
        _read_pty_chunk(sec)
        return False

    def _wait_pty_text(needle, timeout=3.0):
        end_t = time.monotonic() + timeout
        acc = bytearray()
        while time.monotonic() < end_t:
            rdy, _, _ = select.select([client_mfd], [], [], min(0.05, max(0.005, end_t - time.monotonic())))
            if rdy:
                try:
                    acc.extend(os.read(client_mfd, 65536))
                except OSError:
                    break
                txt = _ansi_strip_re.sub("", acc.decode("utf-8", "replace"))
                if needle in txt:
                    return txt
        return _ansi_strip_re.sub("", acc.decode("utf-8", "replace"))

    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("set-environment", "-t", "=alpha-ws", "SSH_CONNECTION", "10.0.0.1 12345 10.0.0.2 22", check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    c_width = int(tmux_out("display-message", "-p", "-t", client_name, "#{client_width}"))
    sr_raw = subprocess.run(
        ["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:status-right}"],
        env=base_env, text=True, capture_output=True, check=True,
    ).stdout.rstrip("\n")
    sr_vis = re.sub(r"#\[[^\]]*\]", "", sr_raw)

    def _sr_col(label):
        pos = sr_vis.index(label)
        return c_width - _cell_w(sr_vis[pos:]) + 1

    # Click 0: Non-interactive SSH host segment ("󰣀") and empty middle status bar space MUST NOT open Help OR hijack pane focus!
    ssh_x = _sr_col("󰣀")
    os.write(client_mfd, f"\x1b[<0;{ssh_x};1M\x1b[<0;{ssh_x};1m".encode())
    ssh_out = _ansi_strip_re.sub("", _read_pty_chunk(0.35).decode("utf-8", "replace"))
    assert "IDE Workspace & Editor Keybindings" not in ssh_out, f"SSH segment click unexpectedly opened Help popup: {ssh_out[-250:]!r}"
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "SSH segment click hijacked active pane role!"

    # Empty middle bar space click (both unzoomed and zoomed) must be a strict pure-C no-op!
    sl_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:status-left}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    wc_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    empty_mid_x = _cell_w(sl_vis) + _cell_w(wc_vis) + 6
    _read_pty_chunk(0.35)
    os.write(client_mfd, f"\x1b[<0;{empty_mid_x};1M\x1b[<0;{empty_mid_x};1m".encode())
    _read_pty_chunk(0.35)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor", "Empty middle status bar click switched focus to Shell!"
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.2)
    os.write(client_mfd, f"\x1b[<0;{empty_mid_x + 18};1M\x1b[<0;{empty_mid_x + 18};1m".encode())
    _read_pty_chunk(0.35)
    assert tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{window_zoomed_flag}") == "1", "Empty middle status bar click unzoomed active pane!"

    # Native #[range=user|tab_zoom] (including rapid <80ms DoubleClick1Status), #[range=user|tab_term], #[range=user|tab_ai], and #[range=user|tab_editor] clicks:
    wc_zoom_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    zoom_tab_x = _cell_w(sl_vis) + _cell_w(wc_zoom_vis[:wc_zoom_vis.index("ZOOM")]) + 1
    os.write(client_mfd, f"\x1b[<0;{zoom_tab_x};1M\x1b[<0;{zoom_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.03) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{window_zoomed_flag}") == "0")), "tab_zoom SGR click did not unzoom"
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    assert "ZOOM" in _wait_pty_text("ZOOM", timeout=2.0), "status bar did not redraw ZOOM badge after re-zoom"
    os.write(client_mfd, f"\x1b[<0;{zoom_tab_x};1M\x1b[<0;{zoom_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.03) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{window_zoomed_flag}") == "0")), "rapid DoubleClick1Status on tab_zoom was dropped!"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    term_tab_x = _cell_w(sl_vis) + _cell_w(wc_vis[:wc_vis.index("Shell")]) + 1
    os.write(client_mfd, f"\x1b[<0;{term_tab_x};1M\x1b[<0;{term_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term")), "tab_term SGR click did not focus Shell"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    wc_term_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    ai_tab_x = _cell_w(sl_vis) + 3
    os.write(client_mfd, f"\x1b[<0;{ai_tab_x};1M\x1b[<0;{ai_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "ai")), "tab_ai SGR click did not focus AI"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)

    wc_ai_vis = re.sub(r"#\[[^\]]*\]", "", subprocess.run(["tmux", "-u", "display-message", "-t", "=alpha-ws:", "-p", "#{T:window-status-current-format}"], env=base_env, text=True, capture_output=True, check=True).stdout.rstrip("\n"))
    ed_tab_x = _cell_w(sl_vis) + _cell_w(wc_ai_vis[:wc_ai_vis.index("Editor")]) + 1
    os.write(client_mfd, f"\x1b[<0;{ed_tab_x};1M\x1b[<0;{ed_tab_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor")), "tab_editor SGR click did not focus Editor"
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _read_pty_chunk(0.35)
    _ = wc_term_vis

    # Click 1: Help (Alt+?) (#[range=user|help]) while SSH, attn, and fleet segments are rendered to its left
    help_x = _sr_col("Help")
    os.write(client_mfd, f"\x1b[<0;{help_x};1M\x1b[<0;{help_x};1m".encode())
    help_out = _wait_pty_text("IDE Workspace & Editor Keybindings", timeout=4.0)
    assert "IDE Workspace & Editor Keybindings" in help_out, f"Help SGR click failed: {help_out[-250:]!r}"
    os.write(client_mfd, b"q")
    _read_pty_chunk(0.4)
    tmux("set-environment", "-u", "-t", "=alpha-ws", "SSH_CONNECTION", check=True)

    # Click 2: Urgent #[range=user|attn] pill ("beta-ws") jumps client to beta-ws and auto-acks
    attn_x = _sr_col("beta-ws")
    os.write(client_mfd, f"\x1b[<0;{attn_x};1M\x1b[<0;{attn_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.08) or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws")), "attn pill SGR click did not jump to beta-ws"
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("show-options", "-gqv", "@ide_attn_summary") == "")), "attn pill SGR click did not clear @ide_attn_summary"

    # Click 3: #[range=user|fleet] pill ("(Alt+s)") opens --sessions popup and switches back to alpha-ws
    tmux("set-environment", "-g", "MOCK_FZF_KEY", "", check=True)
    tmux("set-environment", "-g", "MOCK_FZF_TARGET", "alpha-ws", check=True)
    tmux("refresh-client", "-t", client_name, "-S", check=True)
    _wait_pty_text("(Alt+s)", timeout=2.0)
    _read_pty_chunk(0.15)
    sr_raw2 = subprocess.run(
        ["tmux", "-u", "display-message", "-t", "=beta-ws:", "-p", "#{T:status-right}"],
        env=base_env, text=True, capture_output=True, check=True,
    ).stdout.rstrip("\n")
    sr_vis2 = re.sub(r"#\[[^\]]*\]", "", sr_raw2)
    fleet_x = c_width - _cell_w(sr_vis2[sr_vis2.index("(Alt+s)"):]) + 1
    os.write(client_mfd, f"\x1b[<0;{fleet_x};1M\x1b[<0;{fleet_x};1m".encode())
    assert wait_until(lambda: (_pump_pty(0.1) or tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws"), timeout=4.0), "fleet pill SGR click did not switch to alpha-ws"
    _read_pty_chunk(0.2)

    # (8i) Zero-fork pure-C if-shell -F guard on pane-focus-in & client-session-changed:
    # Switching between Editor and Shell (or into idle/empty AI panes or non-IDE sessions) must NEVER
    # invoke ~/.local/bin/ide --ack-ai, whereas focusing AI when @ide_ai_attn == 1 (approval or
    # background done) immediately invokes --ack-ai --hook and clears @ide_ai_attn and @ide_attn_summary.
    for s_clean in ("alpha-ws", "beta-ws", "gamma-ws"):
        run_cmd([ide_bin, "--agent-state", "idle", s_clean], env=sess_env(s_clean), check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.25)

    real_ide_path = os.path.realpath(ide_bin)
    ack_hook_log = os.path.join(root, "ack_hook.log")
    open(ack_hook_log, "w", encoding="utf-8").close()
    os.unlink(ide_bin)
    with open(ide_bin, "w", encoding="utf-8") as wf:
        wf.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"log_p = {ack_hook_log!r}\n"
            f"real_p = {real_ide_path!r}\n"
            "if '--ack-ai' in sys.argv[1:]:\n"
            "    with open(log_p, 'a', encoding='utf-8') as lf:\n"
            "        lf.write(' '.join(sys.argv[1:]) + '\\n')\n"
            "os.execv(real_p, [real_p, *sys.argv[1:]])\n"
        )
    os.chmod(ide_bin, 0o755)

    # Routine focus switches while @ide_ai_state is idle or empty:
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    os.write(client_mfd, b"\x1bt")
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "term")), "Alt+t did not focus Shell"
    os.write(client_mfd, b"\x1bk")
    assert wait_until(lambda: (_pump_pty(0.05) or tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{@ide_role}") == "editor")), "Alt+k from Shell did not focus Editor"
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("set-option", "-q", "-u", "-t", "=alpha-ws:", "@ide_ai_state", check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("switch-client", "-c", client_name, "-t", "=plain-non-ide", check=True)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)

    # Even while @ide_ai_attn == 1 (background done), switching between Editor and Shell must NOT invoke --ack-ai!
    run_cmd([ide_bin, "--agent-state", "done", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws"
    tmux("select-pane", "-t", ws_alpha["tm"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.3)
    logged_false = open(ack_hook_log, encoding="utf-8").read()
    assert logged_false == "", f"if-shell -F guard leaked --ack-ai calls during non-AI/idle switches: {logged_false!r}"

    # Focusing AI pane while @ide_ai_attn == 1 (background done) immediately triggers --ack-ai --hook and clears!
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "--ack-ai --hook alpha-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on background-done AI did not invoke --ack-ai --hook"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "pane-focus-in did not clear @ide_ai_attn/@ide_attn_summary on done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "idle"

    # Focusing AI pane while @ide_ai_attn == 1 (approval) immediately triggers --ack-ai --hook, clears @ide_ai_attn/@ide_attn_summary, AND preserves @ide_ai_state == "approval"!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws"
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "--ack-ai --hook alpha-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on approval AI did not invoke --ack-ai --hook"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "pane-focus-in did not clear @ide_ai_attn/@ide_attn_summary on approval"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval", "focusing AI wiped unanswered approval state to idle!"
    # Switching back to Editor to inspect code keeps approval state (Orange AI tab & ATTN in --list) without re-triggering @ide_attn_summary!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""
    wcur_ack_app = tmux_out("display-message", "-p", "-t", ws_alpha["ed"], "#{E:window-status-current-format}")
    assert "fg=#CB4B16,bg=#073642,nobold]󰚩 claude (Alt+a)" in wcur_ack_app, f"expected Orange approval tab tint while inspecting Editor: {wcur_ack_app!r}"

    # Firing --agent-state approval while ALREADY focused in AI pane sets @ide_ai_state=approval with @ide_ai_attn=0 (no false urgent alert!)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "foreground approval while focused in AI falsely raised @ide_ai_attn=1!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", "foreground approval while focused in AI falsely lit @ide_attn_summary!"
    run_cmd([ide_bin, "--agent-state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)

    # Routine focus switches into live running or quota AI panes:
    # (a) Foreground non-shell AI binary (ws_beta["ai"] running 'sleep'): 0 --ack-ai --hook forks!
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    open(ack_hook_log, "w", encoding="utf-8").close()
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "quota", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.25)
    assert open(ack_hook_log, encoding="utf-8").read() == "", f"routine running/quota focus spawned hook storm: {open(ack_hook_log, encoding='utf-8').read()!r}"
    run_cmd([ide_bin, "--agent-state", "idle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    # (b) Shell-wrapped AI process (ws_alpha["ai"]: /bin/sh with live child sleep): preserves running/quota without wiping state!
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    _read_pty_chunk(0.2)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "running", "shell-wrapped live running AI lost state on focus!"
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "idle", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)

    # Switching client to a session whose AI pane is active with @ide_ai_attn == 1 triggers client-session-changed --ack-ai --hook and preserves approval!
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "approval", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "--ack-ai --hook beta-ws" in open(ack_hook_log, encoding="utf-8").read())), "client-session-changed did not invoke --ack-ai --hook beta-ws"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") in ("", "0") and tmux_out("show-options", "-gqv", "@ide_attn_summary") == ""))), "client-session-changed did not clear @ide_ai_attn/@ide_attn_summary"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "approval"

    # Crashed 'running' AI CLI (exited to bare /bin/sh without Stop hook):
    # 1) Focusing AI from Editor triggers pane-focus-in crashed-shell guard (--ack-ai --hook) and clears @ide_ai_state & @ide_fleet_active!
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.15)
    open(ack_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sh")
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    assert wait_until(lambda: (_pump_pty(0.05) or "--ack-ai --hook beta-ws" in open(ack_hook_log, encoding="utf-8").read())), "pane-focus-in on crashed running AI did not invoke --ack-ai --hook"
    assert wait_until(lambda: (_pump_pty(0.05) or (tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "" and tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0"))), "pane-focus-in did not clear stale running state after AI exit"

    # 2) If AI crashes while running AND user is already in AI pane, bouncing out via Alt+a (--toggle) clears stale running & @ide_fleet_active!
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep")
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "1"
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sh")
    run_cmd([ide_bin, "--toggle", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "editor"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "", "bouncing out of crashed running AI via --toggle left stale @ide_ai_state!"
    assert tmux_out("show-options", "-gqv", "@ide_fleet_active") == "0", "bouncing out of crashed running AI via --toggle left stale @ide_fleet_active!"

    # (8j) ide --refresh heals stale Editor CWDs + reloads Neovim theme over RPC, refreshes top bar, and NEVER injects keys or wipes unsent text in idle Shell panes!
    r_ref_bad = run_cmd([ide_bin, "--refresh", "no-such-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=False)
    assert r_ref_bad.returncode != 0, "expected non-zero when --refresh targets nonexistent session"
    tmux("respawn-pane", "-k", "-t", ws_alpha["tm"], "-c", ws_alpha["dir"], "env PS1='PROMPT> ' bash --norc --noprofile -i", check=True)
    assert wait_until(lambda: "PROMPT>" in tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"]))
    tmux("send-keys", "-t", ws_alpha["tm"], "-l", "git commit -m 'unsent draft", check=True)
    assert wait_until(lambda: "git commit -m 'unsent draft" in tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"]))
    alpha_sock = tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_socket")
    if shutil.which("nvim"):
        stale_ed_sub = os.path.join(ws_alpha["dir"], "stale_ed")
        os.makedirs(stale_ed_sub, exist_ok=True)
        tmux(
            "respawn-pane", "-k", "-t", ws_alpha["ed"], "-c", stale_ed_sub,
            f"exec nvim --headless -u NONE -i NONE --listen {shlex.quote(alpha_sock)} -c \"lua _G.apply_home_settings_theme = function() vim.g.hs_theme_reloaded = (vim.g.hs_theme_reloaded or 0) + 1 end\"",
            check=True,
        )
        assert wait_until(lambda: nvim_expr_eq(alpha_sock, "exists('*v:lua.apply_home_settings_theme')", "1")), "alpha-ws nvim callback did not initialize for --refresh test"
        shutil.rmtree(stale_ed_sub)
    r_ref_all = run_cmd([ide_bin, "--refresh"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert "Refreshed 3 IDE session(s)" in r_ref_all.stdout and "shell" not in r_ref_all.stdout, f"unexpected --refresh output: {r_ref_all.stdout!r}"
    time.sleep(0.15)
    tm_cap_after = tmux_out("capture-pane", "-p", "-t", ws_alpha["tm"])
    assert "git commit -m 'unsent draft" in tm_cap_after and "_hs_recover_stale_cwd" not in tm_cap_after, (
        f"ide --refresh corrupted or wiped unsent text in idle Shell pane: {tm_cap_after!r}"
    )
    if shutil.which("nvim"):
        ed_cwd_after = subprocess.run(
            ["nvim", "--server", alpha_sock, "--remote-expr", "luaeval('(vim.uv or vim.loop).cwd() or \"\"')"],
            env=base_env, text=True, capture_output=True, timeout=3, check=True,
        ).stdout.strip()
        ed_wrapped = subprocess.run(
            ["nvim", "--server", alpha_sock, "--remote-expr", "luaeval('tostring(vim.fs and vim.fs._hs_abspath_wrapped == true)')"],
            env=base_env, text=True, capture_output=True, timeout=3, check=True,
        ).stdout.strip()
        ed_theme_cnt = subprocess.run(
            ["nvim", "--server", alpha_sock, "--remote-expr", "luaeval('tostring(vim.g.hs_theme_reloaded or 0)')"],
            env=base_env, text=True, capture_output=True, timeout=3, check=True,
        ).stdout.strip()
        assert os.path.realpath(ed_cwd_after) in (os.path.realpath(ws_alpha["dir"]), os.path.realpath(sub_dir)), f"ide --refresh did not heal nvim CWD: {ed_cwd_after!r}"
        assert ed_wrapped == "true", f"ide --refresh did not install vim.fs.abspath wrapper: {ed_wrapped!r}"
        assert ed_theme_cnt == "1", f"ide --refresh did not invoke v:lua.apply_home_settings_theme(): {ed_theme_cnt!r}"

    # 9. Five-Tier Urgency Hierarchy, Elapsed State Age, OS Focus & Notifications, Multi-Ack, PR Badges, Worktree Collision Guard, Cross-Session --send --switch, and Alt+n Launcher
    # Restore direct ide symlink (removing the step 8i ack wrapper)
    if os.path.exists(ide_bin) or os.path.islink(ide_bin):
        os.unlink(ide_bin)
    os.symlink(real_ide_path, ide_bin)

    ws_delta = make_ws("delta-ws", ai_cmd="sleep 300", ai_cli="claude", git_branch="feat/cache", in_home=True)
    ws_shell = make_ws("shell-ws", ai_cmd="exec /bin/sh", ai_cli="agy", git_branch="", in_home=False)
    for s_restore, ws_obj in (("alpha-ws", ws_alpha), ("beta-ws", ws_beta), ("gamma-ws", ws_gamma)):
        tmux("respawn-pane", "-k", "-t", ws_obj["ai"], "-c", ws_obj["dir"], "exec sleep 300", check=True)
        tmux("set-option", "-q", "-t", f"={s_restore}:", "@ide_workdir", ws_obj["dir"], check=True)
    assert wait_until(
        lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_gamma["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_shell["ai"], "#{pane_current_command}") == "sh"
    )
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    tmux("select-pane", "-t", ws_delta["ed"], check=True)
    _read_pty_chunk(0.15)

    # (9a) Five-tier urgency sort: older DONE (beta-ws) MUST NOT beat newer ATTN (alpha-ws); WORKING > IDLE > SHELL; elapsed ages & repeated running preservation
    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    time.sleep(0.03)
    run_cmd([ide_bin, "--agent-state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    run_cmd([ide_bin, "--agent-state", "running", "delta-ws"], env=sess_env("delta-ws", ws_delta["ai"]), check=True)
    run_cmd([ide_bin, "--agent-state", "idle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)

    now_epoch = int(time.time())
    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_ai_state_ts", str(now_epoch - 1560), check=True)  # 26m
    tmux("set-option", "-q", "-t", "=beta-ws:", "@ide_ai_state_ts", str(now_epoch - 180), check=True)    # 3m
    tmux("set-option", "-q", "-t", "=delta-ws:", "@ide_ai_state_ts", str(now_epoch - 480), check=True)   # 8m
    tmux("set-option", "-q", "-t", "=gamma-ws:", "@ide_ai_state_ts", str(now_epoch - 120), check=True)   # 2m

    # Repeated --agent-state running on delta-ws MUST preserve existing @ide_ai_state_ts (8m), not reset to 0s!
    run_cmd([ide_bin, "--agent-state", "running", "delta-ws"], env=sess_env("delta-ws", ws_delta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=delta-ws:", "@ide_ai_state_ts") == str(now_epoch - 480), "repeated running hook reset @ide_ai_state_ts!"

    tier_order = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert tier_order == ["alpha-ws", "beta-ws", "delta-ws", "gamma-ws", "shell-ws"], f"5-tier sort order broken: {tier_order}"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws +1", f"attn_summary failed to prioritize ATTN over older DONE: {tmux_out('show-options', '-gqv', '@ide_attn_summary')!r}"

    tier_table = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert any("alpha-ws" in ln and "ATTN 26m" in ln for ln in tier_table), f"missing ATTN 26m in --list: {tier_table}"
    assert any("beta-ws" in ln and "DONE 3m" in ln for ln in tier_table), f"missing DONE 3m in --list: {tier_table}"
    assert any("delta-ws" in ln and "WORKING 8m" in ln for ln in tier_table), f"missing WORKING 8m in --list: {tier_table}"
    assert any("gamma-ws" in ln and "IDLE 2m" in ln for ln in tier_table), f"missing IDLE 2m in --list: {tier_table}"
    assert any("shell-ws" in ln and "SHELL" in ln and "SHELL " not in ln.split("SHELL", 1)[1][:2] for ln in tier_table), f"unexpected SHELL row: {tier_table}"
    # Verify dynamic column alignment: WORKSPACE column starts at identical character index across every row!
    ws_col_idx = tier_table[0].index("WORKSPACE")
    for row_ln in tier_table[1:]:
        assert row_ln[ws_col_idx:ws_col_idx + 1] in ("~", "/"), f"misaligned WORKSPACE column at {ws_col_idx} in row: {row_ln!r}"

    prev_alpha_age = run_cmd([ide_bin, "--session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "ATTN 26m" in prev_alpha_age, f"missing ATTN 26m in --session-preview: {prev_alpha_age}"

    # --next-attention jumps to newer ATTN (alpha-ws) BEFORE older DONE (beta-ws)!
    run_cmd([ide_bin, "--next-attention", "gamma-ws"], env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_CLIENT": client_name}, check=True)
    _read_pty_chunk(0.15)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "alpha-ws", "next-attention failed to prioritize ATTN blocker ahead of older DONE!"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "beta-ws"

    # (9b) Multi-session --ack-ai: remotely acking approval mutes @ide_ai_attn while keeping ATTN state; remotely acking done transitions to IDLE
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "--agent-state", "approval", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "alpha-ws +1"
    run_cmd([ide_bin, "--ack-ai", "alpha-ws", "beta-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", "multi-target --ack-ai did not clear @ide_attn_summary"
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_state") == "idle", "remote --ack-ai on done did not transition to idle"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "remote --ack-ai on approval did not clear @ide_ai_attn"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "approval", "remote --ack-ai wiped unanswered approval state!"
    muted_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert any("alpha-ws" in ln and "ATTN" in ln and not ln.lstrip().startswith("!") for ln in muted_list), f"muted approval should remain ATTN without '!' marker: {muted_list}"

    # (9c) OS window unfocus (DECSET 1004 \x1b[O / \x1b[I), trailing JSON & piped stdin hardening, idle_prompt ignore, ide_notify & IDE_NOTIFY banners
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_alpha["ai"], check=True)
    assert wait_until(lambda: (drain_pty() or "focused" in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_flags}")))
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)

    # Set up custom ide_notify hook + mock notify-send (with broken DBUS_SESSION_BUS_ADDRESS so busctl falls back cleanly to notify-send!)
    notify_hook_log = os.path.join(root, "ide_notify_hook.log")
    os_notify_log = os.path.join(root, "os_notify.log")
    rules_file = os.path.join(xdg_cfg, "ide", "links.sh")
    os.makedirs(os.path.dirname(rules_file), exist_ok=True)
    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            f'ide_notify() {{ printf "%s|%s|%s|%s|%s|%s\\n" "$1" "$2" "$3" "$4" "$5" "$6" >> {shlex.quote(notify_hook_log)}; }}\n'
        )
    mock_nsend = os.path.join(bin_dir, "notify-send")
    with open(mock_nsend, "w", encoding="utf-8") as nf:
        nf.write(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            f"with open({os_notify_log!r}, 'a', encoding='utf-8') as f:\n"
            "    f.write('|'.join(sys.argv[1:]) + '\\n')\n"
        )
    os.chmod(mock_nsend, 0o755)
    notif_base_env = {
        **sess_env("alpha-ws", ws_alpha["ai"]),
        "DBUS_SESSION_BUS_ADDRESS": f"unix:path={os.path.join(root, 'no-such-bus')}",
        "DISPLAY": ":99",
    }

    # Send DECSET 1004 FocusOut (\x1b[O) while cursor stays in alpha-ws AI pane!
    os.write(client_mfd, b"\x1b[O")
    assert wait_until(lambda: (drain_pty() or "focused" not in tmux_out("list-clients", "-t", "=alpha-ws", "-F", "#{client_flags}"))), "tmux did not clear focused client flag on \\x1b[O"

    # Codex-style trailing JSON argument while OS window is unfocused -> sets @ide_ai_attn=1, updates [!] title, fires ide_notify + notify-send with HTML-escaped body!
    codex_json = '{"type":"agent-turn-complete","last-assistant-message":"Checks <green> & fast"}'
    run_cmd([ide_bin, "--agent-state", "done", codex_json], env={**notif_base_env, "IDE_NOTIFY": "1"}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "1", "unfocused OS window missed done completion while cursor stayed in AI pane!"
    title_unfocused = tmux_out("display-message", "-p", "-t", "=alpha-ws:", "#{E:set-titles-string}")
    assert title_unfocused.startswith("[!] alpha-ws"), f"expected [!] title prefix on unfocused done: {title_unfocused!r}"
    assert wait_until(lambda: os.path.isfile(notify_hook_log) and "done|alpha-ws|claude|" in open(notify_hook_log, encoding="utf-8").read()), "ide_notify hook did not fire on unfocused done"
    assert wait_until(lambda: os.path.isfile(os_notify_log) and "Checks &lt;green&gt; &amp; fast" in open(os_notify_log, encoding="utf-8").read()), "notify-send fallback did not receive HTML-escaped body"
    assert "string:x-canonical-private-synchronous:ide-alpha-ws" in open(os_notify_log, encoding="utf-8").read()

    # Claude-style idle_prompt on non-TTY stdin MUST be ignored and MUST NOT overwrite DONE with ATTN,
    # including >256 KiB multi-chunk slow-writer payloads and >1 MiB payloads without EPIPE!
    def _pipe_chunked_hook(chunks, delay_s=0.0):
        p = subprocess.Popen(
            [ide_bin, "--agent-state", "approval", "alpha-ws"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**notif_base_env, "IDE_NOTIFY": "1"},
        )
        assert p.stdin is not None
        for idx_c, ch_bytes in enumerate(chunks):
            if idx_c > 0 and delay_s > 0:
                time.sleep(delay_s)
            p.stdin.write(ch_bytes)
            p.stdin.flush()
        p.stdin.close()
        rc_p = p.wait(timeout=5.0)
        assert rc_p == 0, f"chunked --agent-state failed rc={rc_p}: {p.stderr.read() if p.stderr else b''!r}"

    chunk_a = ('{"pad":"' + ("x" * 110000)).encode("utf-8")
    chunk_b = (("y" * 290000) + '","notification_type":"idle_prompt","message":"Slow writer 400KB"}').encode("utf-8")
    _pipe_chunked_hook([chunk_a, chunk_b], delay_s=0.015)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done", "400KB slow-writer idle_prompt overwrote DONE with approval!"

    oversized_idle = ('{"notification_type":"idle_prompt","pad":"' + ("z" * 1300000) + '"}').encode("utf-8")
    _pipe_chunked_hook([oversized_idle[:600000], oversized_idle[600000:]], delay_s=0.005)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "done", "1.3MB oversized idle_prompt overwrote DONE with approval!"

    # Send DECSET 1004 FocusIn (\x1b[I) -> tmux pane-focus-in auto-acknowledges alpha-ws!
    os.write(client_mfd, b"\x1b[I")
    assert wait_until(lambda: (drain_pty() or (tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0" and tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "idle"))), "FocusIn \\x1b[I did not auto-acknowledge AI pane!"

    # When OS window IS focused and AI pane IS visible alongside focused Editor:
    # IDE_NOTIFY=1 suppresses OS desktop banner, IDE_NOTIFY=always sends it, zoomed Editor under IDE_NOTIFY=1 sends it, duplicate approval does not re-fire, and SSH suppresses OS banner!
    tmux("select-pane", "-t", ws_alpha["ed"], check=True)
    drain_pty()
    open(os_notify_log, "w", encoding="utf-8").close()
    open(notify_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "done", "--message", "Visible pane done", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "1"}, check=True)
    assert wait_until(lambda: os.path.isfile(notify_hook_log) and "Visible pane done" in open(notify_hook_log, encoding="utf-8").read()), "ide_notify hook should still fire on attention edge"
    time.sleep(0.1)
    assert open(os_notify_log, encoding="utf-8").read() == "", f"IDE_NOTIFY=1 spammed OS banner when AI pane was already visible in focused window: {open(os_notify_log, encoding='utf-8').read()!r}"

    # Duplicate done edge must NOT re-trigger ide_notify!
    open(notify_hook_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "done", "--message", "Duplicate", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "always"}, check=True)
    time.sleep(0.15)
    assert open(notify_hook_log, encoding="utf-8").read() == "", "duplicate state transition re-fired notification!"

    # Transition done -> approval with IDE_NOTIFY=always fires even while AI pane is visible!
    run_cmd([ide_bin, "--agent-state", "approval", "--message", "Always banner", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "always"}, check=True)
    assert wait_until(lambda: "Always banner" in open(os_notify_log, encoding="utf-8").read()), "IDE_NOTIFY=always did not fire on visible attention edge"

    # Zooming Editor hides AI pane -> IDE_NOTIFY=1 fires!
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=notif_base_env, check=True)
    open(os_notify_log, "w", encoding="utf-8").close()
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "--message", "Zoomed editor blocker", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "1"}, check=True)
    assert wait_until(lambda: "Zoomed editor blocker" in open(os_notify_log, encoding="utf-8").read()), "IDE_NOTIFY=1 missed blocker while Editor was zoomed full-screen!"
    tmux("resize-pane", "-Z", "-t", ws_alpha["ed"], check=True)

    # SSH session NEVER fires local OS notification banner even under IDE_NOTIFY=always!
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=notif_base_env, check=True)
    open(os_notify_log, "w", encoding="utf-8").close()
    run_cmd(
        [ide_bin, "--agent-state", "approval", "--message", "SSH blocker", "alpha-ws"],
        env={**notif_base_env, "IDE_NOTIFY": "always", "SSH_CONNECTION": "10.0.0.1 1234 10.0.0.2 22"},
        check=True,
    )
    time.sleep(0.15)
    assert open(os_notify_log, encoding="utf-8").read() == "", "SSH session leaked local desktop notification!"

    # Session-level `-IDE_NOTIFY` removal or empty `IDE_NOTIFY=""` override MUST NOT fall through to global `IDE_NOTIFY=always`!
    tmux("set-environment", "-g", "IDE_NOTIFY", "always", check=True)
    tmux("set-environment", "-t", "=alpha-ws", "-r", "IDE_NOTIFY", check=True)
    env_no_notify_var = {k: v for k, v in notif_base_env.items() if k != "IDE_NOTIFY"}
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=env_no_notify_var, check=True)
    open(os_notify_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--agent-state", "approval", "--message", "Session muted -r", "alpha-ws"], env=env_no_notify_var, check=True)
    time.sleep(0.15)
    assert open(os_notify_log, encoding="utf-8").read() == "", "session -r IDE_NOTIFY fell through to global IDE_NOTIFY=always!"
    tmux("set-environment", "-t", "=alpha-ws", "IDE_NOTIFY", "", check=True)
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=env_no_notify_var, check=True)
    run_cmd([ide_bin, "--agent-state", "approval", "--message", "Session muted empty", "alpha-ws"], env=env_no_notify_var, check=True)
    time.sleep(0.15)
    assert open(os_notify_log, encoding="utf-8").read() == "", "session empty IDE_NOTIFY= fell through to global IDE_NOTIFY=always!"
    tmux("set-environment", "-gu", "IDE_NOTIFY", check=True)
    tmux("set-environment", "-t", "=alpha-ws", "-u", "IDE_NOTIFY", check=True)

    run_cmd([ide_bin, "--agent-state", "idle", "alpha-ws"], env=notif_base_env, check=True)
    run_cmd([ide_bin, "--agent-state", "idle", "delta-ws"], env=sess_env("delta-ws", ws_delta["ai"]), check=True)

    # (9d) Zero-fork PR/MR badges (<branch>@<N>), ide --open-pr (local browser & SSH OSC 52), ide_vcs_summary timeout, and WORKING worktree collision guard
    run_cmd(["git", "-C", ws_alpha["dir"], "remote", "add", "origin", "git@github.com:acme/alpha-ws.git"], check=True)
    run_cmd(["git", "-C", ws_alpha["dir"], "config", "branch.feat/switcher.pr", "42"], check=True)

    pr_cache_dir = os.path.join(xdg_cache, "git-pr-prompt")
    os.makedirs(pr_cache_dir, exist_ok=True)
    delta_common = os.path.realpath(os.path.join(ws_delta["dir"], ".git"))
    delta_key = re.sub(r"[^A-Za-z0-9._-]", "_", delta_common)
    with open(os.path.join(pr_cache_dir, f"{delta_key}.state"), "w", encoding="utf-8") as cf:
        cf.write(f"feat/cache|108|https://gitlab.example.com/team/delta/-/merge_requests/108|{now_epoch}\n")

    beta_common = os.path.realpath(os.path.join(ws_beta["dir"], ".git"))
    beta_key = re.sub(r"[^A-Za-z0-9._-]", "_", beta_common)
    run_cmd(["git", "-C", ws_beta["dir"], "checkout", "-q", "-b", "feat/no-pr"], check=True)
    with open(os.path.join(pr_cache_dir, f"{beta_key}.state"), "w", encoding="utf-8") as cf:
        cf.write(f"feat/no-pr|NONE||{now_epoch}\n")

    pr_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "feat/switcher@42*" in pr_list, f"Tier 0 branch.pr @42 badge missing from --list: {pr_list}"
    assert "feat/cache@108" in pr_list, f"Tier 0.5 cached @108 badge missing from --list: {pr_list}"
    assert "feat/no-pr@" not in pr_list and "feat/no-pr" in pr_list, f"NONE cache entry leaked @ badge: {pr_list}"

    browser_log = os.path.join(root, "browser_pr.log")
    mock_browser = os.path.join(root, "mock-browser.sh")
    with open(mock_browser, "w", encoding="utf-8") as bf:
        bf.write(f'#!/bin/sh\nprintf "%s\\n" "$1" >> {shlex.quote(browser_log)}\n')
    os.chmod(mock_browser, 0o755)
    run_cmd([ide_bin, "--open-pr", "alpha-ws"], env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_BROWSER": mock_browser}, check=True)
    assert wait_until(lambda: os.path.isfile(browser_log) and "https://github.com/acme/alpha-ws/pull/42" in open(browser_log, encoding="utf-8").read()), "ide --open-pr failed to open Tier 0 GitHub PR URL"

    # Over SSH (without IDE_BROWSER), --open-pr copies URL into tmux buffer (OSC 52) without launching local browser
    run_cmd(
        [ide_bin, "--open-pr", "delta-ws"],
        env={**sess_env("delta-ws", ws_delta["ed"]), "SSH_CONNECTION": "10.0.0.1 1 10.0.0.2 22"},
        check=True,
    )
    assert tmux_out("show-buffer") == "https://gitlab.example.com/team/delta/-/merge_requests/108", f"SSH --open-pr did not load URL into tmux buffer: {tmux_out('show-buffer')!r}"
    assert run_cmd([ide_bin, "--open-pr", "beta-ws"], env=sess_env("beta-ws", ws_beta["ed"]), check=False).returncode != 0, "--open-pr should exit non-zero when session has no PR URL"

    # Hanging ide_vcs_summary hook in links.sh must time out in ~0.4s without blocking ide --list,
    # AND ide --session-preview on gamma-ws must stay O(1) without invoking slow peer hooks!
    vcs_inv_log = os.path.join(root, "vcs_invocations.log")
    with open(rules_file, "a", encoding="utf-8") as rf:
        rf.write(
            f'ide_vcs_summary() {{ printf "%s\\n" "$1" >> {shlex.quote(vcs_inv_log)}; if [ "$1" = {shlex.quote(ws_gamma["dir"])} ]; then echo "rev/999|1|rev/999 (pending)|https://cr.example.com/999"; else sleep 2; fi; }}\n'
        )
    vcs_prev_gamma = run_cmd([ide_bin, "--session-preview", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    prev_vcs_calls = [ln.strip() for ln in open(vcs_inv_log, encoding="utf-8").read().splitlines() if ln.strip()] if os.path.isfile(vcs_inv_log) else []
    assert "rev/999 (pending)" in vcs_prev_gamma and prev_vcs_calls == [ws_gamma["dir"]], (
        f"--session-preview failed O(1) ide_vcs_summary scoping (calls={prev_vcs_calls!r}): {vcs_prev_gamma}"
    )
    open(vcs_inv_log, "w", encoding="utf-8").close()
    t0 = time.monotonic()
    vcs_hook_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    elapsed_vcs = time.monotonic() - t0
    list_vcs_calls = [ln.strip() for ln in open(vcs_inv_log, encoding="utf-8").read().splitlines() if ln.strip()] if os.path.isfile(vcs_inv_log) else []
    assert "rev/999*" in vcs_hook_list and len(list_vcs_calls) == 5 and elapsed_vcs < 5.0, (
        f"ide_vcs_summary hook failed or hung ({elapsed_vcs:.2f}s, calls={list_vcs_calls!r}): {vcs_hook_list}"
    )
    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            f'ide_notify() {{ printf "%s|%s|%s|%s|%s|%s\\n" "$1" "$2" "$3" "$4" "$5" "$6" >> {shlex.quote(notify_hook_log)}; }}\n'
        )

    # Git config edge cases: bracketed/escaped branch subsections, includeIf gitdir/onbranch + insteadOf, and non-http(s) prurl rejection!
    inc_cfg = os.path.join(root, "git-corp.inc")
    with open(inc_cfg, "w", encoding="utf-8") as icf:
        icf.write('[url "https://gitlab.corp.example/"]\n\tinsteadOf = corp:[git]:\n[remote "origin"]\n\tforge = gitlab\n')
    global_git_cfg = os.path.join(root, "global.gitconfig")
    with open(global_git_cfg, "w", encoding="utf-8") as ggf:
        ggf.write(f'[includeIf "gitdir:{ws_gamma["dir"].rstrip("/")}/"]\n\tpath = "{inc_cfg}"\n')
    run_cmd(["git", "-C", ws_gamma["dir"], "init", "-q", "-b", 'feat/wip]"1'], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "remote", "add", "origin", "corp:[git]:platform/gamma.git"], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "config", 'branch.feat/wip]"1.pr', "77"], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "config", 'branch.feat/wip]"1.prurl', "-aCalculator"], check=True)
    open(browser_log, "w", encoding="utf-8").close()
    gamma_env_git = {**sess_env("gamma-ws", ws_gamma["ed"]), "GIT_CONFIG_GLOBAL": global_git_cfg, "IDE_BROWSER": mock_browser}
    gamma_pr_list = run_cmd([ide_bin, "--list"], env=gamma_env_git, check=True).stdout
    assert 'feat/wip]"1@77' in gamma_pr_list, f'bracketed/escaped [branch "feat/wip]\\"1"] subsection failed to parse @77 badge: {gamma_pr_list}'
    run_cmd([ide_bin, "--open-pr", "gamma-ws"], env=gamma_env_git, check=True)
    assert wait_until(
        lambda: os.path.isfile(browser_log)
        and open(browser_log, encoding="utf-8").read().strip() == "https://gitlab.corp.example/platform/gamma/-/merge_requests/77"
    ), f"unsafe prurl was not rejected or includeIf/insteadOf failed: {open(browser_log, encoding='utf-8').read()!r}"
    # If remote is absent and prurl is file:///etc/passwd, --open-pr must reject it with non-zero exit and zero browser launches
    run_cmd(["git", "-C", ws_gamma["dir"], "remote", "remove", "origin"], check=True)
    run_cmd(["git", "-C", ws_gamma["dir"], "config", 'branch.feat/wip]"1.prurl', "file:///etc/passwd"], check=True)
    open(browser_log, "w", encoding="utf-8").close()
    assert run_cmd([ide_bin, "--open-pr", "gamma-ws"], env=gamma_env_git, check=False).returncode != 0, "file:// prurl was not rejected by --open-pr!"
    assert open(browser_log, encoding="utf-8").read() == "", "file:// prurl launched browser!"
    shutil.rmtree(os.path.join(ws_gamma["dir"], ".git"))

    # Shared worktree collision guard: subdirectory shares worktree root, separate `git worktree add` does NOT!
    wt2_dir = os.path.join(root, "alpha-wt2")
    run_cmd(["git", "-C", ws_alpha["dir"], "worktree", "add", "-q", "-b", "feat/wt2", wt2_dir], check=True)
    ws_alpha_sub = make_ws("alpha-sub-ws", ai_cmd="sleep 300")
    tmux("set-option", "-q", "-t", "=alpha-sub-ws:", "@ide_workdir", os.path.join(ws_alpha["dir"], "sub"), check=True)
    ws_alpha_wt2 = make_ws("alpha-wt2-ws", ai_cmd="sleep 300")
    tmux("set-option", "-q", "-t", "=alpha-wt2-ws:", "@ide_workdir", wt2_dir, check=True)

    # Idle dirty shared worktree -> NO collision warning!
    idle_wt_prev = _ansi_strip_re.sub("", run_cmd([ide_bin, "--session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
    idle_wt_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert "Warning  : Shared worktree" not in idle_wt_prev, f"false-positive worktree warning while idle: {idle_wt_prev}"
    assert not any("alpha-ws" in ln and ln.rstrip().endswith(" !") for ln in idle_wt_list), f"false-positive ! suffix while idle: {idle_wt_list}"

    # When alpha-ws enters WORKING -> both alpha-ws and alpha-sub-ws warn, while separate git worktree alpha-wt2-ws stays clean!
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    work_wt_prev_raw = run_cmd([ide_bin, "--session-preview", "alpha-sub-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    work_wt_prev = _ansi_strip_re.sub("", work_wt_prev_raw)
    wt2_prev = _ansi_strip_re.sub("", run_cmd([ide_bin, "--session-preview", "alpha-wt2-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
    work_wt_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert "Warning  : Shared worktree with alpha-ws" in work_wt_prev, f"missing shared-worktree warning in preview: {work_wt_prev}"
    assert "\x1b[38;2;181;137;0mShared worktree with alpha-ws" in work_wt_prev_raw, f"expected Solarized Yellow on shared-worktree warning: {work_wt_prev_raw!r}"
    assert "Warning  : Shared worktree" not in wt2_prev, f"separate git worktree falsely warned: {wt2_prev}"
    assert any("alpha-ws" in ln and ln.rstrip().endswith(" !") for ln in work_wt_list), f"missing ! suffix on alpha-ws: {work_wt_list}"
    assert any("alpha-sub-ws" in ln and ln.rstrip().endswith(" !") for ln in work_wt_list), f"missing ! suffix on alpha-sub-ws: {work_wt_list}"
    assert not any("alpha-wt2-ws" in ln and ln.rstrip().endswith(" !") for ln in work_wt_list), f"false ! suffix on separate git worktree: {work_wt_list}"
    run_cmd([ide_bin, "--quit", "--force", "alpha-sub-ws", "alpha-wt2-ws", "delta-ws", "shell-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)

    # (9e) Cross-session ide --send --switch stages payload without Enter, focuses target AI pane, and switches active client!
    recv_beta_sw = os.path.join(root, "ai_recv_beta_sw.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_beta_sw}'",
        check=True,
    )
    time.sleep(0.1)
    tmux("switch-client", "-c", client_name, "-t", "=alpha-ws", check=True)
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    _read_pty_chunk(0.1)
    beta_mod = os.path.join(ws_beta["dir"], "sub", "mod.py")
    run_cmd(
        [ide_bin, "--send", "--ref", f"{beta_mod}:5-7", "--switch", "beta-ws"],
        env={**sess_env("alpha-ws", ws_alpha["ed"]), "IDE_CLIENT": client_name},
        check=True,
    )
    _read_pty_chunk(0.15)
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "beta-ws", "--send --switch did not switch active client to beta-ws"
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai", "--send --switch did not focus beta-ws AI pane"
    assert wait_until(lambda: os.path.isfile(recv_beta_sw) and "@sub/mod.py#L5-L7 " in open(recv_beta_sw, encoding="utf-8").read()), "--send --switch payload did not arrive in beta-ws AI pane"
    sw_stream = open(recv_beta_sw, encoding="utf-8").read().replace("\x1b[200~", "").replace("\x1b[201~", "")
    assert sw_stream == "@sub/mod.py#L5-L7 " and "\n" not in sw_stream, f"--send --switch unexpectedly submitted newline: {sw_stream!r}"

    # (9f) In-picker Alt+n workspace spawner (zoxide query -l + Esc loop back + launch & switch + $HOME subdir fallback)
    spawn_dir = os.path.join(thome, "projects", "spawned-ws")
    os.makedirs(spawn_dir, exist_ok=True)
    mock_zoxide = os.path.join(root, "mock-zoxide.sh")
    with open(mock_zoxide, "w", encoding="utf-8") as zf:
        zf.write(f'#!/bin/sh\nif [ "$1" = "query" ] && [ "$2" = "-l" ]; then printf "%s\\n" {shlex.quote(spawn_dir)}; fi\n')
    os.chmod(mock_zoxide, 0o755)

    altn_state = os.path.join(root, "altn_state.txt")
    altn_fzf = os.path.join(root, "altn-fzf.py")
    with open(altn_fzf, "w", encoding="utf-8") as af:
        af.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"st_path = {altn_state!r}\n"
            "step = int(open(st_path).read().strip()) if os.path.isfile(st_path) else 0\n"
            "open(st_path, 'w').write(str(step + 1))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "args = ' '.join(sys.argv[1:])\n"
            "if step == 0:\n"
            "    assert 'ctrl-y:execute-silent' in args and 'ctrl-o:execute-silent' in args and 'alt-n' in args, f'missing triage/launcher binds: {args}'\n"
            "    assert '--border=rounded' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · C-x: quit · C-r: reload · Alt+s: close ' in args and '--header=' not in args, f'missing bottom border-label on step 0: {args}'\n"
            "    print('alt-n')\n"
            "    print(lines[0])\n"
            "elif step == 1:\n"
            "    assert '--prompt=New IDE > ' in args and '--border=rounded' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: launch workspace · Esc: back to sessions ' in args and '--color=label:#586E75' in args and '--header=' not in args, f'expected New IDE prompt and bottom border-label on step 1: {args}'\n"
            "    sys.exit(130)\n"
            "elif step == 2:\n"
            "    assert '--prompt=IDE > ' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: switch · C-a/e/t: pane · C-y: ack · C-o: PR · M-n: new · C-x: quit · C-r: reload · Alt+s: close ' in args, f'Esc from Alt+n did not return to session list: {args}'\n"
            "    print('alt-n')\n"
            "elif step == 3:\n"
            "    assert '--border=rounded' in args and '--border-label-pos=bottom' in args and '--border-label= Enter: launch workspace · Esc: back to sessions ' in args, f'expected bottom border-label on step 3: {args}'\n"
            "    picked = next(l for l in lines if 'spawned-ws' in l)\n"
            "    print(picked)\n"
        )
    os.chmod(altn_fzf, 0o755)

    run_cmd(
        [ide_bin, "--sessions", "beta-ws"],
        env={
            **sess_env("beta-ws", ws_beta["ed"]),
            "IDE_NO_POPUP": "1",
            "IDE_FZF_BIN": altn_fzf,
            "IDE_ZOXIDE_BIN": mock_zoxide,
            "IDE_CLIENT": client_name,
        },
        check=True,
    )
    _read_pty_chunk(0.2)
    assert open(altn_state, encoding="utf-8").read().strip() == "4", f"expected 4 fzf invocations across Alt+n -> Esc -> Alt+n -> Enter, got {open(altn_state).read()!r}"
    assert tmux("has-session", "-t", "=spawned-ws", check=False).returncode == 0, "Alt+n did not spawn spawned-ws session"
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "spawned-ws", "Alt+n did not switch client into spawned-ws"

    # Also verify $HOME immediate subdirectory fallback when zoxide is unavailable/empty
    empty_zoxide = os.path.join(root, "empty-zoxide.sh")
    with open(empty_zoxide, "w", encoding="utf-8") as ez:
        ez.write("#!/bin/sh\nexit 1\n")
    os.chmod(empty_zoxide, 0o755)
    home_fb_dir = os.path.join(thome, "fallback-ws")
    os.makedirs(home_fb_dir, exist_ok=True)
    fb_state = os.path.join(root, "fb_state.txt")
    fb_fzf = os.path.join(root, "fb-fzf.py")
    with open(fb_fzf, "w", encoding="utf-8") as ff:
        ff.write(
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"st_path = {fb_state!r}\n"
            "step = int(open(st_path).read().strip()) if os.path.isfile(st_path) else 0\n"
            "open(st_path, 'w').write(str(step + 1))\n"
            "lines = [l.rstrip('\\n') for l in sys.stdin if l.strip()]\n"
            "if step == 0:\n"
            "    print('alt-n')\n"
            "else:\n"
            "    picked = next(l for l in lines if 'fallback-ws' in l)\n"
            "    print(picked)\n"
        )
    os.chmod(fb_fzf, 0o755)
    run_cmd(
        [ide_bin, "--sessions", "spawned-ws"],
        env={
            **sess_env("spawned-ws"),
            "IDE_NO_POPUP": "1",
            "IDE_FZF_BIN": fb_fzf,
            "IDE_ZOXIDE_BIN": empty_zoxide,
            "IDE_CLIENT": client_name,
        },
        check=True,
    )
    _read_pty_chunk(0.2)
    assert tmux("has-session", "-t", "=fallback-ws", check=False).returncode == 0
    assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "fallback-ws"

    # (9g) QUOTA fleet state: passive @ide_ai_attn=0, elapsed age preservation, Tier 2 ordering (WORKING > QUOTA > IDLE > SHELL), focus preservation, and SHELL guard
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec sleep 300", check=True)
    tmux("respawn-pane", "-k", "-t", ws_beta["ai"], "-c", ws_beta["dir"], "exec sleep 300", check=True)
    tmux("respawn-pane", "-k", "-t", ws_gamma["ai"], "-c", ws_gamma["dir"], "exec sleep 300", check=True)
    assert wait_until(
        lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_beta["ai"], "#{pane_current_command}") == "sleep"
        and tmux_out("display-message", "-p", "-t", ws_gamma["ai"], "#{pane_current_command}") == "sleep"
    )
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    _read_pty_chunk(0.15)
    run_cmd([ide_bin, "--quit", "--force", "spawned-ws", "fallback-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    open(notify_hook_log, "w", encoding="utf-8").close()
    open(os_notify_log, "w", encoding="utf-8").close()

    run_cmd([ide_bin, "--agent-state", "running", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    run_cmd([ide_bin, "--agent-state", "idle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    run_cmd([ide_bin, "--agent-state", "quota", "alpha-ws"], env={**notif_base_env, "IDE_NOTIFY": "always"}, check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "quota"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_attn") == "0", "quota state must stay passive (@ide_ai_attn=0)"
    assert tmux_out("show-options", "-gqv", "@ide_attn_summary") == "", "quota state must not enter @ide_attn_summary"
    time.sleep(0.1)
    assert open(notify_hook_log, encoding="utf-8").read() == "" and open(os_notify_log, encoding="utf-8").read() == "", "quota state must not fire attention notifications"

    tmux("set-option", "-q", "-t", "=alpha-ws:", "@ide_ai_state_ts", str(now_epoch - 720), check=True)
    run_cmd([ide_bin, "--agent-state", "quota", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state_ts") == str(now_epoch - 720), "repeated quota hook reset @ide_ai_state_ts!"

    quota_order = run_cmd([ide_bin, "--list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert quota_order == ["beta-ws", "alpha-ws", "gamma-ws"], f"expected WORKING (beta-ws) > QUOTA (alpha-ws) > IDLE (gamma-ws), got {quota_order}"
    quota_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "QUOTA 12m" in quota_list, f"expected QUOTA 12m in --list: {quota_list}"
    quota_prev = run_cmd([ide_bin, "--session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "QUOTA 12m" in quota_prev, f"expected QUOTA 12m in --session-preview: {quota_prev}"

    # Focusing AI pane (--ack-ai --hook) must preserve active quota state while child process is alive,
    # and classify_ide_fleet() must clear stale quota to SHELL once the AI process exits to a bare shell.
    run_cmd([ide_bin, "--ack-ai", "--hook", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "quota", "--ack-ai --hook wiped live quota state!"
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sh")
    shell_after_quota = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout.splitlines()
    assert any("alpha-ws" in ln and "SHELL" in ln for ln in shell_after_quota), f"exited quota pane did not transition to SHELL: {shell_after_quota}"
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_state") == "", "classify_ide_fleet did not clear stale @ide_ai_state=quota on bare shell"

    # 10. Adversarial regression coverage for F-02..F-13:
    # (10a) F-02: classify_ide_fleet() #{window_active} & OS focus guard (background window must NOT auto-clear done attention)
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec sleep 300", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sleep")
    tmux("switch-client", "-c", client_name, "-t", "=beta-ws", check=True)
    tmux("select-pane", "-t", ws_beta["ai"], check=True)
    assert wait_until(lambda: (drain_pty() or "focused" in tmux_out("list-clients", "-t", "=beta-ws", "-F", "#{client_flags}")))
    bg_win_id = tmux_out("new-window", "-P", "-F", "#{window_id}", "-t", "=beta-ws", "-n", "scratch", "exec sleep 300")
    drain_pty()
    run_cmd([ide_bin, "--agent-state", "done", "beta-ws"], env=sess_env("beta-ws", ws_beta["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "done while viewing 2nd tmux window failed to set @ide_ai_attn=1!"
    run_cmd([ide_bin, "--list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "1", "classify_ide_fleet falsely cleared done attention while AI window was inactive!"
    tmux("kill-window", "-t", bg_win_id, check=True)
    drain_pty()
    run_cmd([ide_bin, "--list", "--plain"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=beta-ws:", "@ide_ai_attn") == "0", "classify_ide_fleet did not clear done once active focused AI window returned!"

    # (10b) F-06: @ide_ai_msg persistence, ANSI/8-bit CSI/control stripping, 160-char cap, repeat preservation, Message preview, and state-transition clearing
    long_dirty_msg = "[\x1b[32mOK\x1b[0m] \x9b31mRate limit\x9b0m\t\nhit: " + ("x" * 180)
    run_cmd([ide_bin, "--agent-state", "quota", "--message", long_dirty_msg, "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    stored_msg = tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg")
    assert stored_msg.startswith("[OK] Rate limit hit: ") and "\x1b" not in stored_msg and "\x9b" not in stored_msg and "\t" not in stored_msg and len(stored_msg) == 160 and stored_msg.endswith("…"), f"bad @ide_ai_msg sanitization/cap: {stored_msg!r}"
    # Repeat quota hook without --message preserves existing @ide_ai_msg
    run_cmd([ide_bin, "--agent-state", "quota", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == stored_msg, "repeat quota hook wiped @ide_ai_msg!"
    prev_msg_out = _ansi_strip_re.sub("", run_cmd([ide_bin, "--session-preview", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
    assert "Message  : [OK] Rate limit hit:" in prev_msg_out, f"missing Message row in --session-preview: {prev_msg_out}"
    # Transitioning to running clears @ide_ai_msg
    run_cmd([ide_bin, "--agent-state", "running", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "", "running state did not clear @ide_ai_msg!"
    # Approval preserves @ide_ai_msg across focus/ack; done clears @ide_ai_msg when acknowledged to idle
    tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
    drain_pty()
    run_cmd([ide_bin, "--agent-state", "approval", "--message", "Approve rm -rf build?", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    run_cmd([ide_bin, "--ack-ai", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "Approve rm -rf build?", "acknowledging approval wiped @ide_ai_msg!"
    run_cmd([ide_bin, "--agent-state", "done", "--message", "All tests green", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ai"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "All tests green"
    run_cmd([ide_bin, "--ack-ai", "alpha-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)
    assert tmux_out("show-options", "-qv", "-t", "=alpha-ws:", "@ide_ai_msg") == "", "acking done -> idle did not clear @ide_ai_msg!"

    # (10c) F-05: Ctrl+x (--quit {+1}, including multi-select) in Alt+s popup (IDE_IN_POPUP=1) on dirty Neovim buffer NEVER hijacks outer client and surfaces [unsaved] + Warning
    if shutil.which("nvim"):
        ws_pop_dirty = make_ws("pop-dirty-ws", ai_cmd="sleep 300")
        ws_pop_clean = make_ws("pop-clean-ws", ai_cmd="sleep 300")
        _ = ws_pop_clean
        pop_sock = tmux_out("show-options", "-qv", "-t", "=pop-dirty-ws:", "@ide_socket")
        pop_file = os.path.join(ws_pop_dirty["dir"], "unsaved_pop.txt")
        tmux(
            "respawn-pane", "-k", "-t", ws_pop_dirty["ed"], "-c", ws_pop_dirty["dir"],
            f"nvim --headless -u NONE -i NONE --listen {shlex.quote(pop_sock)} -c {shlex.quote('edit ' + pop_file)} -c \"call setline(1, 'unsaved')\"",
            check=True,
        )
        assert wait_until(lambda: nvim_expr_eq(pop_sock, "&modified", "1")), "pop-dirty-ws nvim buffer did not become modified"
        tmux("switch-client", "-c", client_name, "-t", "=gamma-ws", check=True)
        drain_pty()
        r_pop_q = run_cmd(
            [ide_bin, "--quit", "pop-dirty-ws", "pop-clean-ws"],
            env={**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_IN_POPUP": "1", "IDE_CLIENT": client_name},
            check=False,
        )
        assert r_pop_q.returncode != 0, "expected non-zero from popup --quit when one selected session has dirty buffers"
        assert tmux("has-session", "-t", "=pop-clean-ws", check=False).returncode != 0, "clean session in multi-quit should still close"
        assert tmux("has-session", "-t", "=pop-dirty-ws", check=False).returncode == 0, "dirty session must survive multi-quit"
        assert tmux_out("display-message", "-p", "-t", client_name, "#{session_name}") == "gamma-ws", "IDE_IN_POPUP=1 --quit hijacked outer client behind popup!"
        assert "Unsaved changes" in tmux_out("show-options", "-qv", "-t", "=pop-dirty-ws:", "@ide_quit_err")
        pop_lines = _ansi_strip_re.sub("", run_cmd([ide_bin, "--sessions-lines", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
        assert "[unsaved]" in pop_lines, f"missing [unsaved] badge in --sessions-lines: {pop_lines}"
        pop_prev = _ansi_strip_re.sub("", run_cmd([ide_bin, "--session-preview", "pop-dirty-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
        assert "Warning  : Unsaved changes in 1 buffer(s)" in pop_prev, f"missing Warning in --session-preview: {pop_prev}"
        # Saving buffer in Neovim auto-clears @ide_quit_err on next preview!
        subprocess.run(["nvim", "--headless", "--server", pop_sock, "--remote-send", "<C-\\><C-n>:write!<CR>"], env=base_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=True)
        assert wait_until(lambda: nvim_expr_eq(pop_sock, "&modified", "0")), "pop-dirty-ws nvim buffer did not become clean after :write!"
        pop_prev_clean = _ansi_strip_re.sub("", run_cmd([ide_bin, "--session-preview", "pop-dirty-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout)
        assert "Unsaved changes" not in pop_prev_clean and tmux_out("show-options", "-qv", "-t", "=pop-dirty-ws:", "@ide_quit_err") == ""
        run_cmd([ide_bin, "--quit", "pop-dirty-ws"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True)

    # (10d) F-07: send_to_ai() refuses bare shell AI pane and strips nested \x1b[200~ / \x1b[201~ / \x9b201~ bracketed-paste escapes
    tmux("respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"], "exec /bin/sh", check=True)
    assert wait_until(lambda: tmux_out("display-message", "-p", "-t", ws_alpha["ai"], "#{pane_current_command}") == "sh")
    r_bare_send = run_cmd([ide_bin, "--send", "--text", "echo PWNED_BARE_SHELL", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=False)
    assert r_bare_send.returncode != 0 and "idle shell prompt" in r_bare_send.stderr, f"expected bare-shell refusal on --send, got {r_bare_send}"
    assert "PWNED_BARE_SHELL" not in tmux_out("capture-pane", "-p", "-t", ws_alpha["ai"]), "send_to_ai pasted into bare shell!"

    recv_bp = os.path.join(root, "ai_recv_bp.txt")
    tmux(
        "respawn-pane", "-k", "-t", ws_alpha["ai"], "-c", ws_alpha["dir"],
        f"/bin/sh -c 'stty -echo -icanon min 1 time 0; exec cat > {recv_bp}'",
        check=True,
    )
    time.sleep(0.1)
    run_cmd([ide_bin, "--send", "--no-focus", "--text", "safe\x1b[20\x1b[201~1~mid\x1b[200~end\x9b201~!", "alpha-ws"], env=sess_env("alpha-ws", ws_alpha["ed"]), check=True)
    assert wait_until(lambda: os.path.isfile(recv_bp) and "safe" in open(recv_bp, encoding="utf-8").read())
    bp_raw = open(recv_bp, encoding="utf-8").read()
    # Outer paste-buffer -p wraps at most once; inner payload must contain zero embedded 200~/201~ breakouts!
    bp_inner = bp_raw
    if bp_inner.startswith("\x1b[200~"):
        bp_inner = bp_inner[len("\x1b[200~"):]
    if bp_inner.endswith("\x1b[201~"):
        bp_inner = bp_inner[: -len("\x1b[201~")]
    assert bp_inner == "safemidend!", f"nested bracketed-paste escapes were not stripped: {bp_raw!r}"

    # (10e) F-08: open_browser_url() blocks leading '-' option flags and non-http(s) schemes from ide_resolve_link
    open(browser_log, "w", encoding="utf-8").close()
    with open(rules_file, "w", encoding="utf-8") as rf:
        rf.write(
            'ide_resolve_link() {\n'
            '  case "$1" in\n'
            '    badflag) echo "-aCalculator" ;;\n'
            '    badjs) echo "javascript:alert(1)" ;;\n'
            '    goodurl) echo "https://example.com/safe-target" ;;\n'
            '  esac\n'
            '}\n'
        )
    link_env_f08 = {**sess_env("gamma-ws", ws_gamma["ed"]), "IDE_BROWSER": mock_browser}
    assert run_cmd([ide_bin, "--open-link", "", "badflag", ws_gamma["dir"], "gamma-ws"], env=link_env_f08, check=False).returncode != 0
    assert run_cmd([ide_bin, "--open-link", "", "badjs", ws_gamma["dir"], "gamma-ws"], env=link_env_f08, check=False).returncode != 0
    assert open(browser_log, encoding="utf-8").read() == "", f"unsafe ide_resolve_link output launched browser: {open(browser_log, encoding='utf-8').read()!r}"
    run_cmd([ide_bin, "--open-link", "", "goodurl", ws_gamma["dir"], "gamma-ws"], env=link_env_f08, check=True)
    assert wait_until(lambda: open(browser_log, encoding="utf-8").read().strip() == "https://example.com/safe-target")

    # (10f) F-09: resolve_ai_cmd() quotes executable paths containing spaces and falls back when IDE_AI_CLI is uninstalled
    open(os.path.join(thome, ".zshrc"), "a", encoding="utf-8").close()
    spaced_dir = os.path.join(root, "dir with spaces")
    os.makedirs(spaced_dir, exist_ok=True)
    spaced_cli = os.path.join(spaced_dir, "custom agent")
    spaced_marker = os.path.join(root, "spaced_agent_ran.txt")
    with open(spaced_cli, "w", encoding="utf-8") as sf:
        sf.write(f"#!/bin/sh\necho ok > {shlex.quote(spaced_marker)}\nexec sleep 300\n")
    os.chmod(spaced_cli, 0o755)
    f09_ws_dir = os.path.join(root, "f09-spaced-ws")
    os.makedirs(f09_ws_dir, exist_ok=True)
    run_cmd([ide_bin, "--detach", "--ai", spaced_cli, f09_ws_dir], env=base_env, check=True)
    assert wait_until(lambda: os.path.isfile(spaced_marker), timeout=3.0), "spaced AI CLI path failed to launch via send-keys!"
    run_cmd([ide_bin, "--quit", "--force", "f09-spaced-ws"], env=base_env, check=True)

    f09_fb_dir = os.path.join(root, "f09-fb-ws")
    os.makedirs(f09_fb_dir, exist_ok=True)
    mock_claude_dir = os.path.join(root, "mock_claude_bin")
    os.makedirs(mock_claude_dir, exist_ok=True)
    for sys_tool in ("tmux", "bash", "sh", "zsh", "python3", "env", "sleep", "mktemp", "rm", "ps"):
        real_t = shutil.which(sys_tool)
        if real_t and not os.path.exists(os.path.join(mock_claude_dir, sys_tool)):
            os.symlink(real_t, os.path.join(mock_claude_dir, sys_tool))
    fb_claude_marker = os.path.join(root, "fb_claude_ran.txt")
    with open(os.path.join(mock_claude_dir, "claude"), "w", encoding="utf-8") as cf:
        cf.write(f"#!/bin/sh\necho fallback_ok > {shlex.quote(fb_claude_marker)}\nexec sleep 300\n")
    os.chmod(os.path.join(mock_claude_dir, "claude"), 0o755)
    run_cmd(
        [ide_bin, "--detach", f09_fb_dir],
        env={**base_env, "IDE_STRICT_PATH": "1", "IDE_AI_CLI": "nonexistent-custom-ai-xyz", "PATH": mock_claude_dir},
        check=True,
    )
    assert tmux_out("show-options", "-qv", "-t", "=f09-fb-ws:", "@ide_ai_cli") == "claude", "missing IDE_AI_CLI did not update @ide_ai_cli to fallback 'claude'"
    assert wait_until(lambda: os.path.isfile(fb_claude_marker), timeout=3.0), "missing IDE_AI_CLI did not fall back cleanly to claude!"
    run_cmd([ide_bin, "--quit", "--force", "f09-fb-ws"], env=base_env, check=True)

    f09_cwd_dir = os.path.join(root, "f09-cwd-ws")
    os.makedirs(f09_cwd_dir, exist_ok=True)
    cwd_agent_marker = os.path.join(root, "cwd_agent_ran.txt")
    with open(os.path.join(f09_cwd_dir, "local-agent-bin"), "w", encoding="utf-8") as lcf:
        lcf.write(f"#!/bin/sh\necho cwd_ok > {shlex.quote(cwd_agent_marker)}\nexec sleep 300\n")
    os.chmod(os.path.join(f09_cwd_dir, "local-agent-bin"), 0o755)
    subprocess.run(
        [ide_bin, "--detach", "--ai", "local-agent-bin", f09_cwd_dir],
        cwd=f09_cwd_dir,
        env={**base_env, "IDE_STRICT_PATH": "1", "PATH": mock_claude_dir},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    assert wait_until(lambda: os.path.isfile(cwd_agent_marker), timeout=3.0), "CWD-local --ai executable without '/' fell back to claude instead of launching!"
    run_cmd([ide_bin, "--quit", "--force", "f09-cwd-ws"], env=base_env, check=True)

    # (10g) F-04 CLI status_click() bounds, ad-hoc split role, & F-11 ad-hoc split Alt+a bounce-back + unpark_role_pane geometry
    tmux("select-pane", "-t", ws_gamma["ed"], check=True)
    adhoc_pane = tmux_out("split-window", "-h", "-P", "-F", "#{pane_id}", "-t", ws_gamma["ed"], "-c", ws_gamma["dir"], "exec sleep 300")
    assert tmux_out("show-options", "-pqv", "-t", adhoc_pane, "@ide_role") == "", "ad-hoc split should keep empty @ide_role"
    # Out-of-bounds status_click (x=135) must be a strict no-op (both unzoomed and zoomed)!
    run_cmd([ide_bin, "--status-click", "135", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{pane_id}") == adhoc_pane, "out-of-bounds status_click hijacked focus!"
    tmux("resize-pane", "-Z", "-t", adhoc_pane, check=True)
    run_cmd([ide_bin, "--status-click", "135", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{window_zoomed_flag}") == "1", "out-of-bounds status_click unzoomed pane!"
    tmux("resize-pane", "-Z", "-t", adhoc_pane, check=True)
    # Alt+a (--toggle) from ad-hoc split focuses AI, and second Alt+a bounces right back to adhoc_pane!
    run_cmd([ide_bin, "--toggle", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{pane_id}") == ws_gamma["ai"]
    run_cmd([ide_bin, "--toggle", "gamma-ws"], env=sess_env("gamma-ws", ws_gamma["ai"]), check=True)
    assert tmux_out("display-message", "-p", "-t", "=gamma-ws:", "#{pane_id}") == adhoc_pane, "Alt+a failed to bounce back to ad-hoc split!"
    # Park AI and Editor while Shell (bar_role) AND adhoc_pane stay visible -> unparking Editor joins horizontally beside adhoc_pane (not 3 vertical rows)!
    run_cmd([ide_bin, "--toggle-editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    run_cmd([ide_bin, "--toggle-ai", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    run_cmd([ide_bin, "--toggle-editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    ed_top_w_bar = tmux_out("display-message", "-p", "-t", ws_gamma["ed"], "#{pane_top}")
    adhoc_top_w_bar = tmux_out("display-message", "-p", "-t", adhoc_pane, "#{pane_top}")
    assert ed_top_w_bar == adhoc_top_w_bar, f"unpark_role_pane stacked Editor vertically instead of beside adhoc_pane: ed_top={ed_top_w_bar} adhoc_top={adhoc_top_w_bar}"
    # Park all 3 canonical panes while adhoc_pane stays visible, then unpark Editor alongside adhoc_pane!
    run_cmd([ide_bin, "--toggle-term", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    run_cmd([ide_bin, "--toggle-editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    assert tmux_out("list-panes", "-t", "=gamma-ws:", "-F", "#{pane_id}").splitlines() == [adhoc_pane]
    run_cmd([ide_bin, "--toggle-editor", "gamma-ws"], env=sess_env("gamma-ws", adhoc_pane), check=True)
    vis_after_unpark = tmux_out("list-panes", "-t", "=gamma-ws:", "-F", "#{pane_id}").splitlines()
    assert adhoc_pane in vis_after_unpark and ws_gamma["ed"] in vis_after_unpark, f"unpark_role_pane failed when only ad-hoc split was visible: {vis_after_unpark}"
    tmux("kill-pane", "-t", adhoc_pane, check=True)

    # (10h) F-13: literal tab character in workspace directory path + odd/even/comment trailing backslashes & quoted leading-space continuations in .git/config
    tab_ws_dir = os.path.join(root, "dir\twith\ttab")
    os.makedirs(tab_ws_dir, exist_ok=True)
    run_cmd(["git", "-C", tab_ws_dir, "init", "-q", "-b", "feat/tab-bs"], check=True)
    with open(os.path.join(tab_ws_dir, ".git", "config"), "a", encoding="utf-8") as gcf:
        gcf.write(
            '# Windows path comment ending in backslash C:\\\n'
            '[url "https://github.com/wrong/"]\n'
            '\tinsteadOf = corp\\\\\\\\\n'
            '[url "https://gitlab.com/acme/"]\n'
            '\tinsteadOf = "corp\\"bs\\\\\\\n  sp:"\n'
            '# Another backslash comment \\\n'
            '[remote "orig\\"in\\\\1"]\n'
            '\turl = "corp\\"bs\\\\  sp:tabrepo.git" # trailing comment \\\n'
            '[branch "feat/tab-bs"]\n'
            '\tpr = \\\n'
            '\t\t91 # inline comment ending in \\\n'
            '\tremote = "orig\\"in\\\\1"\n'
        )
    tmux("set-option", "-q", "-t", "=beta-ws:", "@ide_workdir", tab_ws_dir, check=True)
    tab_list = run_cmd([ide_bin, "--list"], env=sess_env("gamma-ws", ws_gamma["ed"]), check=True).stdout
    assert "feat/tab-bs@91" in tab_list and "beta-ws" in tab_list, f"literal tab path or odd/even backslash config broke --list: {tab_list!r}"
    open(browser_log, "w", encoding="utf-8").close()
    run_cmd([ide_bin, "--open-pr", "beta-ws"], env={**sess_env("beta-ws", ws_beta["ed"]), "IDE_BROWSER": mock_browser}, check=True)
    assert wait_until(lambda: open(browser_log, encoding="utf-8").read().strip() == "https://gitlab.com/acme/tabrepo/-/merge_requests/91"), (
        f"even trailing backslash in .git/config corrupted remote URL: {open(browser_log, encoding='utf-8').read()!r}"
    )

    # (10i) tmux <= 3.4 utf8_stravis C0-octal escaping regression guard:
    # Older tmux releases (e.g. Ubuntu 22.04/24.04 tmux 3.2a/3.4) escape non-tab/newline C0 control
    # characters (< 0x20 except \t and \n) in display-message / list-* format strings as octal \037.
    # Ensure bin/ide uses printable/tab-based _TMUX_SEP and survives C0-octal-escaped tmux format output
    # even when @ide_workdir contains literal tab characters.
    ide_full_src = open(real_ide_path, encoding="utf-8").read()
    assert '_TMUX_SEP = "\\t__IDE_SEP__\\t"' in ide_full_src, "missing printable/tab _TMUX_SEP delimiter in bin/ide"
    real_tmux_bin = shutil.which("tmux")
    assert real_tmux_bin, "tmux binary not found on PATH"
    tmux34_dir = os.path.join(root, "tmux34_compat_bin")
    os.makedirs(tmux34_dir, exist_ok=True)
    tmux34_hits = os.path.join(root, "tmux34_hits.log")
    tmux34_wrap = os.path.join(tmux34_dir, "tmux")
    with open(tmux34_wrap, "w", encoding="utf-8") as twf:
        twf.write(
            "#!/usr/bin/env python3\n"
            "import subprocess, sys\n"
            f"REAL_TMUX = {real_tmux_bin!r}\n"
            f"HIT_LOG = {tmux34_hits!r}\n"
            "FMT_CMDS = {'display-message', 'display', 'list-sessions', 'ls', 'list-panes', 'lsp', 'list-clients', 'lsc', 'list-windows', 'lsw'}\n"
            "r = subprocess.run([REAL_TMUX, *sys.argv[1:]], stdout=subprocess.PIPE, stderr=subprocess.PIPE)\n"
            "out = r.stdout\n"
            "if any(a in FMT_CMDS for a in sys.argv[1:]):\n"
            "    with open(HIT_LOG, 'a', encoding='utf-8') as hf:\n"
            "        hf.write('1\\n')\n"
            "    escaped = bytearray()\n"
            "    for b in out:\n"
            "        if b < 0x20 and b not in (0x09, 0x0a):\n"
            "            escaped.extend(f'\\\\{b:03o}'.encode('ascii'))\n"
            "        else:\n"
            "            escaped.append(b)\n"
            "    out = bytes(escaped)\n"
            "sys.stdout.buffer.write(out)\n"
            "sys.stderr.buffer.write(r.stderr)\n"
            "sys.exit(r.returncode)\n"
        )
    os.chmod(tmux34_wrap, 0o755)
    t34_path = f"{tmux34_dir}:{base_env['PATH']}"
    env_t34_ed = {**sess_env("beta-ws", ws_beta["ed"]), "PATH": t34_path}
    t34_plain = run_cmd([ide_bin, "--list", "--plain"], env=env_t34_ed, check=True).stdout.splitlines()
    assert t34_plain and t34_plain[0] == "beta-ws" and {"alpha-ws", "beta-ws", "gamma-ws"}.issubset(set(t34_plain)), (
        f"tmux 3.4 C0-octal escaping broke current_ide_session / --list --plain: {t34_plain!r}"
    )
    t34_list = run_cmd([ide_bin, "--list"], env=env_t34_ed, check=True).stdout
    assert "feat/tab-bs@91" in t34_list and "beta-ws" in t34_list, f"tmux 3.4 C0-octal escaping broke --list with tab path: {t34_list!r}"
    panes_before_t34 = tmux_out("list-panes", "-t", "=beta-ws:", "-F", "#{pane_id}").splitlines()
    tmux("select-pane", "-t", ws_beta["ed"], check=True)
    run_cmd([ide_bin, "--toggle", "beta-ws"], env=env_t34_ed, check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "ai", "tmux 3.4 C0-octal escaping broke --toggle -> ai"
    run_cmd([ide_bin, "--toggle", "beta-ws"], env={**sess_env("beta-ws", ws_beta["ai"]), "PATH": t34_path}, check=True)
    assert tmux_out("display-message", "-p", "-t", "=beta-ws:", "#{@ide_role}") == "editor", "tmux 3.4 C0-octal escaping broke --toggle -> editor"
    panes_after_t34 = tmux_out("list-panes", "-t", "=beta-ws:", "-F", "#{pane_id}").splitlines()
    assert panes_after_t34 == panes_before_t34, f"tmux 3.4 C0-octal escaping spawned extra panes during --toggle: {panes_before_t34} -> {panes_after_t34}"
    assert os.path.isfile(tmux34_hits) and len(open(tmux34_hits, encoding="utf-8").read().splitlines()) >= 4, "tmux34_wrap shim did not intercept tmux format commands!"

    # Also verify dotfiles/.tmux.conf preserves status-bar click fallback when #{mouse_status_range} is empty (tmux < 3.4, e.g. 3.2a/3.3a)
    tmux_conf_txt = open(tmux_conf_src, encoding="utf-8").read()
    for status_ev in ("MouseDown1Status", "DoubleClick1Status", "TripleClick1Status"):
        assert re.search(rf"bind -n {status_ev}\b.*mouse_status_range\}},.*--status-click", tmux_conf_txt), (
            f"missing tmux < 3.4 empty mouse_status_range --status-click fallback on {status_ev}"
        )

    print("ALL_FLEET_OK")
finally:
    for mfd in (client2_mfd, client_mfd):
        if mfd is not None:
            try:
                os.close(mfd)
            except OSError:
                pass
    for cproc in (client2_proc, client_proc):
        if cproc is not None:
            try:
                cproc.terminate()
                cproc.wait(timeout=2.0)
            except Exception:
                try:
                    cproc.kill()
                except Exception:
                    pass
    try:
        if xdg_run and os.path.isdir(xdg_run) and shutil.which("nvim"):
            for fn in os.listdir(xdg_run):
                if fn.endswith(".sock"):
                    sp = os.path.join(xdg_run, fn)
                    subprocess.run(
                        ["nvim", "--headless", "--server", sp, "--remote-send", "<C-\\><C-n><Cmd>qall!<CR>"],
                        env=base_env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=2,
                        check=False,
                    )
    except Exception:
        pass
    try:
        if base_env:
            subprocess.run(
                ["tmux", "kill-server"],
                env={**base_env, "TMUX": "", "TMUX_PANE": ""},
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
    except Exception:
        pass
    shutil.rmtree(root, ignore_errors=True)
PY
    )" || true
    if grep -Fq "ALL_FLEET_OK" <<< "$FLEET_TEST_OUT"; then
        pass "bin/ide multi-session workspace switcher (--list [--plain], -s/--sessions popup & fzf ctrl-a/e/t/ctrl-x/alt-s, --session-preview), deterministic hook-only AI lifecycle (--agent-state, FIFO --next-attention, Alt+Shift+S, stale-hook SHELL guard, parked AI preservation, zero-shift top-bar tinting), and context dispatch (--send)"
    else
        fail "bin/ide multi-session workspace switcher & lifecycle suite" "Suite failed: $FLEET_TEST_OUT"
    fi
fi

test_summary
