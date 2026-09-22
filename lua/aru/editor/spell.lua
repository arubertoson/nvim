---@module "aru.editor.spell"
---
--- Spell checking policy: on by default, exclusion-based.
---
--- - Default language: en (American English, bundled with Neovim)
--- - Default mode: comment/string only (`noplainbuffer`) via Treesitter @spell
--- - Prose filetypes in `exclude_noplainbuffer` check the whole buffer
--- - Filetypes in `exclude` (and some buftypes) disable spell entirely
---
--- TODO: Revisit spelling highlight rendering when terminal/UI support changes.
--- We currently rely on plain underline instead of undercurl because undercurl did
--- not render reliably in the active Neovim/terminal path. Colored plain underline
--- may also fall back to the foreground color even when `guisp` is configured.
--- If this improves, switch the theme spell highlights back to red undercurl.

local M = {}

M.lang = "en"

--- Filetypes with spell checking fully disabled.
M.exclude = {
    "help",
    "qf",
    "log",
    "dbui",
    "dbout",
    "oil",
    "notify",
    "checkhealth",
    "lspinfo",
    "git",
    "TelescopePrompt",
    "fzf",
    "dressing_input",
    "toggleterm",
    "floaterm",
    "neo-tree",
    "NvimTree",
    "minifiles",
    "dap-repl",
}

--- Filetypes excluded from `noplainbuffer` (spell the entire buffer).
M.exclude_noplainbuffer = {
    "markdown",
    "text",
    "plaintext",
    "rst",
    "org",
    "mail",
    "norg",
    "gitcommit",
}

--- Buftypes that never get spell checking.
M.exclude_buftype = {
    ["terminal"] = true,
    ["prompt"] = true,
    ["acwrite"] = true,
}

---@param ft string
---@return boolean
local function is_excluded_ft(ft) return ft ~= "" and vim.tbl_contains(M.exclude, ft) end

---@param ft string
---@return boolean
local function is_full_buffer(ft) return ft ~= "" and vim.tbl_contains(M.exclude_noplainbuffer, ft) end

---@param buf? integer
---@return boolean
local function is_excluded_buf(buf)
    buf = buf or 0
    local bt = vim.bo[buf].buftype
    if M.exclude_buftype[bt] then return true end
    return is_excluded_ft(vim.bo[buf].filetype)
end

---@param buf integer
---@param enabled boolean
local function set_win_spell(buf, enabled)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == buf then vim.wo[win].spell = enabled end
    end
end

---Pick a spelling suggestion and replace the misspelling on the current line.
function M.pick_suggestion()
    local bufnr = vim.api.nvim_get_current_buf()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local bad = vim.fn.spellbadword()[1]
    if bad == "" then bad = vim.fn.expand("<cword>") end

    local suggestions = vim.fn.spellsuggest(bad, 10)
    if vim.tbl_isempty(suggestions) then
        vim.notify("No spelling suggestions for " .. bad, vim.log.levels.INFO)
        return
    end

    vim.ui.select(suggestions, { prompt = "Replace " .. bad .. " with:" }, function(choice)
        if not choice then return end
        if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
            return
        end
        if row > vim.api.nvim_buf_line_count(bufnr) then return end

        local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]
        local best_start, best_end
        local start = 1

        while true do
            local match_start, match_end = line:find(bad, start, true)
            if not match_start then break end

            if match_start - 1 <= col and col <= match_end then
                best_start, best_end = match_start, match_end
                break
            end

            if not best_start then
                best_start, best_end = match_start, match_end
            end
            start = match_end + 1
        end

        if not best_start then return end

        vim.api.nvim_buf_set_text(bufnr, row - 1, best_start - 1, row - 1, best_end, { choice })
    end)
end

--- Apply spell options for the current buffer.
---@param buf? integer
function M.apply(buf)
    buf = buf or 0

    if is_excluded_buf(buf) then
        set_win_spell(buf, false)
        return
    end

    vim.bo[buf].spelllang = M.lang

    local opts = { "camel" }
    if not is_full_buffer(vim.bo[buf].filetype) then opts[#opts + 1] = "noplainbuffer" end
    vim.bo[buf].spelloptions = table.concat(opts, ",")

    set_win_spell(buf, true)
end

function M.setup()
    vim.o.spelllang = M.lang

    vim.keymap.set("n", "]s", "]s", { desc = "Next misspelling" })
    vim.keymap.set("n", "[s", "[s", { desc = "Previous misspelling" })
    vim.keymap.set("n", "z=", "z=", { desc = "Spelling suggestions" })
    vim.keymap.set("n", "<leader>sf", "1z=", { desc = "Fix spelling with first suggestion" })
    vim.keymap.set("n", "<leader>ss", M.pick_suggestion, { desc = "Pick spelling suggestion" })

    local group = vim.api.nvim_create_augroup("aru_spell", { clear = true })

    vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "BufWinEnter" }, {
        group = group,
        desc = "Apply exclusionary spell policy",
        callback = function(ev) M.apply(ev.buf) end,
    })
end

M.setup()

return M
