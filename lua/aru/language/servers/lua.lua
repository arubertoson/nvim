---@module "aru.language.servers.lua"
---
--- Configure LuaLS for two workspace kinds:
--- - Plain Lua workspaces use the shared Lua defaults below.
--- - Neovim workspaces additionally know about `vim`, the Neovim runtime, and
---   Lua modules available on runtimepath.
---
--- A workspace is considered Neovim-owned when it is this configuration (with
--- symlinks resolved), or when it has a top-level `lua/` directory and does not
--- provide its own `.luarc.json` or `.luarc.jsonc`.

---Resolve an existing path for stable comparisons and deduplication.
---@param path string
---@return string?
local function realpath(path)
    if path == "" then return end
    return vim.uv.fs_realpath(vim.fs.normalize(path))
end

---Return whether a root should receive Neovim-specific LuaLS settings.
---@param root string
---@return boolean
local function is_nvim_workspace(root)
    local resolved_root = realpath(root)
    if not resolved_root then return false end

    local config_root = realpath(vim.fn.stdpath("config"))
    if config_root and vim.fs.relpath(config_root, resolved_root) then return true end

    if
        vim.uv.fs_stat(vim.fs.joinpath(resolved_root, ".luarc.json"))
        or vim.uv.fs_stat(vim.fs.joinpath(resolved_root, ".luarc.jsonc"))
    then
        return false
    end

    local lua_dir = vim.uv.fs_stat(vim.fs.joinpath(resolved_root, "lua"))
    return lua_dir ~= nil and lua_dir.type == "directory"
end

---Build the Lua library visible to a Neovim workspace.
---@param root string
---@return string[]
local function build_nvim_library(root)
    local library, seen = {}, {}

    local function add(path)
        local resolved = realpath(path)
        if not resolved or seen[resolved] then return end

        seen[resolved] = true
        library[#library + 1] = resolved
    end

    add(vim.fs.joinpath(root, "lua"))
    add(vim.fs.joinpath(vim.env.VIMRUNTIME, "lua"))

    for _, runtime_path in ipairs(vim.api.nvim_list_runtime_paths()) do
        add(vim.fs.joinpath(runtime_path, "lua"))
    end

    return library
end

local lua_language_server =
    vim.fs.joinpath(vim.fn.stdpath("config"), "tools", "bin", "lua-language-server")

---@type vim.lsp.Config
vim.lsp.config("lua_ls", {
    cmd = { lua_language_server },
    filetypes = { "lua" },
    root_markers = {
        ".luarc.json",
        ".luarc.jsonc",
        ".luacheckrc",
        ".stylua.toml",
        "stylua.toml",
        "selene.toml",
        "selene.yml",
        ".git",
    },
    single_file_support = false,
    settings = {
        Lua = {
            hint = {
                enable = true,
            },
            runtime = {
                version = "LuaJIT",
                path = {
                    "lua/?.lua",
                    "lua/?/init.lua",
                },
            },
            diagnostics = {
                groupFileStatus = {
                    redefined = "None",
                },
            },
        },
    },
    before_init = function(_, config)
        if not config.root_dir or not is_nvim_workspace(config.root_dir) then return end

        config.settings.Lua = vim.tbl_deep_extend("force", config.settings.Lua, {
            diagnostics = {
                globals = { "vim" },
            },
            workspace = {
                checkThirdParty = false,
                library = build_nvim_library(config.root_dir),
            },
        })
    end,
})

vim.lsp.enable("lua_ls")
