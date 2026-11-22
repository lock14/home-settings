#!/bin/bash
# Master modular setup and dotfiles engine for home-settings.
# Supports Ubuntu 22.04+ / 24.04+ LTS, Fedora 38+ / 40+, and macOS (Apple Silicon & Intel).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
REPO_URL="https://github.com/lock14/home-settings.git"

# Self-bootstrapping: If piped through curl or run without repository assets, clone and re-exec
if [ ! -d "$SCRIPT_DIR/dotfiles" ] || [ ! -f "$SCRIPT_DIR/.mise.toml" ]; then
    TARGET_DIR="$HOME/home-settings"
    echo "====================================================="
    echo "       home-settings Master Setup & Provisioner      "
    echo "====================================================="

    if ! command -v git >/dev/null 2>&1; then
        echo "  Git not found. Installing git prerequisite..."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -y && sudo apt-get install -y git curl
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf -y install git curl
        elif command -v brew >/dev/null 2>&1; then
            brew install git curl
        else
            echo "Error: git is required to clone home-settings." >&2
            exit 1
        fi
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        echo "  Cloning repository to $TARGET_DIR..."
        git clone "$REPO_URL" "$TARGET_DIR"
    else
        echo "  Updating repository at $TARGET_DIR..."
        git -C "$TARGET_DIR" pull --rebase origin main || true
    fi

    chmod +x "$TARGET_DIR/setup.sh"
    exec "$TARGET_DIR/setup.sh" "$@"
fi

# Source shared helper libraries
# shellcheck source=/dev/null
. "$SCRIPT_DIR/setup/lib/log.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/setup/lib/os.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/setup/lib/symlink.sh"

# Default configurations
export ACTION="install"
export UNINSTALL_TARGETS=""
export IDE_NAME="none"
export IDE_NAMES=""
export TARGET_OS=""
export DRY_RUN=false
export DB_CHOICE="none"
export SKIP_DB=false

# Stage skip and opt-in feature flags
export SKIP_SYSTEM=false
export SKIP_PACKAGES=false
export INSTALL_CHROME=false
export INSTALL_APPS=false
export INSTALL_GHOSTTY=false
export SKIP_USER=false
export SKIP_DOTFILES=false
export SKIP_FONTS=false
export SKIP_TOOLS=false
export SKIP_NVIM=false
export SKIP_VIM=false
export SKIP_ZSH=false
export SKIP_BASH=false
export SKIP_BIN=false
export SKIP_COMPLETIONS=false
export SKIP_TERMINAL=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modular cross-platform workstation provisioner and dotfiles engine.

Workflows & Scope:
  (default)               Provision native OS packages and user environment
  --user                  Configure user dotfiles, MesloLGS Nerd Font Mono, and tools only (no sudo)
  --system-only           Provision native OS packages and system runtimes only
  --uninstall[=<target>]  Remove managed artifacts: all (default) or comma-separated
                          dotfiles,fonts,bin

Platform & Component Options:
  --os <distro>           Target OS override: ubuntu, fedora, or macos
  --db <engine,...>       Database server daemons to install: postgres, mariadb, all, or none
                          (default: none; client CLIs install unless 'db' is in --skip)
  --gui[=<app,...>]       Optional desktop apps: all (default: ghostty,chrome,code) or
                          comma-separated ghostty,chrome,code,intellij,intellij-ultimate,none
  --theme <name>          Initial color theme to apply (default: solarized-dark)
  --skip <stage,...>      Skip comma-separated provisioning stages:
                          packages,db,dotfiles,bin,fonts,tools,nvim,vim,zsh,bash,completions,terminal

Execution Options:
  -n, --dry-run           Preview actions without modifying the system
  -h, --help              Show this help message and exit
EOF
}

require_opt_arg() {
    local flag="$1"
    local val="${2:-}"
    local hint="$3"
    if [ -z "$val" ] || [[ "$val" == -* ]]; then
        echo "Error: $flag requires $hint" >&2
        exit 1
    fi
}

