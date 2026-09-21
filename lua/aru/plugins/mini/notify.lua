local notify = require("mini.notify")

notify.setup({
    lsp_progress = {
        enable = false,
    },
    window = {
        config = function()
            local has_statusline = vim.o.laststatus > 0
            local pad = vim.o.cmdheight + (has_statusline and 1 or 0)

            return {
                anchor = "SE",
                col = vim.o.columns,
                row = vim.o.lines - pad,
                border = "rounded",
            }
        end,
        winblend = 20,
    },
})

local notify_toast = notify.make_notify({
    ERROR = { duration = 8000 },
    WARN = { duration = 5000 },
    INFO = { duration = 3000 },
})

vim.notify = function(msg, level, opts)
    opts = opts or {}
    if opts.title and opts.title ~= "" then msg = opts.title .. "\n" .. msg end
    return notify_toast(msg, level)
end

vim.api.nvim_create_user_command(
    "Notifications",
    function() notify.show_history() end,
    { desc = "Show notification history" }
)
