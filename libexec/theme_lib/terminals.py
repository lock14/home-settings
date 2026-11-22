"""Terminal emulator profile writers for GNOME Terminal (dconf) and macOS Terminal.app."""

from __future__ import annotations

import ast
import copy
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

from theme_lib.palette import ansi_palette_hex_list, resolve_single_theme

MACOS_ANSI_PLIST_KEYS: tuple[str, ...] = (
    "ANSIBlackColor",
    "ANSIRedColor",
    "ANSIGreenColor",
    "ANSIYellowColor",
    "ANSIBlueColor",
    "ANSIMagentaColor",
    "ANSICyanColor",
    "ANSIWhiteColor",
    "ANSIBrightBlackColor",
    "ANSIBrightRedColor",
    "ANSIBrightGreenColor",
    "ANSIBrightYellowColor",
    "ANSIBrightBlueColor",
    "ANSIBrightMagentaColor",
    "ANSIBrightCyanColor",
    "ANSIBrightWhiteColor",
)


def gvariant_quote(text: str) -> str:
    """Encode an arbitrary Unicode string as a GVariant double-quoted literal."""
    out = ['"']
    for ch in text:
        cp = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif 0x20 <= cp <= 0x7E:
            out.append(ch)
        elif cp <= 0xFFFF:
            out.append(f"\\u{cp:04x}")
        else:
            out.append(f"\\U{cp:08x}")
    out.append('"')
    return "".join(out)


def format_gnome_palette_gvariant(theme: dict[str, str]) -> str:
    """Format the 16-color terminal ANSI palette as a GVariant string array."""
    quoted = ", ".join(f"'{col}'" for col in ansi_palette_hex_list(theme))
    return f"[{quoted}]"


def merge_gnome_profile_list(
    raw_list: str,
    legacy_uuid: str,
    factory_uuid: str,
    profile_uuid: str,
) -> str:
    """Remove obsolete profile UUIDs and ensure profile_uuid is present in dconf list."""
    try:
        parsed = ast.literal_eval(raw_list.strip()) if raw_list.strip() else []
        parsed_list = parsed if isinstance(parsed, list) else []
    except Exception:
        parsed_list = []

    filtered = [u for u in parsed_list if u not in (legacy_uuid, factory_uuid)]
    if profile_uuid not in filtered:
        filtered.append(profile_uuid)
    return repr(filtered)


def run_gnome_helper_cli(argv: list[str]) -> int:
    """CLI entrypoint invoked by bin/gnome-terminal-solarized."""
    if not argv:
        sys.stderr.write("Error: missing gnome-terminal helper action\n")
        return 1
    action = argv[0]
    if action == "resolve":
        repo_dir = Path(argv[1])
        raw_name = argv[2] if len(argv) > 2 else ""
        try:
            theme = resolve_single_theme(repo_dir, raw_name)
        except ValueError as err:
            sys.stderr.write(f"Error: {err}\n")
            return 1
        label = theme["THEME_LABEL"]
        fields = [
            label,
            gvariant_quote(label),
            theme["BASE03"],
            theme["BASE02"],
            theme["BASE0"],
            theme["BASE1"],
            format_gnome_palette_gvariant(theme),
        ]
        sys.stdout.write("\0".join(fields) + "\0")
        return 0
    if action == "merge-list":
        val, legacy_uuid, factory_uuid, profile_uuid = argv[1:5]
        print(merge_gnome_profile_list(val, legacy_uuid, factory_uuid, profile_uuid))
        return 0
    sys.stderr.write(f"Error: unknown gnome-terminal helper action '{action}'\n")
    return 1


