"""CLI argument parser and lazy subcommand dispatcher for `bin/ide`."""

from __future__ import annotations

import os
import sys

from ide_lib.constants import SUBCOMMAND_USAGE, safe_getcwd, usage, which_executable


def _is_pos_line_arg(raw: str) -> bool:
    s = raw[1:] if raw.startswith("+") else raw
    return bool(s) and s[0] != "0" and s.isdigit()


_PUBLIC_SUBCOMMANDS = frozenset({
    "list",
    "switch",
    "new",
    "next",
    "cd",
    "refresh",
    "quit",
    "open",
    "send",
    "state",
    "ack",
    "pr",
    "keys",
    "monitor",
})


_SYSTEM_BIN_DIRS = frozenset({
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/sbin",
    "/usr/local/bin",
    "/usr/sbin",
    "/usr/bin",
    "/sbin",
    "/bin",
})


def _strip_trailing_slashes(p: str) -> str:
    if not p or p == "/":
        return p
    stripped = p.rstrip("/")
    return stripped if stripped else "/"


def _calibrate_ide_path() -> None:
    """Keep activated `mise/installs` ahead of `mise/shims` and `mise/shims` ahead of `/usr/bin`."""
    if os.environ.get("IDE_STRICT_PATH", "0") == "1":
        return
    home = _strip_trailing_slashes(os.environ.get("HOME") or os.path.expanduser("~"))
    mise_raw = os.environ.get("MISE_DATA_DIR") or ""
    if mise_raw:
        mise_dir = _strip_trailing_slashes(mise_raw)
    else:
        xdg_data = _strip_trailing_slashes(os.environ.get("XDG_DATA_HOME") or "")
        mise_dir = f"{xdg_data}/mise" if xdg_data else f"{home}/.local/share/mise"
    shims = f"{mise_dir}/shims"
    inst_pfx = f"{mise_dir}/installs/"
    raw_path = os.environ.get("PATH") or ""
    framed = f":{raw_path}:"
    if "/mise/installs/" in framed or inst_pfx in framed:
        filtered: list[tuple[str, str]] = []
        last_mise = 0
        for raw_entry in raw_path.split(":"):
            cp = _strip_trailing_slashes(raw_entry)
            if not cp or cp == shims:
                continue
            filtered.append((raw_entry, cp))
            cp_slash = f"{cp}/"
            if "/mise/installs/" in cp_slash or cp_slash.startswith(inst_pfx):
                last_mise = len(filtered)
        new_parts: list[str] = []
        shims_added = False
        for idx, (raw_entry, cp) in enumerate(filtered, 1):
            if not shims_added and idx > last_mise and cp in _SYSTEM_BIN_DIRS:
                new_parts.append(shims)
                shims_added = True
            new_parts.append(raw_entry)
        if not shims_added:
            new_parts.append(shims)
        os.environ["PATH"] = ":".join([f"{home}/.local/bin", *new_parts, "/usr/local/bin", "/usr/bin", "/bin"])
    else:
        mid = f":{raw_path}" if raw_path else ""
        os.environ["PATH"] = f"{shims}:{home}/.local/bin{mid}:/usr/local/bin:/usr/bin:/bin"


def _looks_like_json_obj(raw: str) -> bool:
    s = raw.strip()
    return len(s) >= 2 and s.startswith("{") and s.endswith("}")


def _normalize_ai_cli(ai_cli: str, from_flag: bool) -> bool:
    if ai_cli in ("agy", "claude", "codex"):
        os.environ["IDE_AI_CLI"] = ai_cli
        return True
    if ai_cli == "openai":
        os.environ["IDE_AI_CLI"] = "codex"
        return True
    if which_executable(ai_cli) or (os.path.isfile(ai_cli) and os.access(ai_cli, os.X_OK)):
        os.environ["IDE_AI_CLI"] = ai_cli
        return True
    if not from_flag:
        fb_cli = next((c for c in ("agy", "claude", "codex") if which_executable(c)), "agy")
        os.environ["IDE_AI_CLI"] = fb_cli
        return True
    print(
        f"Error: Invalid AI CLI '{ai_cli}'. Supported values are: agy, claude, codex (or an executable on PATH).",
        file=sys.stderr,
    )
    return False