append_csv_unique() {
    local current="$1"
    local item="$2"
    case ",$current," in
        *,"$item",*) printf '%s' "$current" ;;
        ",,") printf '%s' "$item" ;;
        *) printf '%s' "$current,$item" ;;
    esac
}

parse_db_list() {
    local raw="$1" tok
    local -a items=()
    IFS=',' read -r -a items <<< "$raw"
    [ "${#items[@]}" -gt 0 ] || {
        echo "Error: --db requires at least one engine (postgres, mariadb, all, or none)" >&2
        exit 1
    }
    for tok in "${items[@]}"; do
        tok="${tok#"${tok%%[![:space:]]*}"}"
        tok="${tok%"${tok##*[![:space:]]}"}"
        case "$tok" in
            none)
                DB_CHOICE="none"
                ;;
            all)
                SKIP_DB=false
                DB_CHOICE="all"
                ;;
            postgres)
                SKIP_DB=false
                case "$DB_CHOICE" in
                    none|postgres) DB_CHOICE="postgres" ;;
                    *) DB_CHOICE="all" ;;
                esac
                ;;
            mariadb)
                SKIP_DB=false
                case "$DB_CHOICE" in
                    none|mariadb) DB_CHOICE="mariadb" ;;
                    *) DB_CHOICE="all" ;;
                esac
                ;;
            *)
                echo "Error: '$tok' is not a supported --db engine (expected: postgres, mariadb, all, or none)" >&2
                exit 1
                ;;
        esac
    done
}

parse_gui_list() {
    local raw="$1" tok
    local -a items=()
    IFS=',' read -r -a items <<< "$raw"
    [ "${#items[@]}" -gt 0 ] || {
        echo "Error: --gui requires an app list (all, none, ghostty, chrome, code, intellij, intellij-ultimate)" >&2
        exit 1
    }
    for tok in "${items[@]}"; do
        tok="${tok#"${tok%%[![:space:]]*}"}"
        tok="${tok%"${tok##*[![:space:]]}"}"
        case "$tok" in
            none)
                INSTALL_GHOSTTY=false
                INSTALL_CHROME=false
                INSTALL_APPS=false
                IDE_NAMES=""
                IDE_NAME="none"
                ;;
            all)
                INSTALL_GHOSTTY=true
                INSTALL_CHROME=true
                INSTALL_APPS=true
                if [ -z "$IDE_NAMES" ]; then
                    IDE_NAMES="code"
                    IDE_NAME="code"
                fi
                ;;
            ghostty)
                INSTALL_GHOSTTY=true
                ;;
            chrome)
                INSTALL_CHROME=true
                ;;
            code|intellij|intellij-ultimate)
                INSTALL_APPS=true
                IDE_NAMES="$(append_csv_unique "$IDE_NAMES" "$tok")"
                IDE_NAME="${IDE_NAMES%%,*}"
                ;;
            *)
                echo "Error: '$tok' is not a supported --gui app (expected: all, none, ghostty, chrome, code, intellij, intellij-ultimate)" >&2
                exit 1
                ;;
        esac
    done
}

parse_skip_list() {
    local raw="$1" tok
    local -a items=()
    IFS=',' read -r -a items <<< "$raw"
    [ "${#items[@]}" -gt 0 ] || {
        echo "Error: --skip requires one or more stage names" >&2
        exit 1
    }
    for tok in "${items[@]}"; do
        tok="${tok#"${tok%%[![:space:]]*}"}"
        tok="${tok%"${tok##*[![:space:]]}"}"
        case "$tok" in
            packages)    SKIP_PACKAGES=true ;;
            db)          SKIP_DB=true; DB_CHOICE="none" ;;
            dotfiles)    SKIP_DOTFILES=true ;;
            bin)         SKIP_BIN=true ;;
            fonts)       SKIP_FONTS=true ;;
            tools)       SKIP_TOOLS=true ;;
            nvim)        SKIP_NVIM=true ;;
            vim)         SKIP_VIM=true ;;
            zsh)         SKIP_ZSH=true ;;
            bash)        SKIP_BASH=true ;;
            completions) SKIP_COMPLETIONS=true ;;
            terminal)    SKIP_TERMINAL=true ;;
            *)
                echo "Error: Unknown --skip stage '$tok' (expected: packages, db, dotfiles, bin, fonts, tools, nvim, vim, zsh, bash, completions, terminal)" >&2
                exit 1
                ;;
        esac
    done
}

