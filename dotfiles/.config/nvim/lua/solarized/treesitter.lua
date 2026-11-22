-- Tree-sitter polyglot parser management, pinned upstream revisions, runtimepath precedence,
-- and Neovim 0.12 query directive compatibility.

local M = {}

M.parsers = {
    "c", "cpp", "go", "java", "kotlin", "swift", "python", "rust",
    "typescript", "javascript", "bash", "markdown", "markdown_inline",
    "json", "yaml", "toml", "terraform", "sql", "lua",
    "vim", "vimdoc", "diff", "printf", "xml", "html", "css",
    "properties", "proto", "textproto", "regex",
    "elixir", "haskell", "ocaml", "clojure", "lean",
    "zig", "c_sharp", "scala", "ruby",
    "graphql", "starlark", "rego", "dockerfile", "make",
}

local css_pinned_rev = "a93651c7bef1b73c47bdc7cd530ffa4ebffae032"
local lean_pinned_rev = "916c44f4d89c970f66dd34a49e7ce848f4d29e72"
M.pinned_revs = {
    css = css_pinned_rev,
    lean = lean_pinned_rev,
}
local lean_parser_spec = {
    install_info = {
        url = "https://github.com/Julian/tree-sitter-lean",
        revision = lean_pinned_rev,
        files = { "src/parser.c", "src/scanner.c" },
        location = "",
    },
    maintainers = { "@Julian" },
    tier = 2,
}

local function pin_parsers()
    local parsers_meta_ok, parsers_meta = pcall(require, "nvim-treesitter.parsers")
    if parsers_meta_ok then
        if parsers_meta.css and parsers_meta.css.install_info then
            parsers_meta.css.install_info.revision = css_pinned_rev
        end
        if not parsers_meta.get_parser_configs then
            parsers_meta.lean = vim.deepcopy(lean_parser_spec)
        else
            local pconfigs = parsers_meta.get_parser_configs()
            if pconfigs.css and pconfigs.css.install_info then
                pconfigs.css.install_info.revision = css_pinned_rev
            end
            pconfigs.lean = vim.deepcopy(lean_parser_spec)
        end
    end
end

local function read_parser_rev(lang)
    local rev_file = vim.fn.stdpath("data") .. "/site/parser-info/" .. lang .. ".revision"
    if vim.fn.filereadable(rev_file) == 1 then
        local rev_lines = vim.fn.readfile(rev_file)
        if rev_lines and #rev_lines > 0 then
            return vim.trim(rev_lines[1])
        end
    end
    return ""
end

local function register_query_directives()
    if not (vim.treesitter and vim.treesitter.query and vim.treesitter.query.add_directive) then
        return
    end
    local function unwrap_node(node)
        if type(node) == "table" and not node.range then
            return node[1]
        end
        return node
    end

    vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
        local capture_id = pred[2]
        local node = unwrap_node(match[capture_id])
        if not node or not node.range then
            return
        end
        metadata["injection.language"] = vim.treesitter.get_node_text(node, bufnr):lower()
    end, { force = true })

    vim.treesitter.query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
        local capture_id = pred[2]
        local node = unwrap_node(match[capture_id])
        if not node or not node.range then
            return
        end
        local type_attr_value = vim.treesitter.get_node_text(node, bufnr)
        local mimes = {
            ["importmap"] = "json",
            ["module"] = "javascript",
            ["application/ecmascript"] = "javascript",
            ["text/ecmascript"] = "javascript",
            ["text/javascript"] = "javascript",
        }
        if mimes[type_attr_value] then
            metadata["injection.language"] = mimes[type_attr_value]
        else
            local parts = vim.split(type_attr_value, "/", { trimempty = true })
            metadata["injection.language"] = parts[#parts]
        end
    end, { force = true })

    vim.treesitter.query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
        local capture_id = pred[2]
        local node = unwrap_node(match[capture_id])
        if not node or not node.range then
            return
        end
        metadata[pred[3]] = vim.treesitter.get_node_text(node, bufnr):lower()
    end, { force = true })
