"""CLI argument parser and lazy subcommand dispatcher for `bin/ide`."""

from __future__ import annotations

import os
import sys

from ide_lib.constants import safe_getcwd, usage, which_executable


def _is_pos_line_arg(raw: str) -> bool:
    s = raw[1:] if raw.startswith("+") else raw
    return bool(s) and s[0] != "0" and s.isdigit()


_SINGLE_ARG_ACTIONS = frozenset({
    "--toggle",
    "--show-editor",
    "--focus-editor",
    "--focus-ai",
    "--focus-term",
    "--show-ai",
    "--show-term",
    "--toggle-editor",
    "--toggle-ai",
    "--toggle-term",
    "--next-attention",
    "--refresh-attn",
    "--heal-socket",
    "--run-ai-popup",
    "--paste",
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


def main(argv: list[str] | None = None) -> int:
    """Parse CLI arguments and dispatch to the matching `ide_lib` domain handler."""
    raw_self = os.environ.pop("IDE_SELF", "")
    ide_self = (
        os.path.abspath(raw_self)
        if raw_self
        else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "ide"))
    )
    _calibrate_ide_path()
    os.environ["FORCE_HYPERLINK"] = "1"
    args = sys.argv[1:] if argv is None else list(argv)

    if not which_executable("tmux"):
        if "--list" in args and "--plain" in args:
            return 0
        if not any(a in ("-h", "--help", "--keys", "--help-keys", "--monitor", "--top", "--btop") for a in args):
            print("Error: 'tmux' is not installed. Run './setup.sh' to install core packages.", file=sys.stderr)
            return 1

    layout_mode = "3pane"
    action = "launch"
    detach_mode = os.environ.get("IDE_NO_ATTACH", "0") == "1"
    force_quit = False
    plain_list = False
    had_env_ai_cli = bool((os.environ.get("IDE_AI_CLI") or "").strip())
    ai_cli = os.environ.get("IDE_AI_CLI") or "agy"
    ai_cli_from_flag = False
    target_arg = ""
    target_args: list[str] = []
    open_file = ""
    open_line = ""
    cd_target = ""
    swap_dir = ""
    status_click_x = ""
    link_href = ""
    link_word = ""
    link_cwd = ""
    send_mode = ""
    send_payload = ""
    send_no_focus = False
    send_switch = False
    agent_state_val = ""
    agent_message = ""
    agent_json_args: list[str] = []
    ack_from_hook = False
    preview_follow = False
    switcher_op = ""
    end_of_opts = False

    i = 0
    n = len(args)
    while i < n:
        arg = args[i]
        if end_of_opts:
            if action == "send" and not send_mode:
                send_mode = "text"
                send_payload = arg
            elif action == "agent-state" and _looks_like_json_obj(arg):
                agent_json_args.append(arg)
            else:
                target_arg = arg
                target_args.append(arg)
            i += 1
        elif arg == "--":
            end_of_opts = True
            i += 1
        elif arg == "--2pane":
            layout_mode = "2pane"
            i += 1
        elif arg == "--3pane":
            layout_mode = "3pane"
            i += 1
        elif arg in ("--ai", "--agent"):
            if i + 1 >= n or args[i + 1].startswith("-"):
                print(f"Error: '{arg}' requires an argument (agy, claude, or codex).", file=sys.stderr)
                return 1
            ai_cli = args[i + 1]
            ai_cli_from_flag = True
            i += 2
        elif arg.startswith(("--ai=", "--agent=")):
            ai_cli = arg.split("=", 1)[1]
            ai_cli_from_flag = True
            i += 1
        elif arg in ("--open", "--preview") or arg.startswith(("--open=", "--preview=")):
            if "=" in arg:
                opt_flag, open_file = arg.split("=", 1)
                action = "open" if opt_flag == "--open" else "preview"
                if not open_file:
                    print(f"Error: '{opt_flag}' requires a file path.", file=sys.stderr)
                    return 1
                next_idx = i + 1
            else:
                action = "open" if arg == "--open" else "preview"
                if i + 1 >= n:
                    print(f"Error: '{arg}' requires a file path.", file=sys.stderr)
                    return 1
                open_file = args[i + 1]
                next_idx = i + 2
            if next_idx < n and _is_pos_line_arg(args[next_idx]):
                from ide_lib.tmux import session_exists

                cand_line = args[next_idx]
                if cand_line.startswith("+") or next_idx + 1 < n or not session_exists(cand_line):
                    open_line = cand_line.lstrip("+")
                    next_idx += 1
            i = next_idx
        elif arg == "--cd" or (arg == "cd" and action == "launch"):
            action = "cd"
            if i + 1 < n:
                cd_target = args[i + 1]
                i += 2
            else:
                cd_target = safe_getcwd()
                i += 1
        elif arg in ("-s", "--sessions"):
            action = "sessions"
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                i += 2
            else:
                i += 1
        elif arg in ("-n", "--new"):
            action = "new"
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                i += 2
            else:
                i += 1
        elif arg == "--sessions-lines":
            action = "sessions-lines"
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                i += 2
            else:
                i += 1
        elif arg == "--follow":
            preview_follow = True
            i += 1
        elif arg == "--session-preview":
            action = "session-preview"
            j = i + 1
            while j < n and args[j] == "--follow":
                preview_follow = True
                j += 1
            if j < n and args[j] == "--":
                j += 1
            if j >= n:
                print("Error: '--session-preview' requires a session name.", file=sys.stderr)
                return 1
            target_arg = args[j]
            i = j + 1
        elif arg.startswith("--session-preview="):
            action = "session-preview"
            target_arg = arg.split("=", 1)[1]
            if not target_arg:
                print("Error: '--session-preview' requires a session name.", file=sys.stderr)
                return 1
            i += 1
        elif arg == "--switcher-op":
            action = "switcher-op"
            if i + 2 >= n:
                print("Error: '--switcher-op' requires an operation and switcher session.", file=sys.stderr)
                return 1
            switcher_op = args[i + 1]
            target_arg = args[i + 2]
            i += 3
        elif arg == "--agent-state":
            action = "agent-state"
            if i + 1 >= n or args[i + 1].startswith("-"):
                print("Error: '--agent-state' requires a state (running, approval, quota, done, or idle).", file=sys.stderr)
                return 1
            agent_state_val = args[i + 1]
            if i + 2 < n and not args[i + 2].startswith("-"):
                cand = args[i + 2]
                if _looks_like_json_obj(cand):
                    agent_json_args.append(cand)
                else:
                    target_arg = cand
                    target_args.append(cand)
                i += 3
            else:
                i += 2
        elif arg.startswith("--agent-state="):
            action = "agent-state"
            agent_state_val = arg.split("=", 1)[1]
            if not agent_state_val:
                print("Error: '--agent-state' requires a state (running, approval, quota, done, or idle).", file=sys.stderr)
                return 1
            if i + 1 < n and not args[i + 1].startswith("-"):
                cand = args[i + 1]
                if _looks_like_json_obj(cand):
                    agent_json_args.append(cand)
                else:
                    target_arg = cand
                    target_args.append(cand)
                i += 2
            else:
                i += 1
        elif arg == "--message":
            if i + 1 >= n:
                print("Error: '--message' requires a text string.", file=sys.stderr)
                return 1
            agent_message = args[i + 1]
            i += 2
        elif arg.startswith("--message="):
            agent_message = arg.split("=", 1)[1]
            i += 1
        elif arg == "--hook":
            ack_from_hook = True
            i += 1
        elif arg == "--ack-ai":
            action = "ack-ai"
            i += 1
        elif arg == "--open-pr":
            action = "open-pr"
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                target_args.append(args[i + 1])
                i += 2
            else:
                i += 1
        elif arg.startswith("--open-pr="):
            action = "open-pr"
            target_arg = arg.split("=", 1)[1]
            if target_arg:
                target_args.append(target_arg)
            i += 1
        elif arg == "--send":
            action = "send"
            i += 1
        elif arg == "--stdin":
            action = "send"
            send_mode = "stdin"
            i += 1
        elif arg == "--ref":
            if i + 1 >= n:
                print("Error: '--ref' requires a file path.", file=sys.stderr)
                return 1
            action = "send"
            send_mode = "ref"
            send_payload = args[i + 1]
            i += 2
        elif arg.startswith("--ref="):
            action = "send"
            send_mode = "ref"
            send_payload = arg.split("=", 1)[1]
            i += 1
        elif arg == "--text":
            if i + 1 >= n:
                print("Error: '--text' requires a text string.", file=sys.stderr)
                return 1
            action = "send"
            send_mode = "text"
            send_payload = args[i + 1]
            i += 2
        elif arg.startswith("--text="):
            action = "send"
            send_mode = "text"
            send_payload = arg.split("=", 1)[1]
            i += 1
        elif arg == "--no-focus":
            send_no_focus = True
            send_switch = False
            i += 1
        elif arg == "--switch":
            send_switch = True
            send_no_focus = False
            i += 1
        elif arg in _SINGLE_ARG_ACTIONS:
            action = arg[2:]
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                target_args.append(args[i + 1])
                i += 2
            else:
                i += 1
        elif arg in ("-r", "--refresh", "--reload") or (arg == "refresh" and action == "launch"):
            action = "refresh"
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                target_args.append(args[i + 1])
                i += 2
            else:
                i += 1
        elif arg == "--kill" or (arg == "kill" and action == "launch"):
            action = "kill"
            i += 1
        elif arg in ("-q", "--quit") or (arg == "quit" and action == "launch"):
            action = "quit"
            i += 1
        elif arg == "--swap":
            action = "swap"
            if i + 1 >= n or args[i + 1].startswith("-"):
                print("Error: '--swap' requires a direction (left, down, up, or right).", file=sys.stderr)
                return 1
            swap_dir = args[i + 1]
            if i + 2 < n and not args[i + 2].startswith("-"):
                target_arg = args[i + 2]
                i += 3
            else:
                i += 2
        elif arg.startswith("--swap="):
            action = "swap"
            swap_dir = arg.split("=", 1)[1]
            if not swap_dir:
                print("Error: '--swap' requires a direction (left, down, up, or right).", file=sys.stderr)
                return 1
            if i + 1 < n and not args[i + 1].startswith("-"):
                target_arg = args[i + 1]
                i += 2
            else:
                i += 1
        elif arg in ("--keys", "--help-keys"):
            action = "keys"
            i += 1
        elif arg in ("--monitor", "--top", "--btop"):
            action = "monitor"
            i += 1
        elif arg == "--status-click":
            action = "status-click"
            status_click_x = args[i + 1] if i + 1 < n else "0"
            target_arg = args[i + 2] if i + 2 < n else ""
            i += 3 if i + 2 < n else (2 if i + 1 < n else 1)
        elif arg == "--copy":
            action = "copy"
            i += 1
        elif arg == "--open-link":
            action = "open-link"
            rem = args[i + 1:]
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
                    i += 5
                else:
                    i += 4
            elif len(rem) >= 2 and os.path.isdir(rem[1]):
                link_href, link_word, link_cwd = "", rem[0], rem[1]
                if len(rem) >= 3:
                    target_arg = rem[2]
                    i += 4
                else:
                    i += 3
            elif len(rem) >= 1 and os.path.isdir(rem[0]):
                link_href, link_word, link_cwd = "", "", rem[0]
                if len(rem) >= 2:
                    target_arg = rem[1]
                    i += 3
                else:
                    i += 2
            else:
                link_href = rem[0] if len(rem) >= 1 else ""
                link_word = rem[1] if len(rem) >= 2 else ""
                link_cwd = rem[2] if len(rem) >= 3 else ""
                if len(rem) >= 4:
                    target_arg = rem[3]
                    i += 5
                else:
                    i += 1 + min(len(rem), 3)
        elif arg in ("-f", "--force"):
            force_quit = True
            i += 1
        elif arg == "--detach":
            detach_mode = True
            i += 1
        elif arg == "--list":
            action = "list"
            i += 1
        elif arg == "--plain":
            plain_list = True
            if action == "launch":
                action = "list"
            i += 1
        elif arg in ("-h", "--help"):
            usage(sys.stdout)
            return 0
        elif arg.startswith("-"):
            print(f"Error: Unknown option '{arg}'", file=sys.stderr)
            usage(sys.stderr)
            return 1
        else:
            if action == "send" and not send_mode:
                send_mode = "text"
                send_payload = arg
            elif action == "agent-state" and _looks_like_json_obj(arg):
                agent_json_args.append(arg)
            else:
                target_arg = arg
                target_args.append(arg)
            i += 1

    if preview_follow and action != "session-preview":
        print("Error: '--follow' can only be used with '--session-preview'.", file=sys.stderr)
        return 1

    if not _normalize_ai_cli(ai_cli, ai_cli_from_flag):
        return 1
    ai_cli = os.environ["IDE_AI_CLI"]

    if action == "keys":
        os.execvp("bash", ["bash", ide_self, "--keys"])
    if action == "monitor":
        os.execvp("bash", ["bash", ide_self, "--monitor"])

    if action in ("agent-state", "ack-ai", "open-pr", "refresh-attn"):
        from ide_lib.fleet import (
            ack_ai_session,
            open_session_pr,
            refresh_fleet_topbar,
            set_agent_state,
        )

        if action == "agent-state":
            return set_agent_state(agent_state_val, target_arg, message=agent_message, json_args=agent_json_args)
        if action == "ack-ai":
            return ack_ai_session(
                target_args or target_arg,
                from_hook=ack_from_hook,
                refresh_always=not ack_from_hook,
            )
        if action == "open-pr":
            return open_session_pr(target_arg)
        return refresh_fleet_topbar()

    if action == "list" and plain_list:
        from ide_lib.fleet import classify_ide_fleet
        from ide_lib.tmux import current_ide_session

        for entry in classify_ide_fleet(include_git=False, cur_sess=current_ide_session()):
            print(str(entry["sess"]))
        return 0

    if action == "session-preview":
        from ide_lib.preview import render_session_preview

        return render_session_preview(target_arg, follow=preview_follow)

    if action == "switcher-op":
        from ide_lib.switcher import handle_switcher_op

        return handle_switcher_op(switcher_op, target_arg)

    if action in ("sessions", "new", "sessions-lines", "next-attention", "list"):
        from ide_lib.sessions import (
            build_sessions_lines,
            list_ide_fleet,
            next_attention,
            run_new_workspace_picker,
            run_sessions_picker,
        )

        if action == "sessions":
            return run_sessions_picker(
                target_arg,
                ide_self,
                had_env_ai_cli=had_env_ai_cli,
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
                detach_only=detach_mode,
            )
        if action == "new":
            return run_new_workspace_picker(
                target_arg,
                ide_self,
                layout_mode=layout_mode,
                ai_cli=ai_cli,
                ai_cli_from_flag=ai_cli_from_flag,
                had_env_ai_cli=had_env_ai_cli,
                detach_only=detach_mode,
            )
        if action == "sessions-lines":
            for row in build_sessions_lines(target_arg):
                print(row)
            return 0
        if action == "next-attention":
            return next_attention(target_arg)
        return list_ide_fleet(plain=plain_list)

    if action == "send":
        from ide_lib.links import send_to_ai

        return send_to_ai(send_mode, send_payload, send_no_focus, send_switch, target_arg)

    if action == "heal-socket":
        from ide_lib.nvim_rpc import heal_target_session_socket

        return heal_target_session_socket(target_arg)

    from ide_lib.tmux import (
        copy_to_system_clipboard,
        discover_display_env,
        paste_from_system_clipboard,
        set_allow_tmux_env_fallback,
    )

    if action in ("copy", "paste"):
        set_allow_tmux_env_fallback(True)

    if action in ("copy", "paste"):
        discover_display_env(target_arg)
    elif action == "launch":
        discover_display_env(target_arg, ignore_tmux_env=not bool(os.environ.get("TMUX")))

    if action == "copy":
        copy_to_system_clipboard(target_arg)
        return 0
    if action == "paste":
        paste_from_system_clipboard(target_arg)
        return 0
    if action in ("open-link", "open", "preview"):
        from ide_lib.links import open_ide_link, open_in_editor

        if action == "open-link":
            return open_ide_link(link_href, link_word, link_cwd, target_arg)
        return open_in_editor(open_file, action == "open", target_arg, open_line)

    from ide_lib.layout import (
        cd_ide_workspace,
        launch_or_attach_workspace,
        quit_ide,
        refresh_ide_sessions,
        run_ai_popup,
        status_click,
        swap_ide_pane,
        toggle_main_pane,
    )

    if action == "status-click":
        return status_click(status_click_x, target_arg)
    if action == "refresh":
        return refresh_ide_sessions(target_arg, ide_self)
    if action == "cd":
        return cd_ide_workspace(cd_target, target_arg)
    if action == "toggle":
        return toggle_main_pane("toggle", target_arg)
    if action == "show-editor":
        return toggle_main_pane("editor", target_arg)
    if action in ("focus-editor", "focus-ai", "focus-term"):
        return toggle_main_pane(action, target_arg, skip_checktime=(os.environ.get("IDE_SKIP_CHECKTIME") == "1"))
    if action == "show-ai":
        return toggle_main_pane("ai", target_arg)
    if action == "show-term":
        return toggle_main_pane("term", target_arg)
    if action in ("toggle-editor", "toggle-ai", "toggle-term"):
        return toggle_main_pane(action, target_arg)
    if action == "swap":
        return swap_ide_pane(swap_dir, target_arg)
    if action == "run-ai-popup":
        run_ai_popup(target_arg)
        return 0
    if action == "quit":
        return quit_ide(target_args, force_quit, False)
    if action == "kill":
        return quit_ide(target_args, True, True)

    return launch_or_attach_workspace(
        target_arg=target_arg,
        layout_mode=layout_mode,
        ai_cli_from_flag=ai_cli_from_flag,
        detach_mode=detach_mode,
    )
