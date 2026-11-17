-- Native Neovim 0.11+ LSP configuration, Mise/Mason PATH calibration, tsserver discovery,
-- capability scrubbing, and non-blocking Mason UI notifications.

local M = {}

M.ensure_installed = {
    "clangd",
    "rust_analyzer",
    "gopls",
    "lua_ls",
    "terraformls",
    "jdtls",
}

M.servers = {
    "clangd",
    "rust_analyzer",
    "gopls",
    "pyright",
    "ts_ls",
    "lua_ls",
    "bashls",
    "terraformls",
    "yamlls",
    "jsonls",
    "leanls",
}

local server_bins = {
    clangd = "clangd",
    rust_analyzer = "rust-analyzer",
    gopls = "gopls",
    pyright = "pyright-langserver",
    ts_ls = "typescript-language-server",
    lua_ls = "lua-language-server",
    bashls = "bash-language-server",
    terraformls = "terraform-ls",
    yamlls = "yaml-language-server",
    jsonls = "vscode-json-language-server",
    leanls = "lake",
}

local function nonempty_env(name)
    local v = vim.env[name]
    return (v and v ~= "") and v:gsub("/+$", "") or nil
end

local function setup_lsp_attach()
    vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if client then
                -- Keep Tree-sitter as the single source of truth for token colors
                client.server_capabilities.semanticTokensProvider = nil
                -- Suppress clickable OSC 8 hyperlink extmarks on URLs in code/configs
                client.server_capabilities.documentLinkProvider = nil
            end

            local bufmap = function(keys, func, desc)
                vim.keymap.set("n", keys, func, { buffer = ev.buf, desc = "LSP: " .. desc })
            end
            bufmap("gd", vim.lsp.buf.definition, "Goto Definition")
            bufmap("gr", vim.lsp.buf.references, "Goto References")
            bufmap("K", vim.lsp.buf.hover, "Hover Documentation")
            bufmap("<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
            bufmap("<leader>ca", vim.lsp.buf.code_action, "Code Action")
            bufmap("<leader>d", vim.diagnostic.open_float, "Line Diagnostics")
        end,
    })
end

