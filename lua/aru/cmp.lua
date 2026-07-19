local M = {}

-- stylua: ignore start
M.CODE_TRIGGERS = {
  default     = "[%w_%.$:@>:%?]",
  lua         = "[%w_%.:]",
  python      = "[%w_%.$]",
  javascript  = "[%w_%.$%?]",
  typescript  = "[%w_%.$%?]",
  tsx         = "[%w_%.$%?]",
  jsx         = "[%w_%.$%?]",
  c           = "[%w_%.$>]",
  cpp         = "[%w_%.$:>]",
  csharp      = "[%w_%.$:]",
  rust        = "[%w_%.$:]",
  go          = "[%w_%.$]",
  php         = "[%w_%.$>:@]",
  ruby        = "[%w_%.$:@]",
  kotlin      = "[%w_%.$:]",
  java        = "[%w_%.$]",
  swift       = "[%w_%.$:]",
  zig         = "[%w_%.@]",
}
-- stylua: ignore end

-- XXX: path completion not working in this setup, need to add trigger for that as well.

--- Check if the character before cursor matches code trigger patterns
--- @return boolean
local function has_code_char_before()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col = cursor[2]

    if col == 0 then return false end

    local line = vim.api.nvim_get_current_line()
    -- cold is 0-based byte offset; Lua string.sub is 1-based
    local prev_char = line:sub(col, col)

    if prev_char == "" or prev_char:match("%s") then return false end

    local ft = vim.bo.filetype
    local pat = M.CODE_TRIGGERS[ft] or M.CODE_TRIGGERS.default

    return prev_char:match(pat) ~= nil
end

--- Check if the character before cursor matches code trigger patterns
--- @param cmp table The blink.cmp module
--- @return boolean
local function should_trigger_menu(cmp)
    if cmp.is_visible() or not has_code_char_before() then return false end

    -- We should also avoid trying to show the list when we have not
    -- available context
    local items = cmp.get_items()

    return items and #items > 0
end

--- Handle tab key forward navigation through snippets and completion
--- @return boolean|nil
function M.tab_forward()
    local blink_ok, cmp = pcall(require, "blink.cmp")

    if not blink_ok then
        vim.log.error("blink.cmp not found")
        return false
    end

    if should_trigger_menu(cmp) then
        pcall(function() require("neocodeium").clear() end)
        cmp.show()
        return true
    end

    if vim.snippet.active({ direction = 1 }) then
        vim.snippet.jump(1)
        return true
    end

    local key = vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
    vim.api.nvim_feedkeys(key, "n", false)
end

--- Handle shift-tab key backward navigation through snippets
function M.tab_backward()
    if vim.snippet.active({ direction = -1 }) then
        vim.snippet.jump(-1)
        return true
    end

    local key = vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true)
    vim.api.nvim_feedkeys(key, "n", false)
end

--- Smart accept completion, snippet, or AI suggestion
function M.smart_accept()
    local blink_ok, cmp = pcall(require, "blink.cmp")

    -- If blink menus is open: accept the selected item
    if blink_ok and cmp.is_visible() then
        cmp.accept()
        return
    end

    -- If supermaven is open: accept the selected item
    -- TODO: this is a bit hacky, but it works for now
    local sup_ok, preview = pcall(require, "supermaven-nvim.completion_preview")

    --- If supermaven is open: accept the selected item
    --- TODO: this is a bit hacky, but it works for now
    if sup_ok then
        local inst = preview:get_inlay_instance()
        if not inst or not inst.completion_text or inst.completion_text == "" then return end
        require("aru.log"):info("super maven triggered!")
        preview.on_accept_suggestion(false)
        return
    end

    -- Otherwise we try to accept neocodeium ghost text.
    -- if there is no ghost this becomes a no-op and won't break anything
    -- local neo_ok, neo = pcall(require, "neocodeium")
    -- if neo_ok then
    --     local before = vim.api.nvim_get_current_line()
    --     neo.accept()
    --
    --     if vim.api.nvim_get_current_line() == before then return end
    -- end
end

return M
