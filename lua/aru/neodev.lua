---@module "aru.neodev"
---
---@brief
--- Tiny Neovim Lua scratch runner for developing against the live editor state.

local M = {}

-- Global print function for debugging
_G.P = function(...)
    -- Inspect all arguments
    local objects = vim.tbl_map(vim.inspect, { ... })
    local lines = vim.split(table.concat(objects, "\n"), "\n")

    -- Create a true scratch buffer (unlisted, no file)
    local buf = vim.api.nvim_create_buf(false, true)

    -- Dump the lines into the buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Set buffer options: wipe out when hidden, treat as Lua for syntax highlighting
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "lua"

    -- Open a vertical split and set the buffer
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)
end

local state = {
    scratch_buf = nil,
    output_buf = nil,
    scratch_win = nil,
    output_win = nil,
    last_chunk = nil,
}

local function valid_buf(buf) return buf and vim.api.nvim_buf_is_valid(buf) end

local function valid_win(win) return win and vim.api.nvim_win_is_valid(win) end

local function make_buf(name, ft)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = ft or ""
    vim.api.nvim_buf_set_name(buf, name)
    return buf
end

local function append_output(lines)
    if not valid_buf(state.output_buf) then return end

    if type(lines) == "string" then lines = vim.split(lines, "\n", { plain = true }) end

    vim.bo[state.output_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.output_buf, -1, -1, false, lines)
    vim.bo[state.output_buf].modifiable = false

    if valid_win(state.output_win) then
        local count = vim.api.nvim_buf_line_count(state.output_buf)
        vim.api.nvim_win_set_cursor(state.output_win, { count, 0 })
    end
end

local function clear_output()
    if not valid_buf(state.output_buf) then return end

    vim.bo[state.output_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, {})
    vim.bo[state.output_buf].modifiable = false
end

local function inspect_lines(...)
    local objects = {}
    for i = 1, select("#", ...) do
        objects[i] = vim.inspect(select(i, ...))
    end

    return vim.split(table.concat(objects, "\n"), "\n", { plain = true })
end

local function print_lines(...)
    local objects = {}
    for i = 1, select("#", ...) do
        objects[i] = tostring(select(i, ...))
    end

    return { table.concat(objects, "\t") }
end

local function pack(...) return { n = select("#", ...), ... } end

local function ensure_buffers()
    if not valid_buf(state.scratch_buf) then
        state.scratch_buf = make_buf("NeoDev Lua Scratch", "lua")
    end

    if not valid_buf(state.output_buf) then
        state.output_buf = make_buf("NeoDev Output", "lua")
        vim.bo[state.output_buf].modifiable = false
    end
end

local function run_chunk(chunk, label)
    ensure_buffers()
    clear_output()

    if not chunk or chunk == "" then
        append_output("empty chunk")
        return
    end

    state.last_chunk = { chunk = chunk, label = label }

    local fn, load_err = load(chunk, label or "NeoDev", "t", _G)
    if not fn then
        append_output(load_err)
        return
    end

    local old_print = _G.print
    local old_vim_print = vim.print
    local old_P = _G.P

    _G.print = function(...) append_output(print_lines(...)) end

    vim.print = function(...)
        append_output(inspect_lines(...))
        return ...
    end

    _G.P = vim.print

    local results = pack(xpcall(fn, debug.traceback))

    _G.print = old_print
    vim.print = old_vim_print
    _G.P = old_P

    local ok = results[1]
    if not ok then
        append_output(results[2])
        return
    end

    if results.n > 1 then
        append_output("=>")
        append_output(inspect_lines(unpack(results, 2, results.n)))
    end
end

local function whole_buffer()
    local lines = vim.api.nvim_buf_get_lines(state.scratch_buf, 0, -1, false)
    return table.concat(lines, "\n")
end

local function current_line()
    local row = vim.api.nvim_win_get_cursor(state.scratch_win)[1] - 1
    return vim.api.nvim_buf_get_lines(state.scratch_buf, row, row + 1, false)[1]
end

local function visual_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    local sr, sc = start_pos[2] - 1, start_pos[3] - 1
    local er, ec = end_pos[2] - 1, end_pos[3]

    if er < sr or (er == sr and ec < sc) then
        sr, sc, er, ec = er, ec, sr, sc
    end

    local lines = vim.api.nvim_buf_get_text(state.scratch_buf, sr, sc, er, ec, {})
    return table.concat(lines, "\n")
end

local function close_win(win)
    if valid_win(win) then vim.api.nvim_win_close(win, true) end
end

local function delete_buf(buf)
    if valid_buf(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
end

function M.close()
    close_win(state.output_win)
    close_win(state.scratch_win)
    delete_buf(state.output_buf)
    delete_buf(state.scratch_buf)

    state.scratch_buf = nil
    state.output_buf = nil
    state.scratch_win = nil
    state.output_win = nil
    state.last_chunk = nil
end

local function set_scratch_keymaps()
    local opts = function(desc) return { buffer = state.scratch_buf, silent = true, desc = desc } end

    vim.keymap.set(
        "n",
        "<leader>rr",
        function() run_chunk(whole_buffer(), "NeoDev scratch") end,
        opts("NeoDev run buffer")
    )

    vim.keymap.set(
        "n",
        "<leader>rl",
        function() run_chunk(current_line(), "NeoDev line") end,
        opts("NeoDev run line")
    )

    vim.keymap.set(
        "x",
        "<leader>rs",
        function() run_chunk(visual_selection(), "NeoDev selection") end,
        opts("NeoDev run selection")
    )

    vim.keymap.set("n", "<leader>re", function()
        if not state.last_chunk then
            clear_output()
            append_output("no previous chunk")
            return
        end

        run_chunk(state.last_chunk.chunk, state.last_chunk.label)
    end, opts("NeoDev rerun last chunk"))

    vim.keymap.set("n", "<leader>rq", M.close, opts("NeoDev close"))
end

function M.open()
    ensure_buffers()

    if valid_win(state.scratch_win) and valid_win(state.output_win) then
        vim.api.nvim_set_current_win(state.scratch_win)
        return
    end

    if valid_win(state.scratch_win) then
        vim.api.nvim_set_current_win(state.scratch_win)
    elseif valid_win(state.output_win) then
        vim.api.nvim_set_current_win(state.output_win)
        vim.cmd("close")
    end

    local width = math.max(40, math.floor(vim.o.columns / 3))

    if not valid_win(state.scratch_win) then
        vim.cmd(("botright vertical %dnew"):format(width))
        state.scratch_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(state.scratch_win, state.scratch_buf)
        vim.api.nvim_win_set_width(state.scratch_win, width)
    end

    local total_height = vim.api.nvim_win_get_height(state.scratch_win)
    local output_height = math.max(6, math.floor(total_height / 3))

    vim.api.nvim_set_current_win(state.scratch_win)
    vim.cmd(("belowright %dnew"):format(output_height))
    state.output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.output_win, state.output_buf)
    vim.api.nvim_win_set_height(state.output_win, output_height)

    set_scratch_keymaps()
    vim.api.nvim_set_current_win(state.scratch_win)
end

function M.setup()
    vim.api.nvim_create_user_command("LuaScratch", M.open, {})
    vim.api.nvim_create_user_command("LuaScratchClose", M.close, {})
end

return M
