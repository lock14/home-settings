-- Conceal-safe Tree-sitter AST and LSP link, anchor, and custom workspace rule navigation.

local M = {}

local ide_job_fn = nil

local function url_decode(str)
    return (str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function M.markdown_heading_slug(raw)
    if not raw or raw == "" then
        return ""
    end
    local h = raw:gsub("^%s*#+%s+", ""):gsub("%s+#+%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    h = h:gsub("%[(.-)%]%b()", "%1"):gsub("%[(.-)%]%b[]", "%1"):gsub("<[^>]+>", "")
    h = h:gsub("–", ""):gsub("—", ""):gsub("‘", ""):gsub("’", ""):gsub("“", ""):gsub("”", "")
    h = vim.fn.tolower(h):gsub("%p", function(c)
        return (c == "-" or c == "_") and c or ""
    end)
    return (h:gsub(" ", "-"))
end

function M.find_markdown_anchor_line(bufnr, raw_slug)
    local cleaned_slug = url_decode(raw_slug or ""):gsub("^#+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local target_slug = vim.fn.tolower(cleaned_slug)
    if target_slug == "" then
        return nil
    end

    local b = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
    local ok, parser = pcall(vim.treesitter.get_parser, b, "markdown")
    if ok and parser then
        local tree = (parser:parse() or {})[1]
        if tree then
            local q = vim.treesitter.query.parse("markdown", "(atx_heading (inline) @h)")
            local seen = {}
            for _, node in q:iter_captures(tree:root(), b) do
                local base = M.markdown_heading_slug(vim.treesitter.get_node_text(node, b))
                local count = seen[base] or 0
                seen[base] = count + 1
                local full = count == 0 and base or string.format("%s-%d", base, count)
                if full == target_slug or (count == 0 and base == target_slug) then
                    return (node:range()) + 1
                end
            end
        end
    end
    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
        local html_id = line:match('<a%s+[^>]*id=["\']([^"\']+)["\']')
            or line:match('<a%s+[^>]*name=["\']([^"\']+)["\']')
        if html_id and html_id:lower() == target_slug then
            return lnum
        end
    end
    return nil
end

local function resolve_markdown_ref_label(bufnr, raw_label)
    local cleaned = (vim.trim((raw_label or ""):gsub("^%[", ""):gsub("%]$", "")):gsub("%s+", " "))
    local norm = vim.fn.tolower(cleaned)
    if norm == "" then
        return nil
    end
    local b = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
    local ok, parser = pcall(vim.treesitter.get_parser, b, "markdown")
    if not (ok and parser) then
        return nil
    end
    local tree = (parser:parse() or {})[1]
    if not tree then
        return nil
    end
    local q_ok, q = pcall(
        vim.treesitter.query.parse,
        "markdown",
        "(link_reference_definition (link_label) @lbl (link_destination) @dst)"
    )
    if not (q_ok and q) then
        return nil
    end
    for _, match in q:iter_matches(tree:root(), b) do
        local lbl_node = match[1]
        local dst_node = match[2]
        if type(lbl_node) == "table" then
            lbl_node = lbl_node[1]
        end
        if type(dst_node) == "table" then
            dst_node = dst_node[1]
        end
        if lbl_node and dst_node then
            local cand_clean = (
                vim.trim(vim.treesitter.get_node_text(lbl_node, b):gsub("^%[", ""):gsub("%]$", "")):gsub("%s+", " ")
            )
            if vim.fn.tolower(cand_clean) == norm then
                return (vim.treesitter.get_node_text(dst_node, b):gsub("^<", ""):gsub(">$", ""))
            end
        end
    end
    return nil
end

function M.extract_link_at_cursor()
    pcall(vim.treesitter.start, 0)
    local pos = vim.api.nvim_win_get_cursor(0)
    local row, col = pos[1] - 1, pos[2]
    pcall(function()
        local parser = vim.treesitter.get_parser(0)
        if not pcall(parser.parse, parser, { row, row + 1 }) then
            parser:parse(true)
        end
    end)
    local line = vim.api.nvim_get_current_line()
    local lcol = line:match("^%s*[-*+%d.)]*%s*%[[ xX]%]%s*()[!]?%[")
        or line:match("^%s*[-*+%d.)]*%s*()[!]?%[")
    if lcol and col < lcol - 1 then
        col = lcol - 1
    end
    local ok, node = pcall(vim.treesitter.get_node, { pos = { row, col }, ignore_injections = false })
    while ok and node do
        local t = node:type()
        if t == "uri_autolink" then
            return (vim.treesitter.get_node_text(node, 0):gsub("^<", ""):gsub(">$", "")), true
        elseif t == "image" then
            local dest, in_dest = nil, false
            local ref_label, desc_node = nil, nil
            for child in node:iter_children() do
                local ct = child:type()
                if ct == "link_destination" then
                    dest = vim.treesitter.get_node_text(child, 0):gsub("^<", ""):gsub(">$", "")
                    local sr, sc, er, ec = child:range()
                    if (row > sr or (row == sr and col >= sc)) and (row < er or (row == er and col < ec)) then
                        in_dest = true
                    end
                elseif ct == "link_label" then
                    ref_label = vim.treesitter.get_node_text(child, 0)
                elseif ct == "image_description" then
                    desc_node = child
                end
            end
            if (not dest or dest == "") and desc_node then
                for sub in desc_node:iter_children() do
                    if sub:type() == "shortcut_link" then
                        for inner in sub:iter_children() do
                            if inner:type() == "link_text" then
                                local wiki = vim.treesitter.get_node_text(inner, 0)
                                    :gsub("^%[", "")
                                    :gsub("%]$", "")
                                    :gsub("|.*$", "")
                                if wiki ~= "" then
                                    dest = wiki
                                end
                            end
                        end
                    end
                end
            end
            if (not dest or dest == "") and (ref_label or desc_node) then
                local lookup = (ref_label and ref_label ~= "[]") and ref_label
                    or (desc_node and vim.treesitter.get_node_text(desc_node, 0):gsub("^!%[", ""):gsub("%]$", ""))
                if lookup and lookup ~= "" then
                    dest = resolve_markdown_ref_label(0, lookup)
                end
            end
            local has_outer_link = false
            if not in_dest then
                local anc = node:parent()
                while anc do
                    if anc:type() == "inline_link" then
                        has_outer_link = true
                        break
                    end
                    anc = anc:parent()
                end
            end
            if dest and dest ~= "" and not has_outer_link then
                return dest, true
            end
        elseif t == "inline_link" then
            local dest, label = nil, nil
            for child in node:iter_children() do
                local ct = child:type()
                if ct == "link_destination" then
                    dest = vim.treesitter.get_node_text(child, 0):gsub("^<", ""):gsub(">$", "")
                elseif ct == "link_text" then
                    label = vim.treesitter
                        .get_node_text(child, 0)
                        :gsub("^%[", "")
                        :gsub("%]$", "")
                        :gsub("^`", "")
                        :gsub("`$", "")
                end
            end
            if dest then
                if label and not dest:find("[#:]") then
                    local lbl_line = label:match(":[Ll]?(%d+)") or label:match("#[Ll]?(%d+)")
                    if lbl_line then
                        dest = dest .. "#L" .. lbl_line
                    end
                end
                return dest, true
            end
        end
        node = node:parent()
    end
    if #line > 0 then
        local idx = math.min(math.max(1, col + 1), #line)
        local sep_pat = "[%s%(%)%[%]%{%}<>\"'`,;*]"
        if line:sub(idx, idx):match(sep_pat) then
            if idx < #line and not line:sub(idx + 1, idx + 1):match(sep_pat) then
                idx = idx + 1
            elseif idx > 1 and not line:sub(idx - 1, idx - 1):match(sep_pat) then
                idx = idx - 1
            end
        end
        if not line:sub(idx, idx):match(sep_pat) then
            local s, e = idx, idx
            while s > 1 and not line:sub(s - 1, s - 1):match(sep_pat) do
                s = s - 1
            end
            while e < #line and not line:sub(e + 1, e + 1):match(sep_pat) do
                e = e + 1
            end
            local tok = line:sub(s, e)
            if not tok:match("/%.%.%.?$") then
                tok = tok:gsub("[.,;:]+$", "")
            end
            if tok ~= "" then
                return tok, false
            end
        end
    end
    local cfile = vim.fn.expand("<cfile>")
    if cfile ~= "" then
        return cfile:gsub("^<", ""):gsub("[>.,;)]+$", ""), false
    end
    return nil, false
end

function M.resolve_custom_link_rule(word, cwd)
    if not word or word == "" then
        return nil
    end
    local uv = vim.uv or vim.loop
    local xdg_cfg = vim.env.XDG_CONFIG_HOME
    if not xdg_cfg or xdg_cfg == "" then
        xdg_cfg = vim.fn.expand("$HOME/.config")
    end
    local rules = vim.env.IDE_LINK_RULES
    if not rules or rules == "" then
        rules = xdg_cfg .. "/ide/links.sh"
    end
    local st = uv.fs_stat(rules)
    if not st or st.type ~= "file" then
        return nil
    end
    local out = vim.fn.system({
        "bash",
        "-c",
        '. "$1" && declare -F ide_resolve_link >/dev/null && ide_resolve_link "$2" "$3"',
        "ide",
        rules,
        word,
        cwd or uv.cwd() or "",
    })
    if vim.v.shell_error ~= 0 or not out then
        return nil
    end
    out = out:gsub("[\r\n]+$", "")
    return out ~= "" and out or nil
end

local function open_external_url(url, base_dir)
    if vim.env.TMUX and vim.env.TMUX ~= "" and ide_job_fn and vim.fn.executable(vim.fn.expand("$HOME/.local/bin/ide")) == 1 then
        ide_job_fn("--open-link", url, url, base_dir)
    elseif vim.ui and vim.ui.open then
        vim.ui.open(url)
    end
end

local function open_local_file_target(raw_target, dir)
    local uv = vim.uv or vim.loop
    local raw_path = url_decode(raw_target:gsub("^file://[^/]*", ""))

    local file_path, fragment = raw_path:match("^([^#]+)#?(.*)$")
    file_path = file_path or raw_path
    fragment = fragment or ""

    local line_num = fragment:match("^[Ll]?(%d+)") or file_path:match(":[Ll]?(%d+)")
    if file_path:match(":[Ll]?%d+") then
        file_path = file_path:gsub(":[Ll]?%d+.*$", "")
    end

    local is_abs = file_path:match("^/") or file_path:match("^%a:[/\\]")
    local resolved_path = is_abs and vim.fs.normalize(file_path)
        or vim.fs.normalize(vim.fs.joinpath(dir, file_path))
    local st = uv.fs_stat(resolved_path)

    if st and st.type == "file" then
        pcall(function()
            require("mini.files").close()
        end)
        vim.cmd("normal! m'")
        vim.cmd("keepjumps edit " .. vim.fn.fnameescape(resolved_path))
        if line_num and tonumber(line_num) then
            vim.cmd(string.format("keepjumps call cursor(%d, 1) | normal! ^zz", tonumber(line_num)))
        elseif fragment and fragment ~= "" then
            local lnum = M.find_markdown_anchor_line(0, fragment)
            if lnum then
                vim.cmd(string.format("keepjumps call cursor(%d, 1) | normal! ^zz", lnum))
            end
        end
        return true
    end
    return false
end

function M.follow_editor_link(at_mouse, fallback_tag)
    if at_mouse then
        local m = vim.fn.getmousepos()
        if m.winid > 0 and vim.api.nvim_win_is_valid(m.winid) then
            if vim.fn.mode():find("[vV\22]") then
                vim.cmd("normal! \27")
            end
            vim.api.nvim_set_current_win(m.winid)
            if m.line > 0 then
                local bufnr = vim.api.nvim_win_get_buf(m.winid)
                local line_cnt = vim.api.nvim_buf_line_count(bufnr)
                local lnum = math.min(m.line, line_cnt)
                local line_str = (vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]) or ""
                local col = math.min(math.max(0, m.column - 1), math.max(0, #line_str - 1))
                pcall(vim.api.nvim_win_set_cursor, m.winid, { lnum, col })
            end
        end
    end

    local uv = vim.uv or vim.loop
    local base_dir = vim.fn.expand("%:p:h")
    if base_dir == "" then
        base_dir = uv.cwd()
    end

    local target, is_md = M.extract_link_at_cursor()
    if target and target ~= "" then
        if target:sub(1, 1) == "#" and (is_md or vim.bo.filetype == "markdown") then
            local lnum = M.find_markdown_anchor_line(0, target:sub(2))
            if lnum then
                vim.cmd("normal! m'")
                vim.cmd(string.format("keepjumps call cursor(%d, 1) | normal! ^zz", lnum))
                return true
            end
            return false
        end

        if target:match("^https?://") then
            local custom_target = M.resolve_custom_link_rule(target, base_dir)
            if custom_target and custom_target:match("^file://") and open_local_file_target(custom_target, base_dir) then
                return true
            end
            local open_url = (custom_target and custom_target:match("^https?://")) and custom_target or target
            open_external_url(open_url, base_dir)
            return true
        end

        if is_md or vim.bo.filetype == "markdown" or target:match("^file://") or target:find("[/\\.]") then
            if not target:match("^//") and open_local_file_target(target, base_dir) then
                return true
            end
            if target:find("/") or target:match("^@?%d%d%d%d%d%d+$") then
                local custom_target = M.resolve_custom_link_rule(target, base_dir)
                if custom_target then
                    if open_local_file_target(custom_target, base_dir) then
                        return true
                    elseif custom_target:match("^https?://") then
                        open_external_url(custom_target, base_dir)
                        return true
                    end
                end
            end
        end
    end

    if at_mouse or fallback_tag then
        local has_lsp = vim.lsp
            and vim.lsp.get_clients
            and #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" }) > 0
        if has_lsp then
            vim.lsp.buf.definition()
            return true
        elseif fallback_tag then
            pcall(vim.cmd, "normal! \29")
            return true
        end
    end
    return false
end

function M.setup(opts)
    ide_job_fn = opts and opts.ide_job or nil
end

return M
