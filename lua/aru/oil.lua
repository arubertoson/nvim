---@module "aru.oil"
---Oil behavior and asynchronous Git-ignore state.

local M = {}

local ignored_by_dir = {}
local pending_by_dir = {}
local hide_gitignored = true

local oil
local refresh_callback

---@param stdout string
---@return table<string, boolean>
local function parse_git_output(stdout)
    local ignored = {}
    for line in vim.gsplit(stdout, "\n", { plain = true, trimempty = true }) do
        ignored[line:gsub("/$", "")] = true
    end
    return ignored
end

---@param bufnr integer
---@param dir string
local function refresh_buffer(bufnr, dir)
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].modified then return end
    if oil.get_current_dir(bufnr) ~= dir then return end

    local wins = vim.fn.win_findbuf(bufnr)
    local win = wins[1]
    if not win or not vim.api.nvim_win_is_valid(win) then return end

    vim.api.nvim_win_call(win, function() refresh_callback() end)
end

---@param bufnr integer
---@param dir string
local function request_gitignored(bufnr, dir)
    local pending = pending_by_dir[dir]
    if pending then
        pending.buffers[bufnr] = true
        return
    end
    if ignored_by_dir[dir] then return end

    pending = { buffers = { [bufnr] = true } }
    pending_by_dir[dir] = pending

    if vim.fn.executable("git") ~= 1 then
        ignored_by_dir[dir] = {}
        pending_by_dir[dir] = nil
        return
    end

    vim.system({
        "git",
        "ls-files",
        "--ignored",
        "--exclude-standard",
        "--others",
        "--directory",
    }, {
        cwd = dir,
        text = true,
    }, function(result)
        local ignored = result.code == 0 and parse_git_output(result.stdout) or {}

        vim.schedule(function()
            if pending_by_dir[dir] ~= pending then return end

            ignored_by_dir[dir] = ignored
            pending_by_dir[dir] = nil

            if not hide_gitignored then return end
            for pending_bufnr in pairs(pending.buffers) do
                refresh_buffer(pending_bufnr, dir)
            end
        end)
    end)
end

---@param bufnr integer
local function load_current_gitignored(bufnr)
    local dir = oil.get_current_dir(bufnr)
    if dir then request_gitignored(bufnr, dir) end
end

local function refresh_gitignored()
    local bufnr = vim.api.nvim_get_current_buf()
    local dir = oil.get_current_dir(bufnr)
    if dir then
        ignored_by_dir[dir] = nil
        request_gitignored(bufnr, dir)
    end
    refresh_callback()
end

local function toggle_gitignored()
    hide_gitignored = not hide_gitignored
    if hide_gitignored then load_current_gitignored(vim.api.nvim_get_current_buf()) end
    refresh_callback()
    vim.notify(("Oil: %s gitignored files"):format(hide_gitignored and "hiding" or "showing"))
end

local function get_oil() return oil or require("oil") end

function M.toggle()
    local current_oil = get_oil()
    if vim.bo[0].filetype == "oil" then
        current_oil.discard_all_changes()
        current_oil.close()
    else
        current_oil.open_float()
    end
end

function M.toggle_cwd()
    local current_oil = get_oil()
    if vim.bo[0].filetype == "oil" then
        current_oil.discard_all_changes()
        current_oil.close()
    else
        current_oil.open_float(vim.fn.getcwd())
    end
end

function M.setup()
    oil = require("oil")
    refresh_callback = require("oil.actions").refresh.callback

    oil.setup({
        view_options = {
            show_hidden = true,
            is_always_hidden = function(name, bufnr)
                if not hide_gitignored then return false end

                local dir = oil.get_current_dir(bufnr)
                local ignored = dir and ignored_by_dir[dir] or nil
                return ignored and ignored[name] == true or false
            end,
        },
        float = {
            padding = 5,
            max_width = 80,
            preview_split = "below",
        },
        watch_for_changes = true,
        skip_confirm_for_simple_edits = true,
        keymaps = {
            q = "actions.close",
            ["<C-k>"] = "actions.parent",
            ["<C-j>"] = "actions.select",
            ["<C-p>"] = "actions.preview",
            ["<C-l>"] = refresh_gitignored,
            ["g."] = toggle_gitignored,
        },
    })

    vim.api.nvim_create_autocmd("User", {
        group = vim.api.nvim_create_augroup("aru_oil_gitignored", { clear = true }),
        pattern = "OilEnter",
        desc = "Populate Oil Git-ignore state asynchronously",
        callback = function(ev) load_current_gitignored(ev.data.buf) end,
    })
end

return M
