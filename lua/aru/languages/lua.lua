---@module "aru.languages.lua"
---
--- Dynamic, project-aware configuration for lua-language-server in Neovim.
---
--- What this module does:
--- 1) Registers lua_ls and stylua with sane defaults that do not nuke performance.
--- 2) On attach, patches the lua_ls client so it answers "workspace/configuration"
---    with settings that reflect the current project.
--- 3) Classifies a project as "Neovim config or plugin" if it is under stdpath("config")
---    or has a top-level "lua/" directory. Those get the Neovim library and "vim" global.
--- 4) Builds Lua workspace.library dynamically from:
---      - project_root/lua
---      - $VIMRUNTIME/lua
---      - every entry in runtimepath with "lua" appended
---    Paths are normalized and deduped via fs_realpath.
--- 5) Guarantees N-in, N-out for "workspace/configuration" requests even on error
---    by returning vim.NIL entries when necessary.
--- 6) Never clobbers unrelated handlers.
---
--- Why you care:
--- - Cleaner diagnostics, correct imports, less CPU spent indexing junk.
--- - No stale config when you hop between a plain Lua repo and your Neovim config.
---
--- Notes:
--- - You can call M.update(client) to push a config refresh if the server does not re-query.
--- - This expects Neovim with vim.lsp.config available.
---
--- TODO: If lua_ls indexing becomes slow, filter vim.api.nvim_list_runtime_paths()
--- to exclude /site/pack/ and %.cache/ directories
---
--- TODO: this was done to learn, grabbing luadev in the future from folke will
--- be a better approach then rolling my own

local log = require("aru.log")

---@class AruLuaDefaults
---@field Lua { runtime: { version: "LuaJIT", path: string[] }, diagnostics: { groupFileStatus: { redefined: string } } }

---@class AruLuaMerged : AruLuaDefaults
---@field Lua { workspace?: { checkThirdParty?: boolean, library?: string[] }, diagnostics?: { globals?: string[] } }

---@class LspHandlerContext
---@field client_id integer

---@class LspConfigurationItem
---@field section string|nil
---@field scopeUri string|nil

---@class LspConfigurationParams
---@field items LspConfigurationItem[]

vim.lsp.config("lua_ls", {
    cmd = { "lua-language-server" },
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
            -- semantic = {
            -- 	unusedLocalExclude = { "*" },
            -- },
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
})

vim.lsp.config("stylua", {
    cmd = { "stylua", "--lsp" },
    filetypes = { "lua" },
    root_markers = { ".stylua.toml", "stylua.toml", ".editorconfig" },
})

vim.lsp.enable({ "lua_ls" })