def _parse_open_link_args(rem: list[str]) -> tuple[str, str, str, str]:
    link_href = ""
    link_word = ""
    link_cwd = ""
    target_arg = ""
    if (
        len(rem) >= 3
        and os.path.isdir(rem[2])
        and (
            len(rem) >= 4
            or not (os.path.isabs(rem[1]) and os.path.isdir(rem[1]) and not os.path.isabs(rem[2]))
        )
    ):
        link_href, link_word, link_cwd = rem[0], rem[1], rem[2]
        if len(rem) >= 4:
            target_arg = rem[3]
    elif len(rem) >= 2 and os.path.isdir(rem[1]):
        link_href, link_word, link_cwd = "", rem[0], rem[1]
        if len(rem) >= 3:
            target_arg = rem[2]
    elif len(rem) >= 1 and os.path.isdir(rem[0]):
        link_href, link_word, link_cwd = "", "", rem[0]
        if len(rem) >= 2:
            target_arg = rem[1]
    else:
        link_href = rem[0] if len(rem) >= 1 else ""
        link_word = rem[1] if len(rem) >= 2 else ""
        link_cwd = rem[2] if len(rem) >= 3 else ""
        if len(rem) >= 4:
            target_arg = rem[3]
    return link_href, link_word, link_cwd, target_arg


def _dispatch_internal(rem: list[str]) -> int:
    """Dispatch private Tmux, Neovim, clipboard, and `fzf` UI callbacks (`ide _internal <op>`)."""
    if not which_executable("tmux"):
        print("Error: 'tmux' is not installed. Run './setup.sh' to install core packages.", file=sys.stderr)
        return 1
    if not rem:
        print("Error: 'ide _internal' requires an operation.", file=sys.stderr)
        return 1

    op = rem[0]
    rest = rem[1:]

    if op == "refresh-attn":
        from ide_lib.fleet import refresh_fleet_topbar

        return refresh_fleet_topbar()

    if op == "ack-hook":
        from ide_lib.fleet import ack_ai_session

        return ack_ai_session(rest or "", from_hook=True, refresh_always=False)

    if op == "sessions-lines":
        from ide_lib.sessions import build_sessions_lines

        for row in build_sessions_lines(rest[0] if rest else ""):
            print(row)
        return 0

    if op == "session-preview":
        from ide_lib.preview import render_session_preview

        follow = False
        j = 0
        while j < len(rest):
            if rest[j] == "--":
                j += 1
                break
            if rest[j] == "--follow":
                follow = True
                j += 1
                continue
            if rest[j].startswith("-"):
                print(f"Error: Unknown option '{rest[j]}' for 'ide _internal session-preview'.", file=sys.stderr)
                return 1
            break
        if j >= len(rest):
            print("Error: 'ide _internal session-preview' requires a session name.", file=sys.stderr)
            return 1
        return render_session_preview(rest[j], follow=follow)

    if op == "switcher-op":
        from ide_lib.switcher import handle_switcher_op

        if len(rest) < 2:
            print("Error: 'ide _internal switcher-op' requires an operation and switcher session.", file=sys.stderr)
            return 1
        return handle_switcher_op(rest[0], rest[1])

    if op == "heal-socket":
        from ide_lib.nvim_rpc import heal_target_session_socket

        return heal_target_session_socket(rest[0] if rest else "")

    if op in ("copy", "paste"):
        from ide_lib.tmux import (
            copy_to_system_clipboard,
            discover_display_env,
            paste_from_system_clipboard,
            set_allow_tmux_env_fallback,
        )

        arg0 = rest[0] if rest else ""
        set_allow_tmux_env_fallback(True)
        discover_display_env(arg0)
        if op == "copy":
            copy_to_system_clipboard(arg0)
        else:
            paste_from_system_clipboard(arg0)
        return 0

    if op == "open-link":
        from ide_lib.links import open_ide_link

        link_href, link_word, link_cwd, target_arg = _parse_open_link_args(rest)
        return open_ide_link(link_href, link_word, link_cwd, target_arg)

    from ide_lib.layout import (
        run_ai_popup,
        status_click,
        swap_ide_pane,
        toggle_main_pane,
    )

    if op == "status-click":
        x_val = rest[0] if len(rest) >= 1 else "0"
        sess = rest[1] if len(rest) >= 2 else ""
        return status_click(x_val, sess)

    if op == "toggle":
        return toggle_main_pane("toggle", rest[0] if rest else "")

    if op in ("show", "focus", "park"):
        if not rest or rest[0] not in ("ai", "editor", "term"):
            print(f"Error: 'ide _internal {op}' requires a role (ai, editor, or term).", file=sys.stderr)
            return 1
        role = rest[0]
        sess = rest[1] if len(rest) >= 2 else ""
        if op == "show":
            return toggle_main_pane(role, sess)
        if op == "focus":
            return toggle_main_pane(
                f"focus-{role}", sess, skip_checktime=(os.environ.get("IDE_SKIP_CHECKTIME") == "1")
            )
        return toggle_main_pane(f"toggle-{role}", sess)

    if op == "swap":
        if not rest or rest[0].startswith("-"):
            print("Error: 'ide _internal swap' requires a direction (left, down, up, or right).", file=sys.stderr)
            return 1
        sess = rest[1] if len(rest) >= 2 else ""
        return swap_ide_pane(rest[0], sess)

    if op == "ai-popup":
        run_ai_popup(rest[0] if rest else "")
        return 0

    print(f"Error: Unknown internal operation '{op}'.", file=sys.stderr)
    return 1


