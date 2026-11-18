#!/bin/bash
# Stage 50: Reconcile headless Neovim plugins against lazy-lock.json.
# Note: Never connects to or hot-reloads live Neovim server sockets; runs isolated with -i NONE.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MODULE_DIR/.." && pwd)"

# shellcheck source=/dev/null
. "$REPO_DIR/lib/log.sh"
# shellcheck source=/dev/null
. "$REPO_DIR/lib/os.sh"

DRY_RUN="${DRY_RUN:-false}"
LOCKFILE="$REPO_DIR/dotfiles/.config/nvim/lazy-lock.json"
INIT_LUA="$REPO_DIR/dotfiles/.config/nvim/init.lua"

echo "  Synchronizing Neovim plugins with lazy-lock.json..."

if [ "$DRY_RUN" = true ]; then
    echo "  [DryRun] Syncing Neovim plugins from lazy-lock.json"
    exit 0
fi

if [ ! -f "$LOCKFILE" ] || [ ! -f "$INIT_LUA" ]; then
    exit 0
fi

prepend_existing_paths "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"

run_bounded() {
    local secs="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    else
        "$@"
    fi
}

if ! command -v nvim >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "  Notice: nvim or git not found on PATH; skipping headless plugin sync."
    exit 0
fi

if ! NVIM_LOG_FILE=/dev/null run_bounded 15 nvim --headless -u NONE -i NONE \
    -c 'if !has("nvim-0.10") | cquit 1 | endif' \
    -c 'qall!' </dev/null >/dev/null 2>&1; then
    echo "  Notice: Neovim < 0.10 detected; skipping headless plugin sync."
    exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat <<'EOF' > "$tmp_dir/check.lua"
local uv = vim.uv or vim.loop
local lock_path = vim.env.HS_LOCKFILE or ""

local function read_file(path)
    local fd = uv.fs_open(path, "r", 438)
    if not fd then
        return nil
    end
    local st = uv.fs_fstat(fd)
    local data = (st and st.size and st.size > 0 and st.size <= 262144) and uv.fs_read(fd, st.size, 0) or nil
    uv.fs_close(fd)
    return data
end

local function is_dir_entry(parent, name, ftype)
    if ftype == "directory" then
        return true
    end
    if ftype == nil or ftype == "link" then
        local st = uv.fs_stat(parent .. "/" .. name)
        return st ~= nil and st.type == "directory"
    end
    return false
end

local function resolve_head_sha(git_dir)
    local head = vim.trim(read_file(git_dir .. "/HEAD") or "")
    if head == "" then
        return nil
    end
    local sym = head:match("^ref:%s*(.+)$")
    if not sym then
        return head:match("^%x+$") and head or nil
    end
    local loose = vim.trim(read_file(git_dir .. "/" .. sym) or "")
    if loose ~= "" and loose:match("^%x+$") then
        return loose
    end
    local packed = read_file(git_dir .. "/packed-refs") or ""
    for line in packed:gmatch("[^\r\n]+") do
        local sha, ref = line:match("^(%x+)%s+(.+)$")
        if sha and ref == sym then
            return sha
        end
    end
    return nil
end

local raw_lock = read_file(lock_path)
local ok, lock = pcall(vim.json.decode, raw_lock or "")
if not ok or type(lock) ~= "table" then
    io.stderr:write("Failed to decode lazy-lock.json\n")
    vim.cmd("cquit 1")
end

local nvim_data = vim.fn.stdpath("data")
local lazy_dir = nvim_data .. "/lazy"
local lazy_sha = (lock["lazy.nvim"] and lock["lazy.nvim"].commit) or ""
local synced = true

local data_scan = uv.fs_scandir(nvim_data)
if data_scan then
    while true do
        local name = uv.fs_scandir_next(data_scan)
        if not name then
            break
        end
        if name:find("^tree%-sitter%-") then
            synced = false
            break
        end
    end
end

local lazy_scan = synced and uv.fs_scandir(lazy_dir) or nil
if not lazy_scan then
    synced = false
else
    local seen = {}
    while true do
        local name, ftype = uv.fs_scandir_next(lazy_scan)
        if not name then
            break
        end
        if name:sub(-8) == ".cloning" then
            synced = false
            break
        end
        if is_dir_entry(lazy_dir, name, ftype) then
            if not lock[name] then
                synced = false
                break
            end
            seen[name] = true
        end
    end
    if synced then
        for name, spec in pairs(lock) do
            if not seen[name] or type(spec) ~= "table" or type(spec.commit) ~= "string" then
                synced = false
                break
            end
            local git_dir = lazy_dir .. "/" .. name .. "/.git"
            local git_st = uv.fs_stat(git_dir)
            if not (git_st and git_st.type == "directory") then
                synced = false
                break
            end
            if uv.fs_stat(git_dir .. "/reftable") then
                synced = false
                break
            end
            local cfg = read_file(git_dir .. "/config") or ""
            if cfg:find("refs/heads/.invalid", 1, true) then
                synced = false
                break
            end
            if resolve_head_sha(git_dir) ~= spec.commit then
                synced = false
                break
            end
            if name == "nvim-treesitter" then
                local origin_head = read_file(git_dir .. "/refs/remotes/origin/HEAD") or ""
                if origin_head:find("refs/remotes/origin/master", 1, true) then
                    synced = false
                    break
                end
            end
        end
    end
end

io.write(string.format("SYNCED=%s\nLAZY_SHA=%s\nNVIM_DATA=%s\n", tostring(synced), lazy_sha, nvim_data))
EOF

