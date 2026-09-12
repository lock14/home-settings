-- Java Filetype Plugin for Neovim (nvim-jdtls integration)
-- Runs on-demand ONLY when a .java file is opened.

local status_ok, jdtls = pcall(require, "jdtls")
if not status_ok then
    return
end

-- Detect project root (Maven pom.xml, Gradle build.gradle, git repo, or fallback to file dir)
local root_markers = { "pom.xml", "build.gradle", "build.gradle.kts", ".git", "mvnw", "gradlew" }
local root_dir = vim.fs.root(0, root_markers) or vim.fn.expand("%:p:h")

-- Compute unique workspace directory per project under XDG_CACHE_HOME to prevent lock collisions
local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
local cache_dir = vim.env.XDG_CACHE_HOME or (vim.env.HOME .. "/.cache")
local workspace_dir = cache_dir .. "/jdtls/workspaces/" .. project_name

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
