local log = require("aru.log")

if vim.g.__aru_loaded_continue == 1 then return end
vim.api.nvim_set_var("__aru_loaded_continue", 1)

require("continue").setup({
    hooks = {
        pre_save = function()
            local ok, nnp = pcall(require, "no-neck-pain")
            if not ok then
                log:error(
                    ("Failed to load no-neck-pain: %s, continue hook for no-neck-pain won't be ran."):format(
                        nnp
                    )
                )
                return
            end

            log:debug("Pre save hook for continue ran, disabling no-neck-pain.")
            require("no-neck-pain.main").disable()
        end,
    },
})
