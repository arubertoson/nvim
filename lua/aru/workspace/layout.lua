---@module "aru.workspace.layout"
---Centered editing layout and its integration points for tool floats.

local log = require("aru.log")
local colors = require("aru.interface.colors")

local M = {}

local ok, nnp = pcall(require, "no-neck-pain")
if not ok then
    log.error("Failed to load no-neck-pain; its features are disabled", nnp)
    return
end

local default_width = 100
local markdown_width = 90
local separator_hl = "AruNoNeckPainSeparator"
local separator_winhighlight = ("WinSeparator:%s,VertSplit:%s"):format(separator_hl, separator_hl)
local saved_winhighlight = {}
local saved_psst_width = nil

local function is_enabled()
    return _G.NoNeckPain and _G.NoNeckPain.state and _G.NoNeckPain.state.enabled
end

---@param layout Psst.config.FloatLayout
function M.expand_for_tool_float(layout)
    if saved_psst_width or not is_enabled() then return end

    saved_psst_width = _G.NoNeckPain.config.width
    local side_margin = 3
    local border_columns = 2
    local float_space = layout.width + side_margin + border_columns
    local target_width = math.max(1, vim.o.columns - float_space * 2)
    nnp.resize(target_width)
end

function M.restore_after_tool_float()
    if not saved_psst_width then return end

    local width = saved_psst_width
    saved_psst_width = nil
    if is_enabled() then nnp.resize(width) end
end

---@param buf integer
---@return integer|nil
local function layout_window(buf)
    if not vim.api.nvim_buf_is_valid(buf) then return nil end
    if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "no-neck-pain" then return nil end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_get_config(win).relative == "" then return win end
    end
end

local function set_separator_highlight(win, value)
    if win and vim.api.nvim_win_is_valid(win) then vim.wo[win].winhighlight = value end
end

local function hide_separator(win)
    win = win or vim.api.nvim_get_current_win()
    saved_winhighlight[win] = saved_winhighlight[win] or vim.wo[win].winhighlight
    set_separator_highlight(win, separator_winhighlight)
end

local function restore_separators()
    for win, winhighlight in pairs(saved_winhighlight) do
        set_separator_highlight(win, winhighlight)
    end

    saved_winhighlight = {}
end

---@param buf integer
local function apply_layout_for_filetype(buf)
    if saved_psst_width or not is_enabled() then return end
    local win = layout_window(buf)
    if not win then return end

    hide_separator(win)

    local is_markdown = vim.bo[buf].filetype == "markdown"
    local is_sqlite_query = vim.b[buf].sqlite_scratch_query == true
    local target_width = is_markdown and markdown_width or default_width
    local center_buffer = is_markdown or is_sqlite_query
    local right_enabled = _G.NoNeckPain.config.buffers.right.enabled

    if right_enabled ~= center_buffer then nnp.toggle_side("right") end

    if _G.NoNeckPain.config.width ~= target_width then nnp.resize(target_width) end
end

local hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
local bg = colors.tohex(hl.bg)

vim.api.nvim_set_hl(0, separator_hl, { fg = bg, bg = bg })

nnp.setup({
    mappings = {},
    width = default_width,
    minSideBufferWidth = 0,
    autocmds = {
        enableOnTabEnter = true,
        skipEnteringNoNeckPainBuffer = true,
    },
    callbacks = {
        postEnable = function(state)
            vim.defer_fn(function() hide_separator(state.previously_focused_win) end, 50)
        end,
        postDisable = restore_separators,
    },
    buffers = {
        colors = {
            background = bg,
        },
        wo = {
            winhighlight = separator_winhighlight,
        },
        right = { enabled = false },
    },
})

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = vim.api.nvim_create_augroup("AruNoNeckPainFiletypeLayout", { clear = true }),
    callback = function(args)
        if not layout_window(args.buf) then return end
        vim.defer_fn(function() apply_layout_for_filetype(args.buf) end, 50)
    end,
})

-- For the first run we just want to apply the layout
vim.defer_fn(function()
    nnp.enable()
    apply_layout_for_filetype(vim.api.nvim_get_current_buf())
end, 0)

vim.keymap.set("n", "<leader>wo", function()
    nnp.toggle()
    local buf = vim.api.nvim_get_current_buf()
    vim.defer_fn(function() apply_layout_for_filetype(buf) end, 50)
end, { desc = "Toggle no-neck-pain" })

return M
