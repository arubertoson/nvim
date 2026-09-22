--[[
Statusline Runtime Contract and Anti-Patterns
=============================================

Context
  This statusline must be pure and cheap. It runs frequently, and sometimes
  while Neovim is under "textlock" (for example during ext-UI events like
  cmdline_show). During textlock, changing buffers or windows is forbidden.
  Violations throw E565: "Not allowed to change text or change window."

Hard Rules (TL;DR)
  1) No side effects in render paths
     - Do NOT call nvim_buf_set_lines, nvim_buf_set_text, nvim_set_current_win,
       nvim_open_win, nvim_win_set_cursor, or anything that might write to a
       buffer or change windows.
     - Do NOT log to buffers, create floats, or show notifications here.

  2) No blocking work in render paths
     - Do NOT call plenary.job():sync() or :wait().
     - Do NOT run shell commands synchronously.
     - The render function should only concatenate strings and read cached data.

  3) All expensive or mutating work must be done elsewhere
     - Use timers, autocmds, or scheduled callbacks to update shared state.
     - The statusline reads those values and formats them.

Safe Patterns

  Async shell commands (git, etc.):
    vim.system({ 'git', 'branch', '--show-current' }, { cwd = vim.uv.cwd(), text = true }, function(res)
      local branch = res.code == 0 and vim.trim(res.stdout) or ''
      vim.schedule(function()
        _G._status_git_branch = branch
        pcall(vim.cmd, 'redrawstatus')
      end)
    end)

  Cache refresh on events that make sense:
    local group = vim.api.nvim_create_augroup('status_cache', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'DirChanged', 'FocusGained' }, {
      group = group,
      callback = function()
        -- kick off async refresh here (like the git example above)
      end,
    })

  Native logging:
    -- In render paths, avoid logging entirely. Elsewhere vim.log safely owns
    -- file-backed writes without touching Neovim buffers.

  Guarding against textlock explicitly:
    local function in_textlock()
      if vim.in_fast_event() then return true end
      local m = vim.fn.mode()
      if m == 'c' or m == 'r' or m == '!' then return true end
      if vim.fn.getcmdwintype() ~= '' then return true end
      return false
    end

Do / Do Not

  Do:
    - Precompute status data outside of StatusLine.active().
    - Read buffer-local options with vim.api.nvim_get_option_value('modifiable', { buf = 0 }).
    - Use vim.fs for paths: joinpath, normalize, basename.
    - Use vim.uv.cwd() to anchor project-relative info.

  Do Not:
    - Spawn jobs or block during StatusLine.active().
    - Write to any buffer or move any window from StatusLine.active().
    - Log from StatusLine.active(). If you must debug, print to :messages sparingly
      or toggle a temporary lightweight string tracer that only appends to a Lua table.

Troubleshooting

  Symptom: E565 during cmdline or messages redraw
    - Cause: Some code in the render path (or a callback it triggers) is calling
      nvim_buf_set_lines or moving windows. Remove those calls or defer them.
    - Cause: Blocking job wait (plenary.job:sync or :wait) inside statusline.
      Replace with vim.system async and cache.

  Symptom: Statusline lags or stutters
    - Cause: Heavy computation in render. Move it to a cache on autocmds/timers.
    - Cause: Too many redrawstatus calls. Only call after cache changes.

Migration away from Plenary (statusline scope)
  - plenary.job -> vim.system (async) or vim.uv.spawn.
  - plenary.path/scandir -> vim.fs.* and vim.fs.dir.

Design principle
  Statusline functions format strings from previously prepared state. Nothing else.
  If a value might cause side effects or blocking work, it does not belong here.

]]
--

local colors = require("aru.interface.colors")
local config = require("aru.config")
local git = require("aru.workspace.git")
local log = require("aru.log")

local highlights = {
    mode = "StatusLineMode",
    normal = "StatusLine",
    selected = "Special",
    dim = "StatusLineNC",
    comment = "StatusLineComment",
}

local ok = colors.shade_highlight("Comment", highlights.comment, { fg = -0.25 })
if not ok then log.error("Failed to create highlight group", highlights.comment) end

---@param hlgroup string
---@param msg string
---@return string
local function hlstring(hlgroup, msg) return ("%%#%s#%s%%*"):format(hlgroup, msg) end

---@return string
local function mode() return hlstring(highlights.mode, vim.api.nvim_get_mode().mode) end

---@return string
local function lineinfo()
    local line_with_width = "%-0" .. 3 .. "l"
    local column_with_width = "%-0" .. 2 .. "c"

    return hlstring(highlights.dim, ("[%s:%s]"):format(line_with_width, column_with_width))
end

local state = {}

local StatusLine = {}

function StatusLine.inactive() return state.filetype or "-" end

