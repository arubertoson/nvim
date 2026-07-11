---@module "aru.nav"
---@brief Navigation entry point.
---
--- Navigation is split into focused subsystems:
--- - jump: semantic/local jump history and explicit file return stack
--- - active: small persisted working set of pinned files
--- - buffers: MRU loaded-buffer cache and pruning policy
---
--- This module wires those pieces together so the leaf modules can stay
--- independent of each other.

local M = {}

M.jump = require("aru.jump")
M.active = require("aru.nav.active")
M.buffers = require("aru.nav.buffers")

function M.setup()
    M.jump.setup()

    M.active.setup({
        before_select = function() M.jump.file_mark() end,
    })

    M.buffers.setup({
        is_pinned = function(path) return M.active.contains(path) end,
    })
end

return M