end

function M.plugin_spec(ctx)
    local config_dir = ctx and ctx.config_dir or nil
    return {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        build = function()
            if vim.env.NVIM_TS_SKIP_AUTO_INSTALL == "1" or package.loaded["nvim-treesitter.configs"] then
                return
            end
            local ok_inst, install = pcall(require, "nvim-treesitter.install")
            if ok_inst and type(install.update) == "function" then
                local task = install.update("all", { summary = true })
                if #vim.api.nvim_list_uis() == 0 and type(task) == "table" and type(task.pwait) == "function" then
                    pcall(task.pwait, task, 300000)
                end
            end
        end,
        lazy = false,
        priority = 900,
        config = function()
            pin_parsers()
            vim.api.nvim_create_autocmd("User", {
                group = vim.api.nvim_create_augroup("SolarizedTreesitterPin", { clear = true }),
                pattern = "TSUpdate",
                callback = pin_parsers,
            })

            -- Legacy nvim-treesitter.configs compatibility (when opened before lazy-lock.json syncs to main):
            -- enable highlight and indent only without triggering legacy `tree-sitter generate --no-bindings` installs.
            local ts_configs_ok, ts_configs = pcall(require, "nvim-treesitter.configs")
            if ts_configs_ok then
                ts_configs.setup({
                    ensure_installed = {},
                    auto_install = false,
                    highlight = {
                        enable = true,
                        additional_vim_regex_highlighting = false,
                    },
                    indent = { enable = true },
                })
            end

            -- Modern nvim-treesitter rewrite API
            local nts_ok, nts = pcall(require, "nvim-treesitter")
            if nts_ok and nts.setup and type(nts.get_installed) == "function" then
                pcall(function()
                    nts.setup({
                        install_dir = vim.fn.stdpath("data") .. "/site",
                    })
                end)
                if vim.env.NVIM_TS_SKIP_AUTO_INSTALL ~= "1" then
                    local ok_inst, inst_list = pcall(nts.get_installed, "parsers")
                    if not ok_inst or type(inst_list) ~= "table" then
                        inst_list = nts.get_installed()
                    end
                    local installed = {}
                    for _, p in ipairs(inst_list) do
                        installed[p] = true
                    end
                    local need_css_install = (not installed["css"]) or (read_parser_rev("css") ~= css_pinned_rev)
                    local need_lean_install = (not installed["lean"]) or (read_parser_rev("lean") ~= lean_pinned_rev)
                    local to_install = {}
                    for _, p in ipairs(M.parsers) do
                        if not installed[p] and p ~= "css" and p ~= "lean" then
                            table.insert(to_install, p)
                        end
                    end
                    if #to_install > 0 then
                        pcall(function()
                            nts.install(to_install, { max_jobs = 4 })
                        end)
                    end
                    local pinned_to_install = {}
                    if need_css_install then
                        table.insert(pinned_to_install, "css")
                    end
                    if need_lean_install then
                        table.insert(pinned_to_install, "lean")
                    end
                    if #pinned_to_install > 0 and type(nts.install) == "function" then
                        pcall(function()
                            nts.install(pinned_to_install, { force = true, max_jobs = 2 }):pwait(60000)
                        end)
                    end
                end
            end

            -- Guarantee our query overrides (queries/ and after/queries/) precede site queries in runtimepath,
            -- including when invoked via `-u dotfiles/.config/nvim/init.lua` with an unlinked XDG_CONFIG_HOME.
            local uv = vim.uv or vim.loop
            if config_dir and config_dir ~= "" then
                vim.opt.rtp:prepend(config_dir)
            end
            local std_cfg = vim.fn.stdpath("config")
            if std_cfg ~= config_dir and uv and uv.fs_stat(std_cfg) then
                vim.opt.rtp:prepend(std_cfg)
            end

            register_query_directives()

            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("SolarizedTreesitterHighlight", { clear = true }),
                callback = function(args)
                    pcall(vim.treesitter.start, args.buf)
                end,
            })
        end,
    }
end

return M