parse_uninstall_list() {
    local raw="$1" tok
    local -a items=()
    IFS=',' read -r -a items <<< "$raw"
    [ "${#items[@]}" -gt 0 ] || {
        echo "Error: --uninstall requires a target (all, dotfiles, fonts, or bin)" >&2
        exit 1
    }
    for tok in "${items[@]}"; do
        tok="${tok#"${tok%%[![:space:]]*}"}"
        tok="${tok%"${tok##*[![:space:]]}"}"
        case "$tok" in
            all)
                UNINSTALL_TARGETS="all"
                return 0
                ;;
            dotfiles|fonts|bin)
                if [ "$UNINSTALL_TARGETS" != "all" ]; then
                    UNINSTALL_TARGETS="$(append_csv_unique "$UNINSTALL_TARGETS" "$tok")"
                fi
                ;;
            *)
                echo "Error: Unknown --uninstall target '$tok' (expected: all, dotfiles, fonts, or bin)" >&2
                exit 1
                ;;
        esac
    done
}

# Parse CLI arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --user)
            SKIP_SYSTEM=true
            shift
            ;;
        --system-only)
            SKIP_USER=true
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            if [ $# -ge 2 ] && [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then
                parse_uninstall_list "$2"
                shift 2
            else
                UNINSTALL_TARGETS="all"
                shift
            fi
            ;;
        --uninstall=*)
            ACTION="uninstall"
            require_opt_arg "--uninstall" "${1#--uninstall=}" "a target (all, dotfiles, fonts, or bin)"
            parse_uninstall_list "${1#--uninstall=}"
            shift
            ;;
        --os)
            require_opt_arg "--os" "${2:-}" "a distro (ubuntu, fedora, or macos)"
            TARGET_OS="$2"
            shift 2
            ;;
        --os=*)
            require_opt_arg "--os" "${1#--os=}" "a distro (ubuntu, fedora, or macos)"
            TARGET_OS="${1#--os=}"
            shift
            ;;
        --db)
            require_opt_arg "--db" "${2:-}" "an engine (postgres, mariadb, all, or none)"
            parse_db_list "$2"
            shift 2
            ;;
        --db=*)
            require_opt_arg "--db" "${1#--db=}" "an engine (postgres, mariadb, all, or none)"
            parse_db_list "${1#--db=}"
            shift
            ;;
        --gui)
            if [ $# -ge 2 ] && [ -n "${2:-}" ] && [[ "${2:-}" != -* ]]; then
                parse_gui_list "$2"
                shift 2
            else
                parse_gui_list "all"
                shift
            fi
            ;;
        --gui=*)
            require_opt_arg "--gui" "${1#--gui=}" "an app list (all, none, ghostty, chrome, code, intellij, intellij-ultimate)"
            parse_gui_list "${1#--gui=}"
            shift
            ;;
        --theme)
            require_opt_arg "--theme" "${2:-}" "a theme name (such as solarized-dark, catppuccin-mocha, nord)"
            export HOME_SETTINGS_THEME="$2"
            shift 2
            ;;
        --theme=*)
            require_opt_arg "--theme" "${1#--theme=}" "a theme name (such as solarized-dark, catppuccin-mocha, nord)"
            export HOME_SETTINGS_THEME="${1#--theme=}"
            shift
            ;;
        --skip)
            require_opt_arg "--skip" "${2:-}" "comma-separated stages (packages, db, dotfiles, bin, fonts, tools, nvim, vim, zsh, bash, completions, terminal)"
            parse_skip_list "$2"
            shift 2
            ;;
        --skip=*)
            require_opt_arg "--skip" "${1#--skip=}" "comma-separated stages (packages, db, dotfiles, bin, fonts, tools, nvim, vim, zsh, bash, completions, terminal)"
            parse_skip_list "${1#--skip=}"
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1' (run '$(basename "$0") --help' for usage)." >&2
            exit 1
            ;;
    esac
