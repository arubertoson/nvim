---@module "aru.agent.prompt"
---Owns the floating agent prompt and its derived Inline Reference preview.

local M = {}

local constants = require("aru.agent.constants")
local channels = require("aru.agent.channels")
local collect = require("aru.agent.collect")
local context = require("aru.agent.context")
local payload = require("aru.agent.payload")
local session = require("aru.agent.session")
local ui = require("aru.agent.ui")

---@class aru.agent.prompt.Deps
---@field send fun(request: aru.agent.Request): boolean
---@field collect aru.agent.collect.Type[]|nil
---@field cwd string
---@field invocation aru.agent.InvocationState

local PROMPT_LAYOUT = constants.UI.PROMPT
local PROMPT_MIN_ROWS = PROMPT_LAYOUT.MIN_ROWS
local PROMPT_MAX_ROWS = PROMPT_LAYOUT.MAX_ROWS
local PROMPT_LEFT_PADDING = PROMPT_LAYOUT.LEFT_PADDING
local PLACEHOLDER_TEXT = "<user types here>"
local PROMPT_NEWLINE_KEY = "<M-CR>"
local PROMPT_CLOSE_KEY = "<Esc>"
local PREVIEW_DELAY_MS = 90

local BLOCK_COLLECT = { collect.COLLECT.BLOCK }

---@class aru.agent.prompt.State
---@field buf integer
---@field win integer
---@field footer_ns integer
---@field reference_ns integer
---@field augroup integer
---@field timer uv.uv_timer_t
---@field refresh_id integer
---@field send fun(request: aru.agent.Request): boolean
---@field collect aru.agent.collect.Type[]
---@field cwd string
---@field invocation aru.agent.InvocationState
---@field build aru.agent.context.BuildResult|nil
---@field preview_win integer|nil
---@field preview_buf integer|nil

---@type aru.agent.prompt.State|nil
local _prompt_state = nil

---@param state aru.agent.prompt.State
---@return string
local function action_footer(state)
    local continuable, session_index = session.can_continue(state.cwd)
    if continuable then
        return ("[CR] continue S%d   [^CR] new session   [^G] generate   [^P] session   [^X] payload"):format(
            session_index
        )
    end
    return "[CR] read   [^CR] new session   [^G] generate   [^P] session   [^X] payload"
end

local function prompt_width()
    return math.min(PROMPT_LAYOUT.WIDTH, vim.o.columns - PROMPT_LAYOUT.BORDER_ROWS)
end

---@param buf integer
---@param width integer
local function prompt_content_rows(buf, width)
    local text_width = width - PROMPT_LEFT_PADDING
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local rows = 0
    for _, line in ipairs(lines) do
        local line_width = vim.fn.strdisplaywidth(line)
        rows = rows + math.max(1, math.ceil((line_width + 1) / text_width))
    end
    return math.max(1, math.min(rows, PROMPT_MAX_ROWS))
end

---@param buf integer
local function prompt_win_config(buf)
    local custom = require("aru.custom")
    local width = prompt_width()
    local content_rows = prompt_content_rows(buf, width)
    local height = math.max(PROMPT_MIN_ROWS, content_rows) + 2
    local available_lines = vim.o.lines - vim.o.cmdheight
    return {
        relative = "editor",
        row = math.max(0, math.floor((available_lines - height - PROMPT_LAYOUT.BORDER_ROWS) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width - PROMPT_LAYOUT.BORDER_ROWS) / 2)),
        width = width,
        height = height,
        style = constants.UI.STYLE_MINIMAL,
        border = custom.border or constants.UI.BORDER_ROUNDED,
        title = " prompt ",
        title_pos = constants.UI.TITLE_POS_LEFT,
        zindex = PROMPT_LAYOUT.ZINDEX,
    }
end

---@param item aru.agent.payload.ContextItem
local function context_label(item)
    if item.kind == "diagnostic" then return "diagnostic" end
    local name = item.path and vim.fs.basename(item.path) or item.kind
    if item.symbol then
        return ("%s#%s:%d-%d"):format(name, item.symbol, item.start_line, item.end_line)
    end
    if item.whole_file then return name end
    if item.start_line and item.end_line then
        return ("%s %s:%d-%d"):format(item.kind, name, item.start_line, item.end_line)
    end
    return name
end

