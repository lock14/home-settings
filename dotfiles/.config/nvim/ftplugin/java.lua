-- Java Filetype Plugin for Neovim (nvim-jdtls integration)
-- Runs on-demand ONLY when a .java file is opened.

local status_ok, jdtls = pcall(require, "jdtls")
if not status_ok then
    return
end

-- Detect Maven or Gradle build root; skip auto-starting jdtls in Bazel-only workspaces.
-- Walk upward one level at a time checking regular files (`type == "file"`) so we stop
-- immediately at a Bazel workspace boundary without probing outer FUSE mount parents or
-- matching synthesized mount directories (such as `mvnw/` or `gradlew/`).
local uv = vim.uv or vim.loop
local maven_gradle_markers = { "pom.xml", "build.gradle", "build.gradle.kts", "mvnw", "gradlew" }
local bazel_markers = { "WORKSPACE", "WORKSPACE.bazel", "MODULE.bazel" }
local buf_dir = vim.fn.expand("%:p:h")
local build_root = nil
local git_root = nil
if uv and buf_dir ~= "" then
    local cur = vim.fs.normalize(buf_dir)
    while cur and cur ~= "" do
        local sep = (cur == "/") and "" or "/"
        for _, m in ipairs(maven_gradle_markers) do
            local st = uv.fs_stat(cur .. sep .. m)
            if st and st.type == "file" then
                build_root = cur
                break
            end
        end
        if build_root then
            break
        end
        for _, bm in ipairs(bazel_markers) do
            local bst = uv.fs_stat(cur .. sep .. bm)
            if bst and bst.type == "file" then
                return
            end
        end
        if not git_root and uv.fs_stat(cur .. sep .. ".git") then
            git_root = cur
        end
        local parent = vim.fs.dirname(cur)
        if not parent or parent == cur then
            break
        end
        cur = parent
    end
end
local root_dir = build_root or git_root or buf_dir

-- Compute hash-salted workspace directory under XDG_CACHE_HOME to prevent OSGi lock collisions
local norm_root = vim.fs.normalize(vim.fn.fnamemodify(root_dir, ":p")):gsub("/+$", "")
if norm_root == "" then
    norm_root = "/"
end
local project_name = vim.fn.fnamemodify(norm_root, ":t")
if project_name == "" then
    project_name = "root"
end
local root_hash = vim.fn.sha256(norm_root):sub(1, 8)
local xdg_cache = vim.env.XDG_CACHE_HOME
local cache_dir = (xdg_cache and xdg_cache ~= "") and xdg_cache or (vim.env.HOME .. "/.cache")
local workspace_dir = cache_dir .. "/jdtls/workspaces/" .. project_name .. "-" .. root_hash

-- Locate jdtls binary (from Mason or system PATH)
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/jdtls"
local cmd = nil

if vim.fn.executable(mason_bin) == 1 then
    cmd = { mason_bin, "-data", workspace_dir }
elseif vim.fn.executable("jdtls") == 1 then
    cmd = { "jdtls", "-data", workspace_dir }
else
    -- Search in Mason package directory if launcher script isn't linked yet
    local mason_pkg_dir = vim.fn.stdpath("data") .. "/mason/packages/jdtls"
    local launcher_jar = vim.fn.glob(mason_pkg_dir .. "/plugins/org.eclipse.equinox.launcher_*.jar")
    if launcher_jar ~= "" then
        local os_config = vim.fn.has("mac") == 1 and "config_mac" or "config_linux"
        cmd = {
            "java",
            "-Declipse.application=org.eclipse.jdt.ls.core.id1",
            "-Dosgi.bundles.defaultStartLevel=4",
            "-Declipse.product=org.eclipse.jdt.ls.core.product",
            "-Dlog.level=ALL",
            "-Xms512m",
            "-Xmx1g",
            "-jar", launcher_jar,
            "-configuration", mason_pkg_dir .. "/" .. os_config,
            "-data", workspace_dir,
        }
    end
end

if not cmd then
    return
end

local config = {
    cmd = cmd,
    root_dir = root_dir,
    settings = {
        java = {
            signatureHelp = { enabled = true },
            contentProvider = { preferred = "fernflower" },
            completion = {
                favoriteStaticMembers = {
                    "org.junit.Assert.*",
                    "org.junit.Assume.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "org.junit.jupiter.api.Assumptions.*",
                    "org.junit.jupiter.api.DynamicContainer.*",
                    "org.junit.jupiter.api.DynamicTest.*",
                    "org.mockito.Mockito.*",
                    "org.mockito.ArgumentMatchers.*",
                },
            },
            sources = {
                organizeImports = {
                    starThreshold = 9999,
                    staticStarThreshold = 9999,
                },
            },
        },
    },
    on_attach = function(client, bufnr)
        -- Disable LSP semantic token overrides so Treesitter handles syntax highlighting
        client.server_capabilities.semanticTokensProvider = nil
        -- Disable documentLinkProvider to eliminate rogue clickable hyperlink metadata and spurious link highlights
        client.server_capabilities.documentLinkProvider = nil

        local bufmap = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "Java LSP: " .. desc })
        end

        bufmap("<leader>jo", jdtls.organize_imports, "Organize Imports")
        bufmap("<leader>jv", jdtls.extract_variable, "Extract Variable")
        bufmap("<leader>jc", jdtls.extract_constant, "Extract Constant")
        bufmap("<leader>jm", jdtls.extract_method, "Extract Method")
    end,
}

jdtls.start_or_attach(config)
