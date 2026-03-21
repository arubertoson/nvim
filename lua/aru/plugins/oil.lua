local log = require("aru.log")

local ok, oil = pcall(require, "oil")
if not ok then
    log:error(
        ("Failed to load oil.nvim: %s, oil features will be disabled"):format(
            oil
        )
    )
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

require("oil").setup({
    view_options = {
        show_hidden = true,
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
