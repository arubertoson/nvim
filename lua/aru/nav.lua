---@module "aru.nav"
---@brief Navigation entry point.
---
--- Navigation is split into focused subsystems:
--- - point_jump: semantic point history within a buffer
--- - file_jump: automatic, restorable file-visit history
--- - active: small persisted working set of pinned files
--- - buffer_cache: MRU loaded-buffer cache and pruning policy
---
--- This module wires those pieces together so the leaf modules can stay
--- independent of each other.

local M = {}

M.point_jump = require("aru.nav.point_jump")
M.file_jump = require("aru.nav.file_jump")
M.active = require("aru.nav.active")
M.buffer_cache = require("aru.nav.buffer_cache")

function M.setup()
    M.point_jump.setup()
    M.file_jump.setup()
    M.active.setup()

    M.buffer_cache.setup({
        is_pinned = function(path) return M.active.contains(path) end,
    })
end

return M