def _extract_opt_value(args: list[str], idx: int, opt_name: str, hint: str) -> tuple[str | None, int]:
    arg = args[idx]
    if "=" in arg:
        val = arg.split("=", 1)[1]
        if not val:
            print(f"Error: '{opt_name}' requires {hint}.", file=sys.stderr)
            return None, idx
        return val, idx + 1
    if idx + 1 >= len(args) or not args[idx + 1] or args[idx + 1].startswith("-"):
        print(f"Error: '{arg}' requires {hint}.", file=sys.stderr)
        return None, idx
    return args[idx + 1], idx + 2


def main(argv: list[str] | None = None) -> int:
    """Parse CLI arguments and dispatch to the matching `ide_lib` domain handler."""
    raw_self = os.environ.pop("IDE_SELF", "")
    ide_self = (
        os.path.abspath(raw_self)
        if raw_self
        else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "bin", "ide"))
    )
    _calibrate_ide_path()
    os.environ["FORCE_HYPERLINK"] = "1"
    args = sys.argv[1:] if argv is None else list(argv)

    if args and args[0] == "_internal":
        return _dispatch_internal(args[1:])

    layout_mode = "3pane"
    action = "launch"
    detach_mode = os.environ.get("IDE_NO_ATTACH", "0") == "1"
    had_env_ai_cli = bool((os.environ.get("IDE_AI_CLI") or "").strip())
    ai_cli = os.environ.get("IDE_AI_CLI") or "agy"
    ai_cli_from_flag = False
    want_help = False

    # Parse leading launch options or identify the subcommand
    i = 0
    n = len(args)
    end_of_opts = False
    launch_targets: list[str] = []

    while i < n:
        arg = args[i]
        if end_of_opts:
            launch_targets.append(arg)
            i += 1
        elif arg == "--":
            end_of_opts = True
            i += 1
        elif arg in ("-h", "--help"):
            want_help = True
            i += 1
        elif arg == "--2pane":
            layout_mode = "2pane"
            i += 1
        elif arg == "--agent" or arg.startswith("--agent="):
            val, next_i = _extract_opt_value(args, i, "--agent", "an argument (agy, claude, or codex)")
            if val is None:
                return 1
            ai_cli = val
            ai_cli_from_flag = True
            i = next_i
        elif arg in ("-d", "--detach"):
            detach_mode = True
            i += 1
        elif arg in ("-s", "switch") and not launch_targets:
            action = "switch"
            i += 1
            break
        elif arg in ("-n", "new") and not launch_targets:
            action = "new"
            i += 1
            break
        elif arg in _PUBLIC_SUBCOMMANDS and not launch_targets:
            action = arg
            i += 1
            break
        elif arg.startswith("-"):
            print(f"Error: Unknown option '{arg}' (run 'ide --help' for usage).", file=sys.stderr)
            return 1
        else:
            launch_targets.append(arg)
            i += 1

    sub_args = args[i:]

    if not want_help:
        for s_arg in sub_args:
            if s_arg == "--":
                break
            if s_arg in ("-h", "--help"):
                want_help = True
                break

    if want_help:
        if action in SUBCOMMAND_USAGE:
            print(SUBCOMMAND_USAGE[action])
        else:
            usage(sys.stdout)
        return 0

    if len(launch_targets) > 1:
        print(f"Error: Unexpected extra argument '{launch_targets[1]}'.", file=sys.stderr)
        return 1

    if not _normalize_ai_cli(ai_cli, ai_cli_from_flag):
        return 1
    ai_cli = os.environ["IDE_AI_CLI"]

    if action == "keys":
        if sub_args:
            print(f"Error: Unknown 'ide keys' argument '{sub_args[0]}'.", file=sys.stderr)
            return 1
        os.execvp("bash", ["bash", ide_self, "keys"])

    if action == "monitor":
        if sub_args:
            print(f"Error: Unknown 'ide monitor' argument '{sub_args[0]}'.", file=sys.stderr)
            return 1
        os.execvp("bash", ["bash", ide_self, "monitor"])

    if action == "list":
        plain_list = False
        json_list = False
        for s_arg in sub_args:
            if s_arg == "--plain":
                plain_list = True
            elif s_arg == "--json":
                json_list = True
            else:
                print(f"Error: Unknown 'ide list' option '{s_arg}' (expected: --plain or --json).", file=sys.stderr)
                return 1
        if plain_list and json_list:
            print("Error: '--plain' and '--json' cannot be combined.", file=sys.stderr)
            return 1
        if not which_executable("tmux"):
            if json_list:
                print("[]")
                return 0
            if plain_list:
                return 0
            print("Error: 'tmux' is not installed. Run './setup.sh' to install core packages.", file=sys.stderr)
            return 1
        from ide_lib.sessions import list_ide_fleet

        return list_ide_fleet(plain=plain_list, json_output=json_list)

    if not which_executable("tmux"):
        print("Error: 'tmux' is not installed. Run './setup.sh' to install core packages.", file=sys.stderr)
        return 1

    if action in ("switch", "new"):
        target_arg = ""
        j = 0
        sub_end = False
        while j < len(sub_args):
            s_arg = sub_args[j]
            if sub_end:
                if target_arg:
                    print(f"Error: Unexpected extra argument '{s_arg}'.", file=sys.stderr)
                    return 1
                target_arg = s_arg
                j += 1
            elif s_arg == "--":
                sub_end = True
                j += 1
            elif s_arg == "--2pane":
                layout_mode = "2pane"
                j += 1
            elif s_arg == "--agent" or s_arg.startswith("--agent="):
                val, next_j = _extract_opt_value(sub_args, j, "--agent", "an argument (agy, claude, or codex)")
                if val is None or not _normalize_ai_cli(val, True):
                    return 1
                ai_cli = os.environ["IDE_AI_CLI"]
                ai_cli_from_flag = True
                j = next_j
            elif s_arg in ("-d", "--detach"):
                detach_mode = True
                j += 1
            elif s_arg.startswith("-"):
                print(f"Error: Unknown 'ide {action}' option '{s_arg}'.", file=sys.stderr)
                return 1
            else:
                if target_arg:
                    print(f"Error: Unexpected extra argument '{s_arg}'.", file=sys.stderr)
                    return 1
                target_arg = s_arg
                j += 1

        from ide_lib.sessions import run_new_workspace_picker, run_sessions_picker

        if action == "switch":
            return run_sessions_picker(
                target_arg,
                ide_self,
                had_env_ai_cli=had_env_ai_cli,
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
                detach_only=detach_mode,
            )
        return run_new_workspace_picker(
            target_arg,
            ide_self,
            layout_mode=layout_mode,
            ai_cli=ai_cli,
            ai_cli_from_flag=ai_cli_from_flag,
            had_env_ai_cli=had_env_ai_cli,
            detach_only=detach_mode,
        )

    if action == "next":
        if len(sub_args) > 1 or (sub_args and sub_args[0].startswith("-")):
            bad = sub_args[0] if sub_args and sub_args[0].startswith("-") else sub_args[1]
            print(f"Error: Unexpected 'ide next' argument '{bad}'.", file=sys.stderr)
            return 1
        from ide_lib.sessions import next_attention

        return next_attention(sub_args[0] if sub_args else "")

    if action == "cd":
        cd_pos: list[str] = []
        sub_end = False
        for s_arg in sub_args:
            if sub_end:
                cd_pos.append(s_arg)
            elif s_arg == "--":
                sub_end = True
            elif s_arg in ("--reset", "-"):
                cd_pos.append(s_arg)
            elif s_arg.startswith("-"):
                print(f"Error: Unknown 'ide cd' option '{s_arg}'.", file=sys.stderr)
                return 1
            else:
                cd_pos.append(s_arg)
        if len(cd_pos) > 2:
            print(f"Error: Unexpected extra argument '{cd_pos[2]}'.", file=sys.stderr)
            return 1
        cd_target = cd_pos[0] if cd_pos else safe_getcwd()
        cd_sess = cd_pos[1] if len(cd_pos) >= 2 else ""
        from ide_lib.layout import cd_ide_workspace

        return cd_ide_workspace(cd_target, cd_sess)

    if action == "refresh":
        pos = [a for a in sub_args if a != "--"]
        if any(a.startswith("-") for a in pos) or len(pos) > 1:
            bad = next((a for a in pos if a.startswith("-")), pos[1] if len(pos) > 1 else "")
            print(f"Error: Unexpected 'ide refresh' argument '{bad}'.", file=sys.stderr)
            return 1
        from ide_lib.layout import refresh_ide_sessions

        return refresh_ide_sessions(pos[0] if pos else "", ide_self)

    if action == "quit":
        force_quit = False
        quit_targets: list[str] = []
        sub_end = False
        for s_arg in sub_args:
            if sub_end:
                quit_targets.append(s_arg)
            elif s_arg == "--":
                sub_end = True
            elif s_arg in ("-f", "--force"):
                force_quit = True
            elif s_arg.startswith("-"):
                print(f"Error: Unknown 'ide quit' option '{s_arg}'.", file=sys.stderr)
                return 1
            else:
                quit_targets.append(s_arg)
        from ide_lib.layout import quit_ide

        return quit_ide(quit_targets, force_quit, force_quit)

    if action == "open":
        focus_open = True
        open_pos: list[str] = []
        sub_end = False
        for s_arg in sub_args:
            if sub_end:
                open_pos.append(s_arg)
            elif s_arg == "--":
                sub_end = True
            elif s_arg in ("-p", "--preview") and not open_pos:
                focus_open = False
            elif s_arg.startswith("-") and not (open_pos and _is_pos_line_arg(s_arg)):
                print(f"Error: Unknown 'ide open' option '{s_arg}'.", file=sys.stderr)
                return 1
            else:
                open_pos.append(s_arg)
        if not open_pos or not open_pos[0]:
            print("Error: 'ide open' requires a file path.", file=sys.stderr)
            return 1
        open_file = open_pos[0]
        open_line = ""
        open_sess = ""
        rest_open = open_pos[1:]
        if rest_open and _is_pos_line_arg(rest_open[0]):
            from ide_lib.tmux import session_exists

            cand_line = rest_open[0]
            if cand_line.startswith("+") or len(rest_open) >= 2 or not session_exists(cand_line):
                open_line = cand_line.lstrip("+")
                rest_open = rest_open[1:]
        if len(rest_open) > 1:
            print(f"Error: Unexpected extra argument '{rest_open[1]}'.", file=sys.stderr)
            return 1
        if rest_open:
            open_sess = rest_open[0]
        from ide_lib.links import open_in_editor

        return open_in_editor(open_file, focus_open, open_sess, open_line)

    if action == "send":
        send_mode = ""
        send_payload = ""
        send_no_focus = False
        send_switch = False
        send_pos: list[str] = []
        j = 0
        sub_end = False
        while j < len(sub_args):
            s_arg = sub_args[j]
            if sub_end:
                send_pos.append(s_arg)
                j += 1
            elif s_arg == "--":
                sub_end = True
                j += 1
            elif s_arg == "--stdin":
                send_mode = "stdin"
                j += 1
            elif s_arg == "--ref" or s_arg.startswith("--ref="):
                if "=" in s_arg:
                    send_payload = s_arg.split("=", 1)[1]
                    j += 1
                else:
                    if j + 1 >= len(sub_args):
                        print("Error: '--ref' requires a file path.", file=sys.stderr)
                        return 1
                    send_payload = sub_args[j + 1]
                    j += 2
                send_mode = "ref"
            elif s_arg == "--text" or s_arg.startswith("--text="):
                if "=" in s_arg:
                    send_payload = s_arg.split("=", 1)[1]
                    j += 1
                else:
                    if j + 1 >= len(sub_args):
                        print("Error: '--text' requires a text string.", file=sys.stderr)
                        return 1
                    send_payload = sub_args[j + 1]
                    j += 2
                send_mode = "text"
            elif s_arg == "--no-focus":
                send_no_focus = True
                send_switch = False
                j += 1
            elif s_arg == "--switch":
                send_switch = True
                send_no_focus = False
                j += 1
            elif s_arg.startswith("-"):
                print(f"Error: Unknown 'ide send' option '{s_arg}'.", file=sys.stderr)
                return 1
            else:
                send_pos.append(s_arg)
                j += 1
        if not send_mode and send_pos:
            send_mode = "text"
            send_payload = send_pos.pop(0)
        if len(send_pos) > 1:
            print(f"Error: Unexpected extra argument '{send_pos[1]}'.", file=sys.stderr)
            return 1
        send_sess = send_pos[0] if send_pos else ""
        from ide_lib.links import send_to_ai

        return send_to_ai(send_mode, send_payload, send_no_focus, send_switch, send_sess)

    if action == "state":
        agent_state_val = ""
        agent_message = ""
        agent_json_args: list[str] = []
        state_sess = ""
        j = 0
        sub_end = False
        while j < len(sub_args):
            s_arg = sub_args[j]
            if not sub_end and s_arg == "--":
                sub_end = True
                j += 1
            elif not sub_end and (s_arg in ("-m", "--message") or s_arg.startswith("--message=")):
                if "=" in s_arg:
                    agent_message = s_arg.split("=", 1)[1]
                    j += 1
                else:
                    if j + 1 >= len(sub_args):
                        print("Error: '--message' requires a text string.", file=sys.stderr)
                        return 1
                    agent_message = sub_args[j + 1]
                    j += 2
            elif not sub_end and s_arg.startswith("-"):
                print(f"Error: Unknown 'ide state' option '{s_arg}'.", file=sys.stderr)
                return 1
            elif not agent_state_val:
                agent_state_val = s_arg
                j += 1
            elif _looks_like_json_obj(s_arg):
                agent_json_args.append(s_arg)
                j += 1
            elif not state_sess:
                state_sess = s_arg
                j += 1
            else:
                print(f"Error: Unexpected extra argument '{s_arg}'.", file=sys.stderr)
                return 1
        if not agent_state_val:
            print("Error: 'ide state' requires a state (running, approval, quota, done, or idle).", file=sys.stderr)
            return 1
        from ide_lib.fleet import set_agent_state

        return set_agent_state(agent_state_val, state_sess, message=agent_message, json_args=agent_json_args)

    if action == "ack":
        ack_targets: list[str] = []
        sub_end = False
        for s_arg in sub_args:
            if sub_end:
                ack_targets.append(s_arg)
            elif s_arg == "--":
                sub_end = True
            elif s_arg.startswith("-"):
                print(f"Error: Unknown 'ide ack' option '{s_arg}'.", file=sys.stderr)
                return 1
            else:
                ack_targets.append(s_arg)
        from ide_lib.fleet import ack_ai_session

        return ack_ai_session(ack_targets or "", from_hook=False, refresh_always=True)

    if action == "pr":
        pr_pos = [a for a in sub_args if a != "--"]
        if any(a.startswith("-") for a in pr_pos) or len(pr_pos) > 1:
            bad = next((a for a in pr_pos if a.startswith("-")), pr_pos[1] if len(pr_pos) > 1 else "")
            print(f"Error: Unexpected 'ide pr' argument '{bad}'.", file=sys.stderr)
            return 1
        from ide_lib.fleet import open_session_pr

        return open_session_pr(pr_pos[0] if pr_pos else "")

    from ide_lib.layout import launch_or_attach_workspace
    from ide_lib.tmux import discover_display_env

    launch_target = launch_targets[0] if launch_targets else ""
    discover_display_env(launch_target, ignore_tmux_env=not bool(os.environ.get("TMUX")))
    return launch_or_attach_workspace(
        target_arg=launch_target,
        layout_mode=layout_mode,
        ai_cli_from_flag=ai_cli_from_flag,
        detach_mode=detach_mode,
    )
