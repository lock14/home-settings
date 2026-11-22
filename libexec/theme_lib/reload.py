"""Theme state materialization, backup-safe symlinking, and live RPC reload dispatch."""

from __future__ import annotations

import getpass
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time

from theme_lib.generators import (
    build_fzf_color_opts,
    generate_active_theme_file_text,
    generate_btop_config_text,
    generate_btop_theme_text,
    generate_ghostty_config_text,
    generate_ghostty_theme_text,
    generate_git_config_text,
    generate_p10k_theme_text,
    generate_tealdeer_config_text,
    generate_theme_env_sh,
    generate_tmtheme_text,
    generate_tmux_theme_text,
    generate_zsh_theme_text,
)
from theme_lib.palette import (
    ansi_palette_hex_list,
    get_xdg_config_home,
)
from theme_lib.sync import sync_managed_repo_assets


def sync_symlink(src_path: Path, dst_path: Path) -> None:
    """Atomically link dst_path to src_path, backing up any physical target first."""
    dst_path.parent.mkdir(parents=True, exist_ok=True)
    if dst_path.is_symlink():
        dst_path.unlink()
    elif dst_path.exists():
        ts = int(time.time())
        bak = dst_path.parent / f"{dst_path.name}.bak.{ts}"
        idx = 1
        while bak.exists() or bak.is_symlink():
            bak = dst_path.parent / f"{dst_path.name}.bak.{ts}.{idx}"
            idx += 1
        dst_path.rename(bak)
    dst_path.symlink_to(src_path)


def emit_live_osc_sequences(theme: dict[str, str]) -> None:
    """Emit live OSC 10, 11, 12, and OSC 4 palette escape sequences to active TTY."""
    if not (sys.stdout.isatty() or os.environ.get("THEME_FORCE_OSC") == "1"):
        return
    if os.environ.get("NO_COLOR"):
        return
    term_lc = (os.environ.get("TERM") or "").strip().lower()
    if term_lc in ("dumb", "linux"):
        return
    in_tmux = bool(os.environ.get("TMUX"))
    seqs = [
        f"\033]10;{theme['BASE0']}\007",
        f"\033]11;{theme['BASE03']}\007",
        f"\033]12;{theme['BASE0']}\007",
    ]
    for idx, col in enumerate(ansi_palette_hex_list(theme)):
        seqs.append(f"\033]4;{idx};{col}\007")

    out = []
    for s in seqs:
        if in_tmux:
            escaped = s.replace("\033", "\033\033")
            out.append(f"\033Ptmux;{escaped}\033\\")
        else:
            out.append(s)
    try:
        sys.stdout.write("".join(out))
        sys.stdout.flush()
    except OSError:
        pass


def discover_nvim_sockets() -> list[Path]:
    """Discover live Neovim RPC sockets while strictly honoring THEME_NVIM_SOCKET_DIR isolation."""
    sockets: list[Path] = []
    sock_dir_override = os.environ.get("THEME_NVIM_SOCKET_DIR", "").strip()
    if sock_dir_override:
        sock_dir_path = Path(sock_dir_override)
        if sock_dir_path.is_dir():
            for pat in ("*.sock", "nvim.*.0", "*/nvim.*.0"):
                for p in sock_dir_path.glob(pat):
                    if p not in sockets:
                        sockets.append(p)
        return sockets

    env_sock = os.environ.get("NVIM_IDE_SOCKET", "").strip()
    if env_sock:
        sockets.append(Path(env_sock))
    for p in Path("/tmp").glob("nvim-ide-*.sock"):
        if p not in sockets:
            sockets.append(p)
    xdg_rt = os.environ.get("XDG_RUNTIME_DIR", "").strip()
    if xdg_rt and Path(xdg_rt).is_dir():
        for pat in ("nvim-ide-*.sock", "nvim.*.0", "*/nvim.*.0"):
            for p in Path(xdg_rt).glob(pat):
                if p not in sockets:
                    sockets.append(p)
    try:
        nvim_user = os.environ.get("USER", "").strip() or getpass.getuser()
    except Exception:
        nvim_user = ""
    if nvim_user:
        tmp_candidates = [Path("/tmp")]
        env_tmp = os.environ.get("TMPDIR", "").strip()
        if env_tmp:
            env_tmp_path = Path(env_tmp)
            if env_tmp_path not in tmp_candidates:
                tmp_candidates.insert(0, env_tmp_path)
        for base_tmp in tmp_candidates:
            user_nvim_dir = base_tmp / f"nvim.{nvim_user}"
            if user_nvim_dir.is_dir():
                for pat in ("nvim.*.0", "*/nvim.*.0"):
                    for p in user_nvim_dir.glob(pat):
                        if p not in sockets:
                            sockets.append(p)
    return sockets


