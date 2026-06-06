local log = require("aru.log")

local M = {}

local function clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

function M.tohex(color) return string.format("#%06x", color) end

function M.shade_color(color, factor)
    if not color then return color end

    -- color is 0xRRGGBB
    local hex = string.format("%06x", color)
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)

    -- factor in [-1,1]; positive darkens, negative lightens
    local f = clamp(factor, -1, 1)
    local m = 1 + f

    r = math.floor(clamp(r * m, 0, 255))
    g = math.floor(clamp(g * m, 0, 255))
    b = math.floor(clamp(b * m, 0, 255))

    return tonumber(string.format("%02x%02x%02x", r, g, b), 16)
end

---@param base_group string
---@param target_group string
---@param opts { fg?: number, bg?: number }
---@return boolean
function M.shade_highlight(base_group, target_group, opts)
    local hl = vim.api.nvim_get_hl(0, { name = base_group, link = false })
    if not hl or (not hl.bg and not hl.fg) then
        log:debug("Could not find hlgroup %s", base_group)
        return false
    end

    local new_hl = {}
    for k, v in pairs(hl) do
        new_hl[k] = v
    end

    new_hl.bg = M.shade_color(new_hl.bg, opts.bg or 0.0)
    new_hl.fg = M.shade_color(new_hl.fg, opts.fg or 0.0)

    vim.api.nvim_set_hl(0, target_group, new_hl)
    return true
end

return M
