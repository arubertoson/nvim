---@module "aru.tools.lua_scratch"
---
---@brief
--- Tiny Neovim Lua scratch runner for developing against the live editor state.

local M = {}

---@class AruLuaScratch.Session
---@field scratch_buf integer
---@field output_buf integer
---@field scratch_win integer?
---@field output_win integer?

---@class AruLuaScratch.State
---@field session AruLuaScratch.Session?
---@field last_chunk { chunk: string, label: string? }?

---@type AruLuaScratch.State
local state = {
    session = nil,
    last_chunk = nil,
}

local function inspect_lines(...)
    local objects = {}
    for i = 1, select("#", ...) do
        objects[i] = vim.inspect((select(i, ...)))
    end

    return vim.split(table.concat(objects, "\n"), "\n", { plain = true })
end

-- Global print function for debugging.
_G.P = function(...)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, inspect_lines(...))
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "lua"

    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
end

---@param buf integer?
---@return boolean
local function valid_buf(buf) return buf ~= nil and vim.api.nvim_buf_is_valid(buf) end

---@param win integer?
---@return boolean
local function valid_win(win) return win ~= nil and vim.api.nvim_win_is_valid(win) end

---@param name string
---@param ft string
---@return integer
local function make_buf(name, ft)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = ft
    vim.api.nvim_buf_set_name(buf, name)
    return buf
end

---@param buf integer
---@param preferred integer?
---@return integer?
local function window_for_buffer(buf, preferred)
    if not valid_buf(buf) then return nil end

    if valid_win(preferred) and vim.api.nvim_win_get_buf(preferred) == buf then
        return preferred
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if vim.api.nvim_win_get_config(win).relative == "" then return win end
    end

    return nil
end

---@return AruLuaScratch.Session
local function ensure_session()
    local session = state.session
    if not session then
        session = {
            scratch_buf = make_buf("Lua Scratch", "lua"),
            output_buf = make_buf("Lua Scratch Output", "lua"),
            scratch_win = nil,
            output_win = nil,
        }
        vim.bo[session.output_buf].modifiable = false
        state.session = session
        return session
    end

    if not valid_buf(session.scratch_buf) then
        session.scratch_buf = make_buf("Lua Scratch", "lua")
        session.scratch_win = nil
    end

    if not valid_buf(session.output_buf) then
        session.output_buf = make_buf("Lua Scratch Output", "lua")
        vim.bo[session.output_buf].modifiable = false
        session.output_win = nil
    end

    session.scratch_win = window_for_buffer(session.scratch_buf, session.scratch_win)
    session.output_win = window_for_buffer(session.output_buf, session.output_win)

    return session
end

---@param session AruLuaScratch.Session
---@param lines string|string[]
local function append_output(session, lines)
    if not valid_buf(session.output_buf) then return end

    if type(lines) == "string" then lines = vim.split(lines, "\n", { plain = true }) end

    vim.bo[session.output_buf].modifiable = true
    vim.api.nvim_buf_set_lines(session.output_buf, -1, -1, false, lines)
    vim.bo[session.output_buf].modifiable = false

    session.output_win = window_for_buffer(session.output_buf, session.output_win)
    if session.output_win then
        local count = vim.api.nvim_buf_line_count(session.output_buf)
        vim.api.nvim_win_set_cursor(session.output_win, { count, 0 })
    end
end

---@param session AruLuaScratch.Session
local function clear_output(session)
    vim.bo[session.output_buf].modifiable = true
    vim.api.nvim_buf_set_lines(session.output_buf, 0, -1, false, {})
    vim.bo[session.output_buf].modifiable = false
end

local function print_lines(...)
    local objects = {}
    for i = 1, select("#", ...) do
        objects[i] = tostring((select(i, ...)))
    end

    return { table.concat(objects, "\t") }
end

local function pack(...) return { n = select("#", ...), ... } end

---@param chunk string?
---@param label string?
local function run_chunk(chunk, label)
    M.open()
    local session = assert(state.session)
    clear_output(session)

    if not chunk or chunk == "" then
        append_output(session, "empty chunk")
        return
    end

    state.last_chunk = { chunk = chunk, label = label }

    local fn, load_err = load(chunk, label or "Lua Scratch", "t", _G)
    if not fn then
        append_output(session, load_err)
        return
    end

    local old_print = _G.print
    local old_vim_print = vim.print
    local old_P = _G.P

    _G.print = function(...) append_output(session, print_lines(...)) end

    vim.print = function(...)
        append_output(session, inspect_lines(...))
        return ...
    end

    _G.P = vim.print

    local results = pack(xpcall(fn, debug.traceback))

    _G.print = old_print
    vim.print = old_vim_print
    _G.P = old_P

    local ok = results[1]
    if not ok then
        append_output(session, results[2])
        return
    end

    if results.n > 1 then
        append_output(session, "=>")
        append_output(session, inspect_lines(unpack(results, 2, results.n)))
    end