def _try_nvim_socket_theme_reload(sock: Path, timeout: float = 1.5) -> bool:
    """Evaluate `v:lua.apply_home_settings_theme()` directly over `AF_UNIX` MsgPack-RPC."""
    import socket
    import struct

    expr_b = b"v:lua.apply_home_settings_theme()"
    req = (
        b"\x94\x00\x01\xa9nvim_eval\x91"
        + struct.pack(">BB", 0xD9, len(expr_b))
        + expr_b
    )
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(timeout)
            client.connect(str(sock))
            client.sendall(req)
            resp = client.recv(4096)
            return bool(resp) and resp[0] == 0x94 and resp[1] == 0x01
    except OSError:
        return False


def broadcast_live_reloads(theme: dict[str, str], state_dir: Path, repo_dir: Path) -> None:
    """Broadcast active palette updates to TTY OSC, Tmux, Neovim RPC, and OS terminals."""
    emit_live_osc_sequences(theme)

    # 1. Live Tmux reload when inside tmux or when THEME_LIVE_TMUX / TMUX_TMPDIR is active
    tmux_conf = state_dir / "tmux-theme.conf"
    if shutil.which("tmux") and tmux_conf.is_file():
        if os.environ.get("TMUX") or os.environ.get("TMUX_TMPDIR") or os.environ.get("THEME_LIVE_TMUX") == "1":
            subprocess.run(
                ["tmux", "source-file", str(tmux_conf)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            fzf_str = build_fzf_color_opts(theme, include_layout=True)
            for k, v in (
                ("HOME_SETTINGS_THEME", theme["THEME_ID"]),
                ("HOME_SETTINGS_THEME_MODE", theme["THEME_MODE"]),
                ("BAT_THEME", theme["BAT_THEME_NAME"]),
                ("FZF_DEFAULT_OPTS", fzf_str),
            ):
                subprocess.run(
                    ["tmux", "set-environment", "-g", k, v],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )

    # 2. Live Neovim RPC reload across active IDE and standalone server sockets
    if shutil.which("nvim") and os.environ.get("THEME_LIVE_NVIM", "1") != "0":
        skip_sock = os.environ.get("THEME_SKIP_NVIM_SOCKET", "").strip()
        skip_resolved = Path(skip_sock).resolve() if skip_sock else None
        uid = os.getuid()
        for sock in discover_nvim_sockets():
            try:
                if skip_resolved and sock.resolve() == skip_resolved:
                    continue
                st = sock.stat()
                if stat.S_ISSOCK(st.st_mode) and st.st_uid == uid:
                    if _try_nvim_socket_theme_reload(sock):
                        continue
                    nvim_rpc_env = os.environ.copy()
                    nvim_rpc_env.setdefault("NVIM_LOG_FILE", "/dev/null")
                    subprocess.run(
                        [
                            "nvim",
                            "--headless",
                            "--server",
                            str(sock),
                            "--remote-expr",
                            "v:lua.apply_home_settings_theme()",
                        ],
                        env=nvim_rpc_env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=3,
                        check=False,
                    )
            except (OSError, subprocess.SubprocessError):
                pass

    # 3. Terminal emulator profile updates (Ghostty SIGUSR2, GNOME Terminal, macOS Terminal.app)
    if os.environ.get("THEME_UPDATE_TERMINAL_PROFILE", "1") != "0":
        if shutil.which("pkill"):
            uid_str = str(os.getuid())
            for proc_name in ("ghostty", "Ghostty"):
                subprocess.run(
                    ["pkill", "-USR2", "-u", uid_str, "-x", proc_name],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
        is_macos = sys.platform == "darwin" or os.environ.get("OS") == "macos"
        if is_macos:
            mt_script = repo_dir / "bin" / "macos-terminal-solarized"
            if mt_script.is_file():
                subprocess.run(
                    [str(mt_script), f"--theme={theme['THEME_ID']}"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
        else:
            gt_script = repo_dir / "bin" / "gnome-terminal-solarized"
            if gt_script.is_file() and shutil.which("dconf") and shutil.which("gsettings"):
                subprocess.run(
                    [str(gt_script), f"--theme={theme['THEME_ID']}"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )


def _materialize_themed_app_dir(
    *,
    theme: dict[str, str],
    repo_app_dir: Path,
    active_app_dir: Path,
    xdg_app_dir: Path,
    config_filename: str,
    config_content: str,
    theme_filename: str | None = None,
    theme_content: str | None = None,
) -> None:
    """Materialize an active XDG app config directory without dirtying tracked repo dotfiles."""
    active_app_dir.mkdir(parents=True, exist_ok=True)
    if theme_filename is not None and theme_content is not None:
        active_themes = active_app_dir / "themes"
        active_themes.mkdir(parents=True, exist_ok=True)
        repo_themes = repo_app_dir / "themes"
        if repo_themes.is_dir():
            for item in repo_themes.iterdir():
                if item.is_file():
                    sync_symlink(item, active_themes / item.name)
        custom_theme_path = active_themes / theme_filename
        if theme["SOURCE"] == "user" or not (repo_themes / theme_filename).is_file():
            if custom_theme_path.is_symlink():
                custom_theme_path.unlink()
            custom_theme_path.write_text(theme_content, encoding="utf-8")

    (active_app_dir / config_filename).write_text(config_content, encoding="utf-8")
    if theme["THEME_ID"] == "solarized-dark" and repo_app_dir.is_dir():
        sync_symlink(repo_app_dir, xdg_app_dir)
    else:
        sync_symlink(active_app_dir, xdg_app_dir)


def _sync_bat_themes(theme: dict[str, str], repo_dir: Path, bat_themes_dir: Path) -> None:
    """Ensure bat .tmTheme files are linked or generated and rebuild bat cache when stale."""
    bat_themes_dir.mkdir(parents=True, exist_ok=True)
    bat_theme_file = bat_themes_dir / f"{theme['BAT_THEME_NAME']}.tmTheme"
    need_rebuild = False
    colors_dir = repo_dir / "colors"

    if colors_dir.is_dir():
        for tm_src in sorted(colors_dir.glob("*.tmTheme")):
            dst_tm = bat_themes_dir / tm_src.name
            if not dst_tm.exists():
                sync_symlink(tm_src, dst_tm)
                need_rebuild = True

    repo_tm = colors_dir / f"{theme['BAT_THEME_NAME']}.tmTheme"
    if repo_tm.is_file() and theme["SOURCE"] != "user":
        if not bat_theme_file.exists():
            sync_symlink(repo_tm, bat_theme_file)
            need_rebuild = True
    else:
        base_tm = (colors_dir / "Solarized-Dark-TrueColor.tmTheme").read_text(encoding="utf-8")
        if bat_theme_file.is_symlink():
            bat_theme_file.unlink()
        bat_theme_file.write_text(generate_tmtheme_text(base_tm, theme), encoding="utf-8")
        need_rebuild = True

    cache_root = Path(os.environ.get("XDG_CACHE_HOME", str(Path(os.environ.get("HOME", str(Path.home()))) / ".cache")))
    bat_cache_bin = cache_root / "bat" / "themes.bin"
    if not bat_cache_bin.is_file():
        need_rebuild = True
    else:
        try:
            cache_mtime = bat_cache_bin.stat().st_mtime
            for tm_item in bat_themes_dir.glob("*.tmTheme"):
                if tm_item.exists() and tm_item.stat().st_mtime > cache_mtime:
                    need_rebuild = True
                    break
        except OSError:
            need_rebuild = True

    if need_rebuild:
        bat_exe = shutil.which("bat") or shutil.which("batcat")
        if bat_exe:
            subprocess.run(
                [bat_exe, "cache", "--build"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )


def apply_theme(
    theme: dict[str, str],
    repo_dir: Path,
    dry_run: bool = False,
    no_live: bool = False,
) -> int:
    """Write theme state, materialize XDG configs, update bat cache, and broadcast reloads."""
    cfg_dir = get_xdg_config_home()
    state_dir = cfg_dir / "home-settings"
    active_dir = state_dir / "active"
    bat_themes_dir = cfg_dir / "bat" / "themes"
    bat_theme_file = bat_themes_dir / f"{theme['BAT_THEME_NAME']}.tmTheme"

    if dry_run:
        print(
            f"[DRY-RUN] Theme: {theme['THEME_LABEL']} "
            f"({theme['THEME_ID']}, mode={theme['THEME_MODE']}, source={theme['SOURCE']})"
        )
        print(f"[DRY-RUN] Would write active state: {state_dir / 'theme'}")
        print(f"[DRY-RUN] Would write active palette: {state_dir / 'active-theme.theme'}")
        print(f"[DRY-RUN] Would write shell environment: {state_dir / 'theme-env.sh'}")
        print(
            f"[DRY-RUN] Would write Zsh & p10k theme: "
            f"{state_dir / 'zsh-theme.zsh'}, {state_dir / 'p10k-theme.zsh'}"
        )
        print(f"[DRY-RUN] Would write Tmux theme: {state_dir / 'tmux-theme.conf'}")
        print(
            f"[DRY-RUN] Would update Ghostty config ({theme['GHOSTTY_THEME_NAME']}): "
            f"{cfg_dir / 'ghostty' / 'config'}"
        )
        print(
            f"[DRY-RUN] Would update btop config ({theme['BTOP_THEME_NAME']}): "
            f"{cfg_dir / 'btop' / 'btop.conf'}"
        )
        print(
            f"[DRY-RUN] Would update Git delta config ({theme['BAT_THEME_NAME']}): "
            f"{cfg_dir / 'git' / 'config'}"
        )
        print(f"[DRY-RUN] Would update tealdeer config: {cfg_dir / 'tealdeer' / 'config.toml'}")
        print(f"[DRY-RUN] Would ensure bat theme: {bat_theme_file}")
        print("[DRY-RUN] Would broadcast live reload to Tmux, Neovim RPC, and terminal OSC palette")
        return 0

    state_dir.mkdir(parents=True, exist_ok=True)
    active_dir.mkdir(parents=True, exist_ok=True)

    git_cfg_text = generate_git_config_text(theme)
    (state_dir / "theme").write_text(f"{theme['THEME_ID']}\n", encoding="utf-8")
    (state_dir / "active-theme.theme").write_text(generate_active_theme_file_text(theme), encoding="utf-8")
    (state_dir / "theme-env.sh").write_text(generate_theme_env_sh(theme, repo_dir), encoding="utf-8")
    (state_dir / "zsh-theme.zsh").write_text(generate_zsh_theme_text(theme), encoding="utf-8")
    (state_dir / "p10k-theme.zsh").write_text(generate_p10k_theme_text(theme), encoding="utf-8")
    (state_dir / "tmux-theme.conf").write_text(generate_tmux_theme_text(theme), encoding="utf-8")
    (state_dir / "delta-theme.gitconfig").write_text(git_cfg_text, encoding="utf-8")

    # 1. Ghostty
    _materialize_themed_app_dir(
        theme=theme,
        repo_app_dir=repo_dir / "dotfiles" / ".config" / "ghostty",
        active_app_dir=active_dir / "ghostty",
        xdg_app_dir=cfg_dir / "ghostty",
        config_filename="config",
        config_content=generate_ghostty_config_text(theme),
        theme_filename=theme["GHOSTTY_THEME_NAME"],
        theme_content=generate_ghostty_theme_text(theme),
    )
    if sys.platform == "darwin" or os.environ.get("OS") == "macos":
        home_dir = Path(os.environ.get("HOME", str(Path.home())))
        macos_gt_dir = home_dir / "Library" / "Application Support" / "com.mitchellh.ghostty"
        macos_gt_dir.mkdir(parents=True, exist_ok=True)
        sync_symlink(cfg_dir / "ghostty" / "config", macos_gt_dir / "config")
        sync_symlink(cfg_dir / "ghostty" / "themes", macos_gt_dir / "themes")

    # 2. btop
    _materialize_themed_app_dir(
        theme=theme,
        repo_app_dir=repo_dir / "dotfiles" / ".config" / "btop",
        active_app_dir=active_dir / "btop",
        xdg_app_dir=cfg_dir / "btop",
        config_filename="btop.conf",
        config_content=generate_btop_config_text(theme, repo_dir),
        theme_filename=f"{theme['BTOP_THEME_NAME']}.theme",
        theme_content=generate_btop_theme_text(theme),
    )

    # 3. git / delta (keep cfg_dir / "git" as a physical directory so user ignore and attributes survive)
    active_git = active_dir / "git"
    active_git.mkdir(parents=True, exist_ok=True)
    (active_git / "config").write_text(git_cfg_text, encoding="utf-8")
    git_cfg_dir = cfg_dir / "git"
    if git_cfg_dir.is_symlink():
        git_cfg_dir.unlink()
    git_cfg_dir.mkdir(parents=True, exist_ok=True)
    repo_git_cfg = repo_dir / "dotfiles" / ".config" / "git" / "config"
    if theme["THEME_ID"] == "solarized-dark" and repo_git_cfg.is_file():
        sync_symlink(repo_git_cfg, git_cfg_dir / "config")
    else:
        sync_symlink(active_git / "config", git_cfg_dir / "config")

    # 4. tealdeer
    _materialize_themed_app_dir(
        theme=theme,
        repo_app_dir=repo_dir / "dotfiles" / ".config" / "tealdeer",
        active_app_dir=active_dir / "tealdeer",
        xdg_app_dir=cfg_dir / "tealdeer",
        config_filename="config.toml",
        config_content=generate_tealdeer_config_text(theme),
    )

    # 5. bat .tmTheme and cache
    _sync_bat_themes(theme, repo_dir, bat_themes_dir)

    if not no_live:
        broadcast_live_reloads(theme, state_dir, repo_dir)

    print(f"Applied theme: {theme['THEME_LABEL']} ({theme['THEME_ID']})")
    return 0
