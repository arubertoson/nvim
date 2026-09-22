---@module "aru.interface.startup_reveal"
---Reveal a Neovim instance that was started in a detached tmux window.

local M = {}

local enabled = vim.env.ARU_NVIM_REVEAL == "tmux"
local revealed = false

function M.reveal()
    if not enabled or revealed then return end
    revealed = true

    local pane = assert(vim.env.TMUX_PANE, "detached startup requires a tmux pane")
    vim.system({ "tmux", "select-window", "-t", pane }, {}, function(result)
        if result.code == 0 then return end
        vim.schedule(
            function()
                vim.notify(
                    "Failed to reveal Neovim tmux window: " .. result.stderr,
                    vim.log.levels.ERROR
                )
            end
        )
    end)
end

function M.setup()
    if not enabled then return end

    vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("AruStartupReveal", { clear = true }),
        once = true,
        callback = function()
            -- Do not leave a successfully started instance hidden if layout setup is skipped.
            vim.defer_fn(M.reveal, 1000)
        end,
    })
end

return M