probe_out="$(
    HS_LOCKFILE="$LOCKFILE" \
    HS_CHECK_LUA="$tmp_dir/check.lua" \
    NVIM_LOG_FILE=/dev/null \
        run_bounded 30 nvim --headless -u NONE -i NONE \
        -c 'lua local ok, err = pcall(dofile, vim.env.HS_CHECK_LUA); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit 1") end' \
        -c 'qall!' </dev/null
)"

synced="false"
lazy_sha=""
nvim_data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
while IFS='=' read -r k v; do
    case "$k" in
        SYNCED) synced="$v" ;;
        LAZY_SHA) lazy_sha="$v" ;;
        NVIM_DATA) [ -n "$v" ] && nvim_data="$v" ;;
    esac
done <<< "$probe_out"

if [ "$synced" = "true" ]; then
    echo "  Neovim plugins already match lazy-lock.json."
    exit 0
fi

lazy_dir="$nvim_data/lazy"
mkdir -p "$lazy_dir"

# Remove leftover temporary grammar directories created by legacy nvim-treesitter checkouts
for ts_tmp in "$nvim_data"/tree-sitter-*; do
    [ -e "$ts_tmp" ] || continue
    rm -rf "$ts_tmp"
done

# Migrate any existing Git reftable plugin clones to files refstorage before lazy.nvim reads .git/HEAD
for repo in "$lazy_dir"/*; do
    [ -d "$repo/.git" ] || continue
    if [ -d "$repo/.git/reftable" ]; then
        if ! GIT_DEFAULT_REF_FORMAT=files git -C "$repo" refs migrate --ref-format=files; then
            echo "  Warning: git refs migrate failed for $(basename "$repo"); removing for clean re-clone." >&2
            rm -rf "$repo"
            continue
        fi
    fi
    if [ -f "$repo/.git/config" ] && grep -Fq 'refs/heads/.invalid' "$repo/.git/config"; then
        git -C "$repo" config --unset-all remote.origin.fetch 'refs/heads/\.invalid' || true
    fi
done

# Pin lazy.nvim itself before launching Neovim so obsolete pre-existing lazy.nvim checkouts never execute
if [ -n "$lazy_sha" ]; then
    if [ ! -d "$lazy_dir/lazy.nvim/.git" ]; then
        rm -rf "$lazy_dir/lazy.nvim"
        retry_cmd 2 1 env GIT_DEFAULT_REF_FORMAT=files git clone --filter=blob:none https://github.com/folke/lazy.nvim.git "$lazy_dir/lazy.nvim"
    fi
    cur_lazy_sha="$(git -C "$lazy_dir/lazy.nvim" rev-parse HEAD 2>/dev/null || true)"
    if [ "$cur_lazy_sha" != "$lazy_sha" ]; then
        if ! git -C "$lazy_dir/lazy.nvim" cat-file -e "${lazy_sha}^{commit}" 2>/dev/null; then
            retry_cmd 2 1 env GIT_DEFAULT_REF_FORMAT=files git -C "$lazy_dir/lazy.nvim" fetch --tags --force origin
        fi
        git -C "$lazy_dir/lazy.nvim" checkout --force "$lazy_sha" >/dev/null
    fi
fi

# Run restore followed by clean against an ephemeral copy of lazy-lock.json so the tracked file stays read-only
cp -f "$LOCKFILE" "$tmp_dir/lazy-lock.json"
cat <<'EOF' > "$tmp_dir/sync.lua"
local ok, lazy = pcall(require, "lazy")
if not ok then
    io.stderr:write("Failed to load lazy.nvim\n")
    vim.cmd("cquit 1")
end
lazy.restore({ wait = true, show = false })
lazy.clean({ wait = true, show = false })
local Config = require("lazy.core.config")
local Plugin = require("lazy.core.plugin")
local errs = {}
for name, plugin in pairs(Config.plugins or {}) do
    if Plugin.has_errors(plugin) then
        for _, task in ipairs((plugin._ and plugin._.tasks) or {}) do
            if task:has_errors() then
                table.insert(errs, name .. " (" .. tostring(task.name) .. "): " .. tostring(task:output(vim.log.levels.ERROR)))
            end
        end
    end
end
if #errs > 0 then
    io.stderr:write("Neovim plugin sync failed:\n" .. table.concat(errs, "\n") .. "\n")
    vim.cmd("cquit 1")
end
EOF

NVIM_LAZY_LOCKFILE="$tmp_dir/lazy-lock.json" \
NVIM_TS_SKIP_AUTO_INSTALL=1 \
NVIM_LOG_FILE=/dev/null \
GIT_DEFAULT_REF_FORMAT=files \
HS_NVIM_SYNC_LUA="$tmp_dir/sync.lua" \
    run_bounded 180 nvim --headless -i NONE -u "$INIT_LUA" \
    -c 'lua local ok, err = pcall(dofile, vim.env.HS_NVIM_SYNC_LUA); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit 1") end' \
    -c 'qall!' </dev/null >/dev/null

if [ -d "$lazy_dir/nvim-treesitter/.git" ] && \
   [ -f "$lazy_dir/nvim-treesitter/.git/refs/remotes/origin/HEAD" ] && \
   grep -Fq 'refs/remotes/origin/master' "$lazy_dir/nvim-treesitter/.git/refs/remotes/origin/HEAD"; then
    git -C "$lazy_dir/nvim-treesitter" remote set-head origin main || true
fi
