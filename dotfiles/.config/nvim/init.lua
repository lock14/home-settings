-- =============================================================
-- Modern Modular Neovim Configuration (init.lua)
-- Developer Workstation Orchestrator (Linux, macOS, Windows)
-- =============================================================

-- Resolve init.lua's physical config directory and ensure it is on runtimepath BEFORE requiring
-- `solarized.*` modules so `-u $REPO/dotfiles/.config/nvim/init.lua` works even when XDG_CONFIG_HOME
-- has not been symlinked yet (e.g., fresh headless test sandboxes or standalone invocations).
local uv = vim.uv or vim.loop
local init_source = debug.getinfo(1, "S").source
local init_path = (init_source and init_source:sub(1, 1) == "@")
    and init_source:sub(2)
    or (vim.fn.stdpath("config") .. "/init.lua")
local init_real = (uv and uv.fs_realpath and uv.fs_realpath(init_path)) or init_path
local init_dir = vim.fn.fnamemodify(init_path, ":p:h")
local real_config_dir = vim.fn.fnamemodify(init_real, ":p:h")
local config_dir = (uv and uv.fs_stat(init_dir .. "/lua/solarized")) and init_dir or real_config_dir
local repo_root = vim.fn.fnamemodify(init_real, ":h:h:h:h")

local rtp_entries = vim.opt.rtp:get()
if not vim.tbl_contains(rtp_entries, config_dir) then
    vim.opt.rtp:prepend(config_dir)
end
local after_dir = config_dir .. "/after"
if uv and uv.fs_stat(after_dir) and not vim.tbl_contains(rtp_entries, after_dir) then
    vim.opt.rtp:append(after_dir)
end

-- Allow `:source $MYVIMRC` to pick up edits to local orchestrator submodules without evicting
-- maxmx03/solarized.nvim's own `solarized`, `solarized.palette`, or `solarized.highlights` modules.
for _, mod in ipairs({
    "options",
    "autocmds",
    "links",
    "keymaps",
    "ide",
    "images",
    "theme_groups",
    "theme",
    "treesitter",
    "lsp",
    "plugins",
}) do
    package.loaded["solarized." .. mod] = nil
end

local ctx = {
    config_dir = config_dir,
    repo_root = repo_root,
}

require("solarized.options").setup()

local ide = require("solarized.ide")
ide.setup()

local links = require("solarized.links")
links.setup({ ide_job = ide.ide_job })

local autocmds = require("solarized.autocmds")
autocmds.setup({ follow_editor_link = links.follow_editor_link })

require("solarized.keymaps").setup({
    follow_editor_link = links.follow_editor_link,
    recover_stale_cwd = autocmds.recover_stale_cwd,
})

local theme = require("solarized.theme")
theme.setup(ctx)

require("solarized.plugins").setup(ctx, theme)
