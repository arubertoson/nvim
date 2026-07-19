---@module "aru.picker"
--- Shared picker presentation helpers.

local custom = require("aru.custom")

local M = {}

local item_padding = "  "
local diagnostic_ns = vim.api.nvim_create_namespace("aru_picker_diagnostics")

function M.window_config()
    local has_tabline = vim.o.showtabline == 2
        or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
    local has_statusline = vim.o.laststatus > 0
    local max_height = vim.o.lines
        - vim.o.cmdheight
        - (has_tabline and 1 or 0)
        - (has_statusline and 1 or 0)

    local height = math.floor(0.7 * max_height)
    local width = math.min(math.floor(0.8 * vim.o.columns), 75)

    return {
        anchor = "NW",
        border = custom.border or "rounded",
        height = height,
        width = width,
        row = math.floor(0.5 * (max_height - height)) + (has_tabline and 1 or 0),
        col = math.floor(0.5 * (vim.o.columns - width)),
    }
end

local function item_text(item)
    if type(item) == "string" then return item end
    if type(item) == "table" and type(item.text) == "string" then return item.text end
    return vim.inspect(item, { newline = " ", indent = "" })
end

local function pad_item(item)
    if type(item) ~= "table" then return item_padding .. item_text(item) end

    local copy = vim.deepcopy(item)
    copy.text = item_padding .. item_text(item)
    return copy
end

function M.show(buf_id, items, query, opts)
    local padded_items = vim.tbl_map(pad_item, items)
    require("mini.pick").default_show(buf_id, padded_items, query, opts)
end

function M.show_diagnostics(buf_id, items, query)
    M.show(buf_id, items, query)

    vim.api.nvim_buf_clear_namespace(buf_id, diagnostic_ns, 0, -1)

    local groups = {
        [vim.diagnostic.severity.ERROR] = "DiagnosticFloatingError",
        [vim.diagnostic.severity.WARN] = "DiagnosticFloatingWarn",
        [vim.diagnostic.severity.INFO] = "DiagnosticFloatingInfo",
        [vim.diagnostic.severity.HINT] = "DiagnosticFloatingHint",
    }

    for i, item in ipairs(items) do
        local group = groups[item.severity]
        if group then
            vim.api.nvim_buf_set_extmark(buf_id, diagnostic_ns, i - 1, 0, {
                line_hl_group = group,
                priority = 199,
            })
        end
    end
end

return M