local function calibrate_toolchain_path()
    local uv = vim.uv or vim.loop
    local home_dir = nonempty_env("HOME") or vim.fn.expand("~"):gsub("/+$", "")
    local mise_data_dir = nonempty_env("MISE_DATA_DIR")
        or ((nonempty_env("XDG_DATA_HOME") or (home_dir .. "/.local/share")) .. "/mise")
    local mason_bin_dir = (vim.fn.stdpath("data"):gsub("/+$", "")) .. "/mason/bin"
    local mise_shims_dir = mise_data_dir .. "/shims"
    local mise_installs_pfx = mise_data_dir .. "/installs/"

    local entries, had_shims, last_mise_idx = {}, false, 0
    for p in (vim.env.PATH or ""):gmatch("[^:]+") do
        local clean_p = (p ~= "/") and p:gsub("/+$", "") or p
        if clean_p == mise_shims_dir then
            had_shims = true
        elseif clean_p ~= mason_bin_dir then
            entries[#entries + 1] = p
            if clean_p:find("/mise/installs/", 1, true) or clean_p:find(mise_installs_pfx, 1, true) then
                last_mise_idx = #entries
            end
        end
    end

    local sys_dirs = {
        ["/opt/homebrew/bin"] = true,
        ["/opt/homebrew/sbin"] = true,
        ["/usr/local/sbin"] = true,
        ["/usr/local/bin"] = true,
        ["/usr/sbin"] = true,
        ["/usr/bin"] = true,
        ["/sbin"] = true,
        ["/bin"] = true,
    }
    local insert_idx = #entries + 1
    for i = last_mise_idx + 1, #entries do
        local clean_p = (entries[i] ~= "/") and entries[i]:gsub("/+$", "") or entries[i]
        if sys_dirs[clean_p] then
            insert_idx = i
            break
        end
    end
    local shims_st = uv.fs_stat(mise_shims_dir)
    if had_shims or (shims_st and shims_st.type == "directory") then
        table.insert(entries, insert_idx, mise_shims_dir)
        insert_idx = insert_idx + 1
    end
    table.insert(entries, insert_idx, mason_bin_dir)
    vim.env.PATH = table.concat(entries, ":")

    return mise_data_dir, mason_bin_dir
end

local function resolve_tsserver_fallback(mise_data_dir)
    local uv = vim.uv or vim.loop
    local npm_ts_dir = mise_data_dir .. "/installs/npm-typescript"
    local rels = { "/node_modules/typescript/lib/tsserver.js", "/lib/node_modules/typescript/lib/tsserver.js" }
    local function probe_dir(base)
        for _, rel in ipairs(rels) do
            local st = uv.fs_stat(base .. rel)
            if st and st.type == "file" then
                return base .. rel
            end
        end
        return nil
    end
    for _, ch in ipairs({ "6", "5", "latest" }) do
        local found = probe_dir(npm_ts_dir .. "/" .. ch)
        if found then
            return found
        end
    end
    local scan = uv.fs_scandir(npm_ts_dir)
    if scan then
        local vers = {}
        while true do
            local name = uv.fs_scandir_next(scan)
            if not name then
                break
            end
            if name:match("^%d") then
                vers[#vers + 1] = name
            end
        end
        table.sort(vers, function(a, b)
            local pa, pb = vim.split(a, ".", { plain = true }), vim.split(b, ".", { plain = true })
            for i = 1, math.max(#pa, #pb) do
                local na, nb = tonumber(pa[i]) or -1, tonumber(pb[i]) or -1
                if na ~= nb then
                    return na > nb
                end
            end
            return a > b
        end)
        for _, v in ipairs(vers) do
            local found = probe_dir(npm_ts_dir .. "/" .. v)
            if found then
                return found
            end
        end
    end
    local ts_bin = vim.fn.exepath("tsserver")
    if ts_bin ~= "" then
        local real_bin = uv.fs_realpath(ts_bin) or ts_bin
        local cand = vim.fn.fnamemodify(real_bin, ":h:h") .. "/lib/tsserver.js"
        local st = uv.fs_stat(cand)
        if st and st.type == "file" then
            return cand
        end
    end
    return nil
end

local function build_server_configs(tsserver_fallback)
    return {
        clangd = {
            cmd = {
                "clangd",
                "--background-index",
                "--clang-tidy",
                "--header-insertion=iwyu",
                "--completion-style=detailed",
                "--fallback-style=llvm",
            },
        },
        lua_ls = {
            settings = {
                Lua = {
                    diagnostics = {
                        globals = { "vim" },
                    },
                    workspace = {
                        library = vim.api.nvim_get_runtime_file("", true),
                        checkThirdParty = false,
                    },
                    telemetry = { enable = false },
                },
            },
        },
        rust_analyzer = {
            settings = {
                ["rust-analyzer"] = {
                    check = {
                        command = "check",
                    },
                },
            },
        },
        gopls = {},
        pyright = {},
        ts_ls = {
            init_options = {
                hostInfo = "neovim",
                tsserver = tsserver_fallback and { fallbackPath = tsserver_fallback } or nil,
            },
        },
        bashls = {},
        terraformls = {},
        yamlls = {
            settings = {
                yaml = {
                    validate = false,
                },
            },
        },
        jsonls = {
            settings = {
                json = {
                    validate = { enable = false },
                },
            },
        },
        leanls = {
            cmd = { "lake", "serve", "--" },
            filetypes = { "lean" },
            root_markers = { "lakefile.toml", "lakefile.lean", "lean-toolchain", ".git" },
        },
    }
end

local function install_nonblocking_mason_notify()
    -- Keep background Mason status/error echoes within cmdheight=1 echospace so failed offline/mirror
    -- installs never trigger a modal "Press ENTER" prompt that freezes the Editor pane and RPC server.
    package.loaded["mason-lspconfig.notify"] = function(msg, level)
        vim.schedule(function()
            local m = vim.api.nvim_get_mode()
            if m.blocking or (m.mode ~= "n" and m.mode ~= "i") then
                return
            end
            local hl = (level == vim.log.levels.ERROR) and "DiagnosticError"
                or ((level == vim.log.levels.WARN) and "DiagnosticWarn" or "Comment")
            local line = tostring(msg or ""):gsub("[\r\n]+", " ")
            local max_w = math.max(1, (vim.v.echospace or (vim.o.columns - 12)) - 2)
            if vim.fn.strdisplaywidth(line) > max_w then
                local n = max_w - 1
                while n > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(line, 0, n)) >= max_w do
                    n = n - 1
                end
                line = vim.fn.strcharpart(line, 0, n) .. "…"
            end
            vim.cmd("silent! redraw")
            pcall(vim.api.nvim_echo, { { line, hl } }, false, {})
        end)
    end
end

function M.plugin_specs()
    return {
        {
            "williamboman/mason.nvim",
            opts = { PATH = "skip" },
        },
        {
            "mfussenegger/nvim-jdtls",
            ft = "java",
        },
        {
            "williamboman/mason-lspconfig.nvim",
            dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
            opts = {
                ensure_installed = M.ensure_installed,
                automatic_enable = false,
            },
            config = function(_, opts)
                setup_lsp_attach()
                local mise_data_dir, mason_bin_dir = calibrate_toolchain_path()
                local tsserver_fallback = resolve_tsserver_fallback(mise_data_dir)
                local server_configs = build_server_configs(tsserver_fallback)

                -- Note: jdtls is started on-demand via ftplugin/java.lua with nvim-jdtls
                if vim.lsp.config and vim.lsp.enable then
                    for _, s in ipairs(M.servers) do
                        vim.lsp.config[s] = server_configs[s] or {}
                    end
                end

                local already_enabled = {}
                local function enable_installed_servers()
                    local newly_enabled = {}
                    for _, s in ipairs(M.servers) do
                        if not already_enabled[s] then
                            local bin = server_bins[s] or s
                            if vim.fn.executable(bin) == 1 or vim.fn.executable(mason_bin_dir .. "/" .. bin) == 1 then
                                already_enabled[s] = true
                                table.insert(newly_enabled, s)
                            end
                        end
                    end
                    if #newly_enabled > 0 then
                        if vim.lsp.config and vim.lsp.enable then
                            vim.lsp.enable(newly_enabled)
                        else
                            local lspconfig = require("lspconfig")
                            for _, s in ipairs(newly_enabled) do
                                lspconfig[s].setup(server_configs[s] or {})
                            end
                        end
                    end
                end
                enable_installed_servers()

                if #vim.api.nvim_list_uis() > 0 then
                    install_nonblocking_mason_notify()
                    pcall(function()
                        require("mason-registry"):on("package:install:success", vim.schedule_wrap(enable_installed_servers))
                    end)
                    require("mason-lspconfig").setup(opts)
                end
            end,
        },
    }
end

return M
