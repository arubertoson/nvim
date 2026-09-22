local M = {}

--- Check if the current environment is running in a SSH shell
---@return boolean
function M.is_ssh_shell()
    return (vim.env.SSH_CLIENT ~= nil or vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_TTY ~= nil)
end

return M