def apply_macos_osascript(theme: dict[str, str]) -> int:
    """Update a running macOS Terminal.app instance via AppleScript."""
    def _rgb16(key: str) -> str:
        h = theme[key].lstrip("#")
        return f"{{{int(h[0:2], 16) * 257}, {int(h[2:4], 16) * 257}, {int(h[4:6], 16) * 257}}}"

    label = theme["THEME_LABEL"]
    esc_name = label.replace("\\", "\\\\").replace('"', '\\"')
    script = f'''tell application "Terminal"
    try
        set font name of settings set "{esc_name}" to "MesloLGSNFM-Regular"
        set font size of settings set "{esc_name}" to 12
        set font antialiasing of settings set "{esc_name}" to true
        set background color of settings set "{esc_name}" to {_rgb16("BASE03")}
        set normal text color of settings set "{esc_name}" to {_rgb16("BASE0")}
        set bold text color of settings set "{esc_name}" to {_rgb16("BASE1")}
        set cursor color of settings set "{esc_name}" to {_rgb16("BASE0")}
        set default settings to settings set "{esc_name}"
        set startup settings to settings set "{esc_name}"
    end try
end tell'''
    res = subprocess.run(
        ["osascript", "-e", script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return 0 if res.returncode == 0 else 1


def apply_macos_terminal_plist(
    theme: dict[str, str],
    plist_path: Path,
    template_path: Path,
) -> None:
    """Write 22 sRGB NSColor entries into com.apple.Terminal.plist preserving existing profiles."""
    with open(template_path, "rb") as fh:
        theme_dict = plistlib.load(fh)

    srgb_archive_template = plistlib.loads(theme_dict["TextColor"])

    def _encode_nscolor(hex_str: str) -> bytes:
        h = hex_str.lstrip("#")
        rf = int(h[0:2], 16) / 255.0
        gf = int(h[2:4], 16) / 255.0
        bf = int(h[4:6], 16) / 255.0
        arc = copy.deepcopy(srgb_archive_template)
        arc["$objects"][1]["NSComponents"] = f"{rf:.10g} {gf:.10g} {bf:.10g} 1".encode("ascii")
        arc["$objects"][1]["NSRGB"] = f"{rf:.10g} {gf:.10g} {bf:.10g}\x00".encode("ascii")
        return plistlib.dumps(arc, fmt=plistlib.FMT_BINARY)

    for legacy_key in [k for k in list(theme_dict.keys()) if k.endswith("Colour")]:
        del theme_dict[legacy_key]

    color_map: dict[str, str] = {
        "BackgroundColor": theme["BASE03"],
        "TextColor": theme["BASE0"],
        "TextBoldColor": theme["BASE1"],
        "CursorColor": theme["BASE0"],
        "CursorTextColor": theme["BASE03"],
        "SelectionColor": theme["BASE02"],
    }
    for plist_key, hex_val in zip(MACOS_ANSI_PLIST_KEYS, ansi_palette_hex_list(theme)):
        color_map[plist_key] = hex_val

    for plist_key, hex_val in color_map.items():
        theme_dict[plist_key] = _encode_nscolor(hex_val)

    label = theme["THEME_LABEL"]
    theme_dict["name"] = label
    theme_dict["useOptionAsMetaKey"] = True

    prefs: dict[str, object] = {}
    loaded_from_cfprefsd = False
    if shutil.which("defaults"):
        try:
            exp = subprocess.run(
                ["defaults", "export", "com.apple.Terminal", "-"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            if exp.returncode == 0 and exp.stdout:
                exp_dict = plistlib.loads(exp.stdout)
                if isinstance(exp_dict, dict) and exp_dict:
                    prefs = exp_dict
                    loaded_from_cfprefsd = True
        except Exception:
            prefs = {}

    if not loaded_from_cfprefsd and plist_path.exists():
        try:
            with open(plist_path, "rb") as fh:
                disk_dict = plistlib.load(fh)
                if isinstance(disk_dict, dict):
                    prefs = disk_dict
        except Exception:
            prefs = {}

    win_settings = prefs.get("Window Settings")
    if not isinstance(win_settings, dict):
        win_settings = {}
        prefs["Window Settings"] = win_settings

    win_settings[label] = theme_dict
    prefs["Default Window Settings"] = label
    prefs["Startup Window Settings"] = label

    plist_path.parent.mkdir(parents=True, exist_ok=True)
    with open(plist_path, "wb") as fh:
        plistlib.dump(prefs, fh, fmt=plistlib.FMT_BINARY)


def run_macos_helper_cli(argv: list[str]) -> int:
    """CLI entrypoint invoked by bin/macos-terminal-solarized."""
    if len(argv) < 5:
        sys.stderr.write("Error: insufficient arguments for macos-terminal helper\n")
        return 1
    mode_arg = argv[0]
    repo_dir = Path(argv[1])
    raw_name = argv[2]
    plist_path = Path(argv[3])
    template_path = Path(argv[4])

    try:
        theme = resolve_single_theme(repo_dir, raw_name)
    except ValueError as err:
        sys.stderr.write(f"Error: {err}\n")
        return 1

    if mode_arg == "validate":
        print(theme["THEME_LABEL"])
        return 0
    if mode_arg == "osascript":
        return apply_macos_osascript(theme)
    if mode_arg == "apply":
        try:
            apply_macos_terminal_plist(theme, plist_path, template_path)
        except Exception as exc:
            sys.stderr.write(f"Error updating Terminal preferences: {exc}\n")
            return 1
        return 0
    sys.stderr.write(f"Error: unknown macos-terminal helper action '{mode_arg}'\n")
    return 1
