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

  Logger safety (never write during fast events):
    local function logger_safe_write(fn)
      if vim.in_fast_event() or vim.fn.getcmdwintype() ~= '' then return end
      vim.schedule(function() pcall(fn) end)
    end
    -- In render paths, avoid logging entirely. Outside, wrap writes with logger_safe_write.

  Guarding against textlock explicitly:
    local function in_textlock()
      if vim.in_fast_event() then return true end
      local m = vim.fn.mode()
      if m == 'c' or m == 'r' or m == '!' then return true end
      if vim.fn.getcmdwintype() ~= '' then return true end
      return false
    end

  Queue-and-flush for log buffers (optional pattern):
    -- Queue lines while in_textlock() is true.
    -- Use vim.schedule or vim.defer_fn with small backoff to flush later.
    -- Cap retries to avoid infinite loops.
    -- Never call nvim_win_set_cursor from the logger.

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

TODO: This module is marked for future rewrite due to:
- Ad-hoc state management across autocmds
- Git branch query duplication with aru.state.git
- Potential race conditions with async git system() calls
For now: it works, don't touch unless broken
]]
--

local colors = require("aru.colors")
local log = require("aru.log")

local highlights = {
    mode = "StatusLineMode",
    normal = "StatusLine",
    selected = "Special",
    dim = "StatusLineNC",
    comment = "StatusLineComment",
}

local ok = colors.shade_highlight("Comment", highlights.comment, { fg = -0.25 })
if not ok then
    log:error("Failed to create hlgroup %s", highlights.comment)
end

---@param hlgroup string
---@param msg string
---@return string
local function hlstring(hlgroup, msg)
    return ("%%#%s#%s%%*"):format(hlgroup, msg)
end

---@return string
local function mode()
    return hlstring(highlights.mode, vim.api.nvim_get_mode().mode)
end

---@return string
local function lineinfo()
    local line_with_width = "%-0" .. 3 .. "l"
    local column_with_width = "%-0" .. 2 .. "c"

    return hlstring(
        highlights.dim,
        ("[%s:%s]"):format(line_with_width, column_with_width)
    )
end

StatusLine = {}

StatusLine.inactive = function()
    return table.concat({
        StatusLine.filetype or "-",
    })
end

StatusLine.cache = function(attr, value) StatusLine[attr] = value end

StatusLine.active = function()
    local mode_str = vim.api.nvim_get_mode().mode
    if mode_str == "t" or mode_str == "nt" then
        return table.concat({
            " ",
            mode(),
            "%=",
            "%=",
            StatusLine.harpoon_state or "-",
        })
    end
    local statusline = {
        StatusLine.workspace_branch or "-",
        StatusLine.buffer_lsp_and_filetype or "[-]",
        StatusLine.current_buffer or "-",
        "%=",
        "%=",
        StatusLine.harpoon_state or "-",
        lineinfo(),
    }

    return table.concat(statusline, " ")
end

vim.opt.statusline = "%!v:lua.StatusLine.active()"

-- ============================================================
-- Statusline autocmds
-- ============================================================

local statusline_augroup =
    vim.api.nvim_create_augroup("aru-statusline", { clear = true })

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "FileType" }, {
    group = statusline_augroup,
    pattern = {
        "fzf",
        "lspinfo",
        "lazy",
        "netrw",
        "qf",
    },
    callback = function()
        vim.opt_local.statusline = "%!v:lua.StatusLine.inactive()"
    end,
})