done

OS="$(detect_os)"
export OS
case "$OS" in
    ubuntu|fedora|macos) ;;
    *)
        echo "Error: Unsupported or unrecognized distribution: '$OS'. Please specify --os ubuntu, --os fedora, or --os macos." >&2
        exit 1
        ;;
esac

ARCH="$(detect_arch)"
export ARCH

# Handle uninstallation actions
if [ "$ACTION" = "uninstall" ]; then
    "$SCRIPT_DIR/setup/modules/99-uninstall.sh" "${UNINSTALL_TARGETS:-all}"
    exit 0
fi

# Validate Color Theme (if explicitly specified via --theme or HOME_SETTINGS_THEME)
if [ -n "${HOME_SETTINGS_THEME:-}" ]; then
    if [[ "$HOME_SETTINGS_THEME" == -* ]]; then
        echo "Error: Invalid theme name '$HOME_SETTINGS_THEME'" >&2
        exit 1
    fi
    if [ -x "$SCRIPT_DIR/bin/theme" ] && ! "$SCRIPT_DIR/bin/theme" --dry-run --no-live --set="$HOME_SETTINGS_THEME" >/dev/null; then
        exit 1
    fi
fi

echo "====================================================="
echo "       Home-Settings Cross-Platform Setup            "
echo "====================================================="
echo "Target OS : $OS"
echo "Arch      : $ARCH"
echo "IDE Choice: ${IDE_NAMES:-none}"
echo "Database  : Server: $DB_CHOICE (Clients: $([ "$SKIP_DB" = true ] && echo "skipped" || echo "enabled"))"
[ -n "${HOME_SETTINGS_THEME:-}" ] && echo "Theme     : $HOME_SETTINGS_THEME"
[ "$DRY_RUN" = true ] && echo "Mode      : DRY RUN (preview only, no modifications)"
echo "====================================================="

export ELAN_HOME="${ELAN_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/elan}"
prepend_path "$HOME/.local/bin"

# 1. System Provisioning (OS packages, Database, Chrome, Apps)
if [ "$SKIP_SYSTEM" = false ]; then
    echo -e "\n[1/2] Running System-Level Provisioning..."
    "$SCRIPT_DIR/setup/modules/00-packages.sh"
else
    echo -e "\n[1/2] Skipping System-Level Provisioning."
fi

# 2. User-Level Configuration (Dotfiles, Fonts, Tools, Shell, Terminal)
if [ "$SKIP_USER" = false ]; then
    echo -e "\n[2/2] Running User Dotfiles & Environment Setup..."
    [ "$SKIP_DOTFILES" = false ] && "$SCRIPT_DIR/setup/modules/10-dotfiles.sh"
    [ "$SKIP_BIN" = false ] && "$SCRIPT_DIR/setup/modules/20-bin.sh"
    [ "$SKIP_FONTS" = false ] && "$SCRIPT_DIR/setup/modules/30-fonts.sh"
    [ "$SKIP_TOOLS" = false ] && "$SCRIPT_DIR/setup/modules/40-mise.sh"

    # Expose Mise shims and Elan toolchain binaries on PATH for Neovim sync and shell completions
    prepend_path "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" "$ELAN_HOME/bin"

    [ "$SKIP_NVIM" = false ] && "$SCRIPT_DIR/setup/modules/50-nvim.sh"
    "$SCRIPT_DIR/setup/modules/60-shell.sh"
    [ "$SKIP_TERMINAL" = false ] && "$SCRIPT_DIR/setup/modules/70-terminal.sh"
fi

echo -e "\n====================================================="
echo " Setup complete! Restart your shell or run: exec zsh "
echo "====================================================="
