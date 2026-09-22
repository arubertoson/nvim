---@module "aru.autosave"
---Save normal file buffers shortly after their text changes.

local M = {}

local delay_ms = 100
local group = vim.api.nvim_create_augroup("aru_buffer_autosave_on_events", { clear = true })

---@type table<integer, { timer: uv.uv_timer_t, generation: integer }>
local pending_by_buffer = {}

---@param bufnr integer
---@return boolean
local function can_save(bufnr)
    return vim.api.nvim_get_option_value("buftype", { buf = bufnr }) == ""
        and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
        and vim.uv.fs_stat(vim.api.nvim_buf_get_name(bufnr)) ~= nil
end

---@param bufnr integer
local function save_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end
    if not can_save(bufnr) then return end

    vim.cmd(("checktime %d"):format(bufnr))
    vim.api.nvim_buf_call(bufnr, function() vim.cmd.update() end)
end

---@param bufnr integer
local function cancel_pending(bufnr)
    local pending = pending_by_buffer[bufnr]
    if not pending then return end

    pending_by_buffer[bufnr] = nil
    pending.timer:stop()
    pending.timer:close()
end

local function schedule_save(bufnr)
    local pending = pending_by_buffer[bufnr]
    if not pending then
        pending = {
            timer = assert(vim.uv.new_timer()),
            generation = 0,
        }
        pending_by_buffer[bufnr] = pending
    end

    pending.generation = pending.generation + 1
    local generation = pending.generation
    pending.timer:stop()
    pending.timer:start(
        delay_ms,
        0,
        vim.schedule_wrap(function()
            if pending_by_buffer[bufnr] ~= pending or pending.generation ~= generation then
                return
            end

            pending_by_buffer[bufnr] = nil
            pending.timer:close()
            save_buffer(bufnr)
        end)
    )
end

function M.setup()
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = group,
        desc = "Save changed buffers after a short idle period",
        callback = function(ev) schedule_save(ev.buf) end,
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        desc = "Cancel pending autosave for destroyed buffers",
        callback = function(ev) cancel_pending(ev.buf) end,
    })
end

M.setup()

return M