function StatusLine.active()
    local mode_str = vim.api.nvim_get_mode().mode
    if mode_str == "t" or mode_str == "nt" then
        return table.concat({ " ", mode(), "%=", "%=", state.active_files or "-" })
    end

    return table.concat({
        state.workspace_branch or "-",
        state.buffer_lsp_and_filetype or "[-]",
        state.current_buffer or "-",
        "%=",
        "%=",
        state.active_files or "-",
        lineinfo(),
    }, " ")
end

_G.StatusLine = StatusLine
vim.opt.statusline = "%!v:lua.StatusLine.active()"

local statusline_augroup = vim.api.nvim_create_augroup("aru-statusline", { clear = true })

local inactive_filetypes = {
    fzf = true,
    lspinfo = true,
    lazy = true,
    netrw = true,
    qf = true,
}

vim.api.nvim_create_autocmd("FileType", {
    group = statusline_augroup,
    desc = "Select the statusline for the current filetype",
    callback = function()
        vim.opt_local.statusline = inactive_filetypes[vim.bo.filetype]
                and "%!v:lua.StatusLine.inactive()"
            or ""
    end,
})

local function current_root() return git.git_root(0) or vim.uv.cwd() or "" end

local function cache_branch(root, branch)
    if root ~= current_root() then return end

    state.workspace_root = root
    state.workspace_branch = hlstring(highlights.comment, branch or "-")
    vim.cmd.redrawstatus()
end

local function refresh_branch()
    local root = current_root()
    cache_branch(root, git.branch_for(root))
    git.refresh_branch(root)
end

vim.api.nvim_create_autocmd({ "DirChanged", "BufEnter", "VimEnter" }, {
    group = statusline_augroup,
    desc = "Update statusline Git scope",
    callback = refresh_branch,
})

vim.api.nvim_create_autocmd("User", {
    group = statusline_augroup,
    pattern = "AruGitBranchChanged",
    desc = "Update statusline after an asynchronous Git branch refresh",
    callback = function(event)
        local data = event.data
        if data then cache_branch(data.root, data.branch) end
    end,
})

local function refresh_current_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    local current_buffer = vim.api.nvim_buf_get_name(bufnr)
    local root = current_root()
    local relpath = vim.fs.relpath(root, current_buffer) or current_buffer
    local dirty = vim.api.nvim_get_option_value("modified", { buf = bufnr }) and "*" or ""

    state.current_buffer = hlstring(highlights.comment, ("%s%s"):format(relpath, dirty))
    vim.cmd.redrawstatus()
end

vim.api.nvim_create_autocmd(
    { "BufEnter", "BufWritePost", "TextChanged", "TextChangedI", "VimEnter" },
    {
        group = statusline_augroup,
        desc = "Update current file status",
        callback = refresh_current_buffer,
    }
)

vim.api.nvim_create_autocmd("OptionSet", {
    group = statusline_augroup,
    pattern = "modified",
    desc = "Update current file status after an explicit modified-option change",
    callback = refresh_current_buffer,
})

local function refresh_lsp_state()
    local bufnr = vim.api.nvim_get_current_buf()
    local lsp_active = #vim.lsp.get_clients({ bufnr = bufnr }) > 0 and "LSP" or ""
    local filetype = vim.bo[bufnr].filetype

    state.buffer_lsp_and_filetype = table.concat({
        hlstring(highlights.dim, "["),
        hlstring(highlights.comment, lsp_active),
        hlstring(highlights.comment, "."),
        hlstring(highlights.dim, filetype),
        hlstring(highlights.dim, "]"),
    })
    state.filetype = filetype
    vim.cmd.redrawstatus()
end

vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufEnter", "VimEnter" }, {
    group = statusline_augroup,
    desc = "Update statusline LSP and filetype state",
    callback = refresh_lsp_state,
})

local function refresh_active_files()
    local ok, active = pcall(function() return require("tracks").active end)
    if not ok then return end

    local slots = {}
    local current_path = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
    local items = active.items()
    for i = 1, #config.navigation.active_file_keys do
        local item = items[i]
        local content = ""
        if item then
            local color = item.path == current_path and highlights.dim or highlights.comment
            content = hlstring(color, vim.fs.basename(item.path))
        end

        slots[#slots + 1] = hlstring(highlights.comment, ("[%d:"):format(i))
        slots[#slots + 1] = content
        slots[#slots + 1] = hlstring(highlights.comment, "]")
        slots[#slots + 1] = " "
    end

    state.active_files = table.concat(slots)
    vim.cmd.redrawstatus()
end

vim.api.nvim_create_autocmd("User", {
    group = statusline_augroup,
    pattern = "TracksActiveUpdated",
    desc = "Update active-file slots for statusline",
    callback = refresh_active_files,
})
vim.api.nvim_create_autocmd({ "BufEnter", "VimEnter" }, {
    group = statusline_augroup,
    desc = "Update active-file slots for statusline",
    callback = refresh_active_files,
})