---@param state aru.agent.prompt.State
---@param width integer
local function context_footer(state, width)
    if not state.build then return nil end
    local entries = {}
    for _, item in ipairs(state.build.context) do
        entries[#entries + 1] = context_label(item)
    end
    for _, ref in ipairs(state.build.references) do
        if ref.state == "editing" then
            entries[#entries + 1] = "…" .. ref.raw:sub(2)
        elseif ref.state == "unresolved" then
            entries[#entries + 1] = "?" .. ref.raw:sub(2)
        end
    end
    if #entries == 0 then return nil end

    local prefix = ("ctx %d"):format(#state.build.context)
    local visible = prefix
    for index, entry in ipairs(entries) do
        local suffix = " · " .. entry
        local remaining = #entries - index
        local overflow = remaining > 0 and (" · +%d"):format(remaining) or ""
        if vim.fn.strdisplaywidth(visible .. suffix .. overflow) > width then
            return visible .. (remaining + 1 > 0 and (" · +%d"):format(remaining + 1) or "")
        end
        visible = visible .. suffix
    end
    return visible
end

---@param state aru.agent.prompt.State
local function render_footer(state)
    local buf = state.buf
    local total = vim.api.nvim_buf_line_count(buf)
    local footer_idx = total - 1
    local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    local show_placeholder = total == 1 and first_line == ""

    local width = prompt_width()
    local content_rows = prompt_content_rows(buf, width)
    local virt_lines = {}
    local spacer_rows = math.max(1, PROMPT_MIN_ROWS - content_rows)
    for _ = 1, spacer_rows do
        virt_lines[#virt_lines + 1] = { { "", "Normal" } }
    end

    local summary = context_footer(state, width - PROMPT_LEFT_PADDING)
    if summary then
        virt_lines[#virt_lines + 1] = { { summary, constants.UI.HIGHLIGHT_COMMENT } }
    end

    local action = action_footer(state)
    local padding = math.max(0, width - PROMPT_LEFT_PADDING - vim.fn.strdisplaywidth(action))
    virt_lines[#virt_lines + 1] = {
        { string.rep(" ", padding) .. action, constants.UI.HIGHLIGHT_COMMENT },
    }

    local opts = { virt_lines = virt_lines, virt_lines_above = false }
    if show_placeholder then
        opts.virt_text = { { PLACEHOLDER_TEXT, constants.UI.HIGHLIGHT_COMMENT } }
        opts.virt_text_pos = "overlay"
    end

    vim.api.nvim_buf_clear_namespace(buf, state.footer_ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, state.footer_ns, footer_idx, 0, opts)
end

---@param state aru.agent.prompt.State
local function render_references(state)
    vim.api.nvim_buf_clear_namespace(state.buf, state.reference_ns, 0, -1)
    if not state.build then return end
    local highlights = {
        resolved = "Special",
        editing = constants.UI.HIGHLIGHT_COMMENT,
        unresolved = "DiagnosticError",
    }
    for _, ref in ipairs(state.build.references) do
        vim.api.nvim_buf_set_extmark(
            state.buf,
            state.reference_ns,
            ref.span.start_row,
            ref.span.start_col,
            {
                end_row = ref.span.end_row,
                end_col = ref.span.end_col,
                hl_group = highlights[ref.state],
            }
        )
    end
end

---@param state aru.agent.prompt.State
local function resize_prompt(state)
    if not vim.api.nvim_win_is_valid(state.win) then return end
    vim.api.nvim_win_set_config(state.win, prompt_win_config(state.buf))
    render_footer(state)
end

---@param buf integer
local function read_prompt_text(buf)
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

---@param state aru.agent.prompt.State
local function prompt_cursor(state)
    local cursor = vim.api.nvim_win_get_cursor(state.win)
    return { cursor[1] - 1, cursor[2] }
end

---@param state aru.agent.prompt.State
---@param authoritative boolean|nil
local function build_context(state, authoritative)
    return context.build({
        prompt = read_prompt_text(state.buf),
        cursor = authoritative and nil or prompt_cursor(state),
        cwd = state.cwd,
        invocation = state.invocation,
        collect = state.collect,
    })
end

---@param state aru.agent.prompt.State
local function refresh(state)
    if _prompt_state ~= state then return end
    if not vim.api.nvim_buf_is_valid(state.buf) or not vim.api.nvim_win_is_valid(state.win) then
        return
    end
    state.build = build_context(state)
    render_references(state)
    resize_prompt(state)
end

---@param state aru.agent.prompt.State
---@param immediate boolean
local function request_refresh(state, immediate)
    state.refresh_id = state.refresh_id + 1
    local refresh_id = state.refresh_id
    state.timer:stop()
    if immediate then
        refresh(state)
        return
    end
    state.timer:start(
        PREVIEW_DELAY_MS,
        0,
        vim.schedule_wrap(function()
            if _prompt_state == state and state.refresh_id == refresh_id then refresh(state) end
        end)
    )
end

local function close_prompt()
    if not _prompt_state then return end
    local state = _prompt_state
    _prompt_state = nil

    state.timer:stop()
    if not state.timer:is_closing() then state.timer:close() end
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
        vim.api.nvim_win_close(state.preview_win, true)
    end
    ui.close_win_buf(state.win, state.buf)
    vim.cmd("stopinsert")
end

---@param destination aru.agent.channels.Destination
---@param force_new_session boolean|nil
local function submit_prompt(destination, force_new_session)
    if not _prompt_state then return end
    local state = _prompt_state
    local prompt_text = read_prompt_text(state.buf)
    if prompt_text:match("^%s*$") then return end

    local built = build_context(state, true)
    state.build = built
    render_references(state)
    render_footer(state)
    if #built.blocking > 0 then
        local ref = built.blocking[1]
        vim.notify(("Cannot submit unresolved reference %s"):format(ref.raw), vim.log.levels.ERROR)
        return
    end

    local sent = state.send({
        destination = destination,
        force_new_session = force_new_session,
        collect = state.collect,
        context = built.context,
        prompt = prompt_text,
    })
    if sent then close_prompt() end
end

local function submit_float_read() submit_prompt(channels.DESTINATION.FLOAT, false) end
local function submit_float_new_session() submit_prompt(channels.DESTINATION.FLOAT, true) end

local function insert_prompt_newline()
    if not _prompt_state then return end
    local state = _prompt_state
    if not vim.api.nvim_buf_is_valid(state.buf) or not vim.api.nvim_win_is_valid(state.win) then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(state.win)
    local row, col = cursor[1], cursor[2]
    local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
    vim.api.nvim_buf_set_lines(state.buf, row - 1, row, false, {
        line:sub(1, col),
        line:sub(col + 1),
    })
    vim.api.nvim_win_set_cursor(state.win, { row + 1, 0 })
    request_refresh(state, true)
end

---@param invocation_buf integer
---@return integer[]
local function completion_bufnrs(invocation_buf)
    local bufnrs = {}
    local included = {}
    for _, item in ipairs(require("aru.nav.active").items()) do
        if vim.uv.fs_stat(item.path) then
            local bufnr = item.bufnr
            if not bufnr then bufnr = vim.fn.bufadd(item.path) end
            if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
            bufnrs[#bufnrs + 1] = bufnr
            included[bufnr] = true
        end
    end
    if require("aru.buf").is_normal_file(invocation_buf) and not included[invocation_buf] then
        bufnrs[#bufnrs + 1] = invocation_buf
    end
    return bufnrs
end

---@param state aru.agent.prompt.State
local function close_payload_preview(state)
    if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
        vim.api.nvim_win_close(state.preview_win, true)
    end
end

---@param state aru.agent.prompt.State
local function show_payload_preview(state)
    local built = build_context(state, true)
    state.build = built
    render_references(state)
    render_footer(state)

    close_payload_preview(state)
    local rendered = payload.render({
        prompt = read_prompt_text(state.buf),
        context = built.context,
    })
    local sections = {}
    if #built.blocking > 0 then
        local warnings = { "NOT PART OF PAYLOAD — unresolved inline references:" }
        for _, ref in ipairs(built.blocking) do
            warnings[#warnings + 1] = ("- %s: %s"):format(ref.raw, ref.error or ref.state)
        end
        sections[#sections + 1] = table.concat(warnings, "\n")
    end
    sections[#sections + 1] = rendered

    local preview_buf = ui.create_scratch_buf({
        filetype = constants.UI.FILETYPE_MARKDOWN,
        lines = vim.split(table.concat(sections, "\n\n"), "\n", { plain = true }),
    })
    vim.bo[preview_buf].modifiable = false
    local width = math.min(math.max(40, vim.o.columns - 12), 120)
    local height = math.min(math.max(8, vim.o.lines - 8), 35)
    local preview_win = vim.api.nvim_open_win(preview_buf, false, {
        relative = "editor",
        row = math.max(0, math.floor((vim.o.lines - height) / 2)),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        width = width,
        height = height,
        style = constants.UI.STYLE_MINIMAL,
        border = require("aru.custom").border or constants.UI.BORDER_ROUNDED,
        title = " payload ",
        title_pos = constants.UI.TITLE_POS_LEFT,
        zindex = PROMPT_LAYOUT.ZINDEX + 1,
    })
    state.preview_buf = preview_buf
    state.preview_win = preview_win

    local close = function()
        if _prompt_state == state then close_payload_preview(state) end
    end
    vim.keymap.set("n", "q", close, { buffer = preview_buf, silent = true })
    vim.keymap.set("n", "<Esc>", close, { buffer = preview_buf, silent = true })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = state.augroup,
        pattern = tostring(preview_win),
        once = true,
        callback = function()
            state.preview_win = nil
            state.preview_buf = nil
            vim.schedule(function()
                if _prompt_state == state and vim.api.nvim_win_is_valid(state.win) then
                    vim.api.nvim_set_current_win(state.win)
                    vim.cmd("startinsert")
                end
            end)
        end,
    })
    vim.api.nvim_set_current_win(preview_win)
end

---@param deps aru.agent.prompt.Deps
function M.open(deps)
    if _prompt_state then
        if vim.api.nvim_win_is_valid(_prompt_state.win) then
            vim.api.nvim_set_current_win(_prompt_state.win)
            return
        end
        close_prompt()
    end

    local invocation_buf = deps.invocation.bufnr
    local buf = ui.create_scratch_buf({ filetype = constants.UI.FILETYPE_PROMPT, lines = { "" } })
    vim.bo[buf].syntax = constants.UI.FILETYPE_MARKDOWN
    vim.b[buf].aru_agent_prompt = true
    vim.b[buf].aru_completion_cwd = deps.cwd
    vim.b[buf].aru_completion_invocation_buf = invocation_buf
    vim.b[buf].aru_completion_bufnrs = completion_bufnrs(invocation_buf)

    local win = vim.api.nvim_open_win(buf, true, prompt_win_config(buf))
    ui.apply_win_options(win, {
        wrap = true,
        linebreak = true,
        cursorline = false,
        foldcolumn = tostring(PROMPT_LEFT_PADDING),
        foldenable = false,
    })
    vim.api.nvim_win_set_cursor(win, { 1, 0 })

    local footer_ns = vim.api.nvim_create_namespace(constants.NAMESPACE.PROMPT_FOOTER)
    local reference_ns = vim.api.nvim_create_namespace(constants.NAMESPACE.PROMPT_REFERENCE)
    local augroup = vim.api.nvim_create_augroup(constants.AUGROUP.PROMPT, { clear = true })
    local timer = assert(vim.uv.new_timer())

    ---@type aru.agent.prompt.State
    local state = {
        buf = buf,
        win = win,
        footer_ns = footer_ns,
        reference_ns = reference_ns,
        augroup = augroup,
        timer = timer,
        refresh_id = 0,
        send = deps.send,
        collect = deps.collect or BLOCK_COLLECT,
        cwd = deps.cwd,
        invocation = deps.invocation,
        build = nil,
        preview_win = nil,
        preview_buf = nil,
    }
    _prompt_state = state
    refresh(state)

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = augroup,
        buffer = buf,
        callback = function()
            resize_prompt(state)
            request_refresh(state, false)
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "CompleteDone" }, {
        group = augroup,
        buffer = buf,
        callback = function() request_refresh(state, true) end,
    })
    vim.api.nvim_create_autocmd("WinLeave", {
        group = augroup,
        buffer = buf,
        callback = function()
            vim.schedule(function()
                if _prompt_state ~= state then return end
                local current = vim.api.nvim_get_current_win()
                if current ~= state.win and current ~= state.preview_win then close_prompt() end
            end)
        end,
    })

    local map_opts = { buffer = buf, silent = true, nowait = true }
    vim.keymap.set({ "n", "i" }, "<CR>", submit_float_read, map_opts)
    vim.keymap.set({ "n", "i" }, "<C-CR>", submit_float_new_session, map_opts)
    vim.keymap.set({ "n", "i" }, "<C-j>", submit_float_new_session, map_opts)
    vim.keymap.set(
        { "n", "i" },
        "<C-g>",
        function() submit_prompt(channels.DESTINATION.EDITOR, nil) end,
        map_opts
    )
    vim.keymap.set({ "n", "i" }, "<C-p>", function()
        local ok, cmp = pcall(require, "blink.cmp")
        if ok and cmp.is_visible() then
            cmp.select_prev()
            return
        end
        submit_prompt(channels.DESTINATION.TMUX, nil)
    end, map_opts)
    vim.keymap.set({ "n", "i" }, "<C-x>", function()
        if _prompt_state then show_payload_preview(_prompt_state) end
    end, map_opts)
    vim.keymap.set({ "n", "i" }, PROMPT_NEWLINE_KEY, insert_prompt_newline, map_opts)
    vim.keymap.set({ "n", "i" }, PROMPT_CLOSE_KEY, close_prompt, map_opts)

    vim.cmd("startinsert")
end

return M