-- TODO: switch these things out with gitisngs, it was for experimental purposes.
-- this whole section can also potentially be improved by extracting functionality
-- into functions and reduce the caught events. BufEnter is an event the whole
-- statusline reacts to, we can bundle that. But let's stay simple for now
vim.api.nvim_create_autocmd({ "DirChanged", "BufEnter", "VimEnter" }, {
    group = statusline_augroup,
    callback = function()
        -- XXX: this should be cached somewhere :)
        local root = vim.fs.root(0, { ".git" })
        if not root then root = vim.uv.cwd() or "" end
        local branch = require("aru.state.git").branch_for(root) or "-"

        -- Ensure that our cache is up to date. Launc in a schedule to avoid blocking.
        vim.schedule(function()
            local branch_hl = hlstring(highlights.comment, branch or "no-head")

            StatusLine.cache("workspace_root", root)
            StatusLine.cache("workspace_branch", branch_hl)

            vim.cmd.redrawstatus()
        end)
    end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "VimEnter" }, {
    group = statusline_augroup,
    desc = "Update and cache current filename for statusline",
    callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        local current_buffer = vim.api.nvim_buf_get_name(bufnr)
        local root = StatusLine.workspace_root
            or vim.fs.root(bufnr, { ".git" })
            or vim.uv.cwd()
            or ""

        local relpath = root and vim.fs.relpath(root, current_buffer)
            or current_buffer
        local buf_dirty = vim.api.nvim_get_option_value(
            "modified",
            { buf = bufnr }
        ) and "*" or ""

        vim.schedule(function()
            StatusLine.cache(
                "current_buffer",
                hlstring(
                    highlights.comment,
                    ("%s%s"):format(relpath, buf_dirty)
                )
            )

            vim.cmd.redrawstatus()
        end)
    end,
})

vim.api.nvim_create_autocmd(
    { "LspAttach", "LspDetach", "BufEnter", "VimEnter" },
    {
        group = statusline_augroup,
        desc = "Show if LSP is active in the current buffer/workspace and what filetype it is",
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            local clients = vim.lsp.get_clients({ bufnr = bufnr })

            local lsp_active = (#clients > 0 and "LSP" or "")
            local filetype = vim.bo.filetype

            local parts = {}
            table.insert(parts, hlstring(highlights.dim, "["))
            table.insert(parts, hlstring(highlights.comment, lsp_active))
            table.insert(parts, hlstring(highlights.comment, "."))
            table.insert(parts, hlstring(highlights.dim, filetype))
            table.insert(parts, hlstring(highlights.dim, "]"))

            local buffer_lsp_and_filetype = table.concat(parts)

            vim.schedule(function()
                StatusLine.cache(
                    "buffer_lsp_and_filetype",
                    buffer_lsp_and_filetype
                )
                StatusLine.cache("lsp_active", lsp_active)
                StatusLine.cache("filetype", filetype)

                vim.cmd.redrawstatus()
            end)
        end,
    }
)

local function refresh_harpoon_state(event)
    local ok, harpoon = pcall(require, "harpoon")
    if not ok then return end

    local list = harpoon:list()
    local slots = {}
    local cwd = vim.uv.cwd() or ""

    local cur_abs = vim.fs.normalize(vim.api.nvim_buf_get_name(event.buf))

    for i = 1, 3 do
        local item = list.items[i]
        local content = ""

        if item then
            local filename = vim.fs.basename(item.value)

            -- We need to compare the paths, harpoon uses relateive paths compared
            -- to the cwd e.g. /home/dev/lua/core.lua => lua/core.lua
            local item_abs = vim.fs.normalize(vim.fs.joinpath(cwd, item.value))
            local is_selected = (item_abs == cur_abs)

            local color = is_selected and highlights.dim or highlights.comment
            content = hlstring(color, filename)
        end

        table.insert(slots, hlstring(highlights.comment, ("[%d:"):format(i)))
        table.insert(slots, content)
        table.insert(slots, hlstring(highlights.comment, "]"))
        table.insert(slots, " ")
    end

    vim.schedule(function()
        StatusLine.cache("harpoon_state", table.concat(slots, ""))

        vim.cmd.redrawstatus()
    end)
end

---To keep visual track harpoon we add three slots to the statusline.
---It will have different highlight for selected and inactive,
---and will show the current file name.
vim.api.nvim_create_autocmd("User", {
    group = statusline_augroup,
    pattern = { "HarpoonStateUpdated" },
    desc = "Update and cache current filename for statusline",
    callback = refresh_harpoon_state,
})
vim.api.nvim_create_autocmd({ "BufEnter", "VimEnter" }, {
    group = statusline_augroup,
    desc = "Update and cache current filename for statusline",
    callback = refresh_harpoon_state,
})