---Build the library list for LuaLS based on the current project.
---Includes project_root/lua, $VIMRUNTIME/lua, and runtimepath/*/lua.
---@param root string root directory of the project
---@return string[] paths absolute, deduped, existing
local function build_lua_ls_library(root)
    local out, seen = {}, {}

    ---Normalize and realpath a path for dedupe. Falls back to normalized input.
    ---@param p string|nil
    ---@return string|nil
    local function realpath(p)
        if not p or p == "" then return nil end

        p = vim.fs.normalize(p)
        return vim.uv.fs_realpath(p)
    end

    ---Add a path if it exists and is not already present.
    ---@param p string|nil
    local function add(p)
        p = realpath(p)
        if not p or seen[p] then return end

        if vim.uv.fs_stat(p) then
            seen[p] = true
            out[#out + 1] = p
        end
    end

    local join = vim.fs.joinpath

    if root and root ~= "" then add(join(root, "lua")) end

    -- We add the runtime and the config path to the library, these are statci and should always
    -- be present.
    local v = vim.env.VIMRUNTIME
    if v and v ~= "" then add(join(v, "lua")) end

    for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
        add(join(rtp, "lua"))
    end

    return out
end

---Heuristic: treat root as a Neovim config or plugin workspace.
---True if under stdpath("config") or has a top-level "lua" directory.
---@param root string
---@return boolean
local function is_nvim_project(root)
    root = root or vim.uv.cwd()
    if not root or root == "" then return false end

    local cfg = vim.fn.stdpath("config")
    if root == cfg or root:sub(1, #cfg) == cfg then return true end

    -- XXX: this is not right, if other lua projects have a "lua"
    -- dir underneath it's root this will be treated as a neovim
    -- plugin.
    local stat = vim.uv.fs_stat(vim.fs.joinpath(root, "lua"))
    if stat and stat.type == "directory" then return true end

    return false
end

---Answer "workspace/configuration" with project-aware settings.
---Guarantees N results for N requested items, uses vim.NIL when unavailable.
---@param err any
---@param params LspConfigurationParams
---@param ctx LspHandlerContext
---@param _ any
---@return any[] response array aligned with params.items
local function refresh_library_paths(err, params, ctx, _)
    local items = (params and params.items) or {}
    if #items == 0 then return {} end

    -- If the server asks for N items we give it N items back
    -- to keep everyone happy.
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if err or not client then
        local narray = {}
        for i = 1, #items do
            narray[i] = vim.NIL
        end

        return narray
    end

    local root = nil
    if params.items[1] and params.items[1].scopeUri then
        root = vim.uri_to_fname(params.items[1].scopeUri)
    else
        root = vim.uv.cwd() or "" -- XXX: or just drop and roll (return {})
    end

    local defaults = {
        Lua = {
            diagnostics = { groupFileStatus = { redefined = "None" } },
            runtime = {
                version = "LuaJIT",
                path = { "lua/?.lua", "lua/?/init.lua" },
            },
        },
    }

    local user_settings = vim.deepcopy(client.settings or {})
    ---@type AruLuaMerged
    local merged = vim.tbl_deep_extend("force", {}, defaults, user_settings)

    if is_nvim_project(root) then
        merged = vim.tbl_deep_extend("force", merged, {
            Lua = {
                diagnostics = {
                    globals = { "vim" },
                },
                workspace = {
                    checkThirdParty = false,
                    library = build_lua_ls_library(root),
                },
            },
        })
    else
        merged = vim.tbl_deep_extend("force", merged, {
            Lua = {
                workspace = { checkThirdParty = false, library = {} },
            },
        })
    end

    -- Persist the merged view on the client for later pushes
    client.settings = merged

    local response = {}
    for _, item in ipairs(params.items) do
        local val

        if item.section == "" then
            val = merged
        else
            local keys = vim.split(item.section, ".", { plain = true })
            val = vim.tbl_get(merged, unpack(keys))
        end

        table.insert(response, val == nil and vim.NIL or val)
    end

    return response
end

---@type table<number, boolean>
local attached = {}

vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
    desc = [[
A simple handler to update the lua_ls clients library paths to be more dynamic and
reflect what is to be expected by different projects.
]],
    callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if not client then return end

        if ev.event == "LspAttach" and client.name == "lua_ls" then
            if attached[client.id] then
                log:debug("lang.lua: client %d:%s already patched; skip.", client.id, client.name)
                return
            end
            log:debug("lang.lua: patching client %d:%s for buf %d", client.id, client.name, ev.buf)

            attached[client.id] = true

            client.handlers["workspace/configuration"] = refresh_library_paths
        else
            log:debug("lang.lua: detach from client %d:%s buf %d", client.id, client.name, ev.buf)
            attached[client.id] = nil
        end

        -- Optional manual push if you observe stale behavior:
        -- client:notify("workspace/didChangeConfiguration", { settings = { Lua = {} }})
    end,
})

local M = {}

---Ask the server to re-read config from client.settings.
---Use only if the server does not re-query by itself.
---@param client vim.lsp.Client
function M.update(client)
    client:notify("workspace/didChangeConfiguration", { settings = { Lua = {} } })
end

return M