end

---@return string
local function whole_buffer()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    return table.concat(lines, "\n")
end

---@return string
local function current_line() return vim.api.nvim_get_current_line() end

---@return string
local function visual_selection()
    local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), {
        type = vim.fn.mode(),
    })
    return table.concat(lines, "\n")
end

---@param win integer
---@return boolean
local function can_close_window(win)
    if vim.api.nvim_win_get_config(win).relative ~= "" then return true end
    return #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)) > 1
end

---@param win integer?
---@param buf integer
local function close_owned_window(win, buf)
    win = window_for_buffer(buf, win)
    if win and can_close_window(win) then vim.api.nvim_win_close(win, true) end
end

---@param buf integer
local function delete_buf(buf)
    if valid_buf(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end

function M.close()
    local session = state.session
    state.session = nil
    state.last_chunk = nil
    if not session then return end

    close_owned_window(session.output_win, session.output_buf)
    close_owned_window(session.scratch_win, session.scratch_buf)
    delete_buf(session.output_buf)
    delete_buf(session.scratch_buf)
end

---@param session AruLuaScratch.Session
local function set_scratch_keymaps(session)
    local function opts(desc) return { buffer = session.scratch_buf, silent = true, desc = desc } end

    vim.keymap.set(
        "n",
        "<leader>rr",
        function() run_chunk(whole_buffer(), "Lua Scratch buffer") end,
        opts("Lua Scratch run buffer")
    )

    vim.keymap.set(
        "n",
        "<leader>rl",
        function() run_chunk(current_line(), "Lua Scratch line") end,
        opts("Lua Scratch run line")
    )

    vim.keymap.set(
        "x",
        "<leader>rs",
        function() run_chunk(visual_selection(), "Lua Scratch selection") end,
        opts("Lua Scratch run selection")
    )

    vim.keymap.set("n", "<leader>re", function()
        if not state.last_chunk then
            M.open()
            local current = assert(state.session)
            clear_output(current)
            append_output(current, "no previous chunk")
            return
        end

        run_chunk(state.last_chunk.chunk, state.last_chunk.label)
    end, opts("Lua Scratch rerun last chunk"))

    vim.keymap.set("n", "<leader>rq", M.close, opts("Lua Scratch close"))
end

---@param session AruLuaScratch.Session
local function create_scratch_window(session)
    vim.cmd("botright vsplit")
    session.scratch_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(session.scratch_win, session.scratch_buf)

    local desired = math.max(40, math.floor(vim.o.columns / 3))
    local available = math.max(1, vim.o.columns - vim.o.winminwidth - 1)
    vim.api.nvim_win_set_width(session.scratch_win, math.min(desired, available))
end

---@param session AruLuaScratch.Session
local function create_output_window(session)
    vim.api.nvim_set_current_win(assert(session.scratch_win))
    local scratch_height = vim.api.nvim_win_get_height(session.scratch_win)

    vim.cmd("belowright split")
    session.output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(session.output_win, session.output_buf)

    local desired = math.max(6, math.floor(scratch_height / 3))
    local available = math.max(1, scratch_height - vim.o.winminheight - 1)
    vim.api.nvim_win_set_height(session.output_win, math.min(desired, available))
end

function M.open()
    local session = ensure_session()

    if session.scratch_win and session.output_win then
        vim.api.nvim_set_current_win(session.scratch_win)
        return
    end

    -- If only the output window survived, reuse that owned window for the
    -- scratch buffer and reconstruct output below it. Output is ephemeral.
    if not session.scratch_win and session.output_win then
        vim.api.nvim_win_set_buf(session.output_win, session.scratch_buf)
        session.scratch_win = session.output_win
        session.output_win = nil

        if not valid_buf(session.output_buf) then
            session.output_buf = make_buf("Lua Scratch Output", "lua")
            vim.bo[session.output_buf].modifiable = false
        end
    end

    if not session.scratch_win then create_scratch_window(session) end
    if not session.output_win then create_output_window(session) end

    set_scratch_keymaps(session)
    vim.api.nvim_set_current_win(session.scratch_win)
end

function M.setup()
    vim.api.nvim_create_user_command("LuaScratch", M.open, {})
    vim.api.nvim_create_user_command("LuaScratchClose", M.close, {})
end

return M
