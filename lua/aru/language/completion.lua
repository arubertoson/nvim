local blink = require("blink.cmp")
local config = require("aru.config")

local M = {}

local plugin_ui_filetypes = {
    fff_file_info = true,
    fff_input = true,
    fff_list = true,
    fff_preview = true,
    fzf = true,
    minifiles = true,
    ["minifiles-help"] = true,
    minimap = true,
    mininotify = true,
    ["mininotify-history"] = true,
    minipick = true,
    ministarter = true,
    minitest = true,
    ["no-neck-pain"] = true,
    oil = true,
    oil_progress = true,
}

local function completion_enabled() return not plugin_ui_filetypes[vim.bo.filetype] end

-- stylua: ignore start
local code_triggers = {
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

local path_triggers = "[/\\~`%-]"

---@return boolean
local function has_code_char_before()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    if col == 0 then return false end

    local previous = vim.api.nvim_get_current_line():sub(col, col)
    if previous == "" or previous:match("%s") then return false end

    local pattern = code_triggers[vim.bo.filetype] or code_triggers.default
    return previous:match(pattern) ~= nil or previous:match(path_triggers) ~= nil
end

function M.tab_forward()
    if vim.snippet.active({ direction = 1 }) then
        vim.snippet.jump(1)
        return true
    end

    if not blink.is_visible() and has_code_char_before() then
        blink.show()
        return true
    end

    local key = vim.api.nvim_replace_termcodes("<Tab>", true, false, true)
    vim.api.nvim_feedkeys(key, "n", false)
end

function M.tab_backward()
    if vim.snippet.active({ direction = -1 }) then
        vim.snippet.jump(-1)
        return true
    end

    local key = vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true)
    vim.api.nvim_feedkeys(key, "n", false)
end

function M.complete()
    if blink.is_visible() then return blink.select_and_accept() end
    return blink.show()
end

blink.setup({
    enabled = completion_enabled,
    fuzzy = { implementation = "prefer_rust_with_warning" },
    appearance = { kind_icons = config.icons.kind },

    -- We activate completion sources for specific actions on the cmdline
    cmdline = {
        sources = function()
            local t = vim.fn.getcmdtype()
            if t == "/" or t == "?" then return { "buffer" } end
            if t == ":" then return { "cmdline" } end
            return {}
        end,
    },

    completion = {
        accept = { auto_brackets = { enabled = true } },
        trigger = {
            show_on_insert = false,
            show_on_trigger_character = true,
        },
        documentation = {
            auto_show = true,
            auto_show_delay_ms = 150,
            update_delay_ms = 120,
            treesitter_highlighting = true,
            window = { border = config.ui.border, winblend = vim.o.pumblend },
        },
        ghost_text = { enabled = false, show_with_menu = false },
        list = {
            selection = {
                preselect = function(ctx)
                    return ctx.mode ~= "cmdline"
                        and not require("blink.cmp").snippet_active({
                            direction = 1,
                        })
                end,
            },
        },
        menu = {
            auto_show = function(ctx)
                return ctx.mode ~= "default" or vim.b[ctx.bufnr].psst_prompt == true
            end,
            border = config.ui.border,
            -- Minimum width should be controlled by components
            min_width = 1,
            draw = {
                columns = {
                    { "kind_icon" },
                    { "label", "label_description", gap = 1 },
                    { "provider" },
                },
                components = {
                    provider = {
                        text = function(ctx)
                            return "[" .. ctx.item.source_name:sub(1, 3):upper() .. "]"
                        end,
                    },
                },
            },
        },
    },

    sources = {
        default = function()
            if vim.b.psst_prompt then
                return require("psst.completion").sources(vim.api.nvim_get_current_buf())
            end
            return { "lsp", "path", "snippets", "buffer" }
        end,
        providers = {
            -- lsp = { min_keyword_length = 2, name = "LSP", fallbacks = { "lazydev" } },
            path = { module = "blink.cmp.sources.path" },
            -- snippets = { min_keyword_length = 1 },
            buffer = { min_keyword_length = 3, max_items = 5 },
            prompt_files = {
                name = "Files",
                module = "psst.completion.files",
                async = true,
                opts = {
                    get_cwd = function(ctx) return vim.b[ctx.bufnr].psst_completion_cwd end,
                },
            },
            prompt_symbol = {
                name = "Symbol",
                module = "psst.completion.symbol",
                opts = {
                    get_cwd = function(ctx) return vim.b[ctx.bufnr].psst_completion_cwd end,
                    get_invocation_buf = function(ctx)
                        return vim.b[ctx.bufnr].psst_completion_invocation_buf
                    end,
                },
            },
            -- lazydev = { name = "Development", module = "lazydev.integrations.blink" },
        },
    },

    signature = {
        enabled = true,
        window = {
            show_documentation = true,
            border = config.ui.border,
            winblend = vim.o.pumblend,
        },
    },

    keymap = {
        preset = "none",

        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },

        ["<C-u>"] = { "scroll_documentation_up", "fallback" },
        ["<C-d>"] = { "scroll_documentation_down", "fallback" },
        ["<C-e>"] = { "hide" },
    },
})

vim.keymap.set({ "i", "s" }, "<Tab>", M.tab_forward, { silent = true })
vim.keymap.set({ "i", "s" }, "<S-Tab>", M.tab_backward, { silent = true })
vim.keymap.set({ "i", "s" }, "<C-l>", M.complete, { silent = true })

return M
