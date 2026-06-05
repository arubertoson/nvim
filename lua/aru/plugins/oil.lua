local log = require("aru.log")

local ok, oil = pcall(require, "oil")
if not ok then
    log:error(("Failed to load oil.nvim: %s, oil features will be disabled"):format(oil))
end

local function toggle_oil()
    if vim.bo[0].filetype == "oil" then
        require("oil").discard_all_changes()
        require("oil").close()
    else
        require("oil").open_float()
    end
end

local function toggle_cwd_oil()
    if vim.bo[0].filetype == "oil" then
        require("oil").discard_all_changes()
        require("oil").close()
    else
        require("oil").open_float(vim.fn.getcwd())
    end
end

local function parse_git_output(proc)
    local result = proc:wait()
    local ignored = {}

    if result.code ~= 0 then return ignored end

    for line in vim.gsplit(result.stdout, "\n", { plain = true, trimempty = true }) do
        ignored[line:gsub("/$", "")] = true
    end

    return ignored
end

local function new_git_ignored()
    return setmetatable({}, {
        __index = function(self, dir)
            local ignored = {}

            if vim.fn.executable("git") == 1 then
                ignored = parse_git_output(vim.system({
                    "git",
                    "ls-files",
                    "--ignored",
                    "--exclude-standard",
                    "--others",
                    "--directory",
                }, {
                    cwd = dir,
                    text = true,
                }))
            end

            rawset(self, dir, ignored)
            return ignored
        end,
    })
end

local git_ignored = new_git_ignored()
local hide_gitignored = true
local refresh = require("oil.actions").refresh
local refresh_callback = refresh.callback

local function toggle_gitignored()
    hide_gitignored = not hide_gitignored
    refresh_callback()
    vim.notify(("Oil: %s gitignored files"):format(hide_gitignored and "hiding" or "showing"))
end

refresh.callback = function(...)
    git_ignored = new_git_ignored()
    refresh_callback(...)
end

require("oil").setup({
    view_options = {
        show_hidden = true,
        is_always_hidden = function(name, bufnr)
            if not hide_gitignored then return false end

            local dir = require("oil").get_current_dir(bufnr)

            if not dir then return false end

            return git_ignored[dir][name] == true
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
        ["g."] = toggle_gitignored,
    },
})

-- Open parent directory in current window
vim.keymap.set("n", "<leader>n", toggle_oil, { desc = "Open Oil" })
vim.keymap.set("n", "<leader>N", toggle_cwd_oil, { desc = "Open Oil" })

vim.api.nvim_create_autocmd("User", {
    pattern = "OilEnter",
    callback = function()
        vim.opt_local.number = false
        vim.opt_local.showtabline = 0
        vim.opt_local.signcolumn = "no"
    end,
})
