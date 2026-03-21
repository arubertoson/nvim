local which = "supermaven"

if which ~= "supermaven" then
    local neo_ok, neo = pcall(require, "neocodeium")
    if neo_ok then
        vim.api.nvim_create_autocmd("User", {
            pattern = "BlinkCmpMenuOpen",
            callback = function()
                if vim.api.nvim_get_mode().mode == "c" then return end

                neo.clear()
            end,
        })

        neo.setup({
            filetypes = {
                TelescopePrompt = false,
            },
            filter = function(bufnr)
                local blink_ok, blink = pcall(require, "blink.cmp")
                if blink_ok and blink.is_visible() then
                    vim.log.info("blink is visible so skipping neocodeium")
                    return false
                end

                local name = vim.api.nvim_buf_get_name(bufnr)
                if name:match("%.env$") then
                    vim.log.info("env file so skipping neocodeium")
                    return false
                end

                return true
            end,
        })

        return
    end
end

local supermaven = require("supermaven-nvim")
local preview = require("supermaven-nvim.completion_preview")

supermaven.setup({
    disable_keymaps = true,
    condition = function()
        local name = vim.api.nvim_buf_get_name(0)
        if name:match("%.env$") then
            vim.log.info("env file so skipping inlay completion")
            return false
        end
    end,
})

vim.api.nvim_create_autocmd("User", {
    pattern = "BlinkCmpMenuOpen",
    callback = function()
        local preview = require("supermaven-nvim.completion_preview")
        preview.on_dispose_inlay()
    end,
})

vim.keymap.set(
    "i",
    "<c-t>",
    function() require("supermaven-nvim.completion_preview").on_dispose_inlay() end
)

-- local function accept_line()
--     local data = preview:accept_completion_text(false)
--     local newline = data.completion_text:find("\n", 1, true)
--     if newline then
--         data.completion_text = data.completion_text:sub(1, newline - 1)
--     end
--     -- paste the edited text (copied from on_accept_suggestion)
--     local cursor = vim.api.nvim_win_get_cursor(0)
--     local range = {
--         start = {
--             line = cursor[1] - 1,
--             character = math.max(cursor[2] - data.prior_delete, 0),
--         },
--         ["end"] = { line = cursor[1] - 1, character = vim.fn.col("$") },
--     }
--     vim.lsp.util.apply_text_edits(
--         { { range = range, newText = data.completion_text } },
--         0,
--         "utf-8"
--     )
--     vim.api.nvim_win_set_cursor(
--         0,
--         { cursor[1], cursor[2] + #data.completion_text }
--     )
-- end
