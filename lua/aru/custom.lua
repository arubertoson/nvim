local M = {}

M.theme = "kanagawa-dragon"

-- Border style of floating windows
M.border = "rounded"

-- Width of side windows
-- M.width = function()
--   return math.max(math. .floor(vim.go.columns * 0.2), 30)
-- en

local append_space = function(icons)
    local result = {}
    for k, v in pairs(icons) do
        result[k] = v .. " "
    end
    return result
end

local kind_icons = {
    Array = "",
    Boolean = "",
    Class = "",
    Color = "",
    Constant = "",
    Constructor = "",
    Enum = "",
    EnumMember = "",
    Event = "",
    Field = "",
    File = "",
    Folder = "",
    Function = "",
    Interface = "",
    Key = "",
    Keyword = "",
    Method = "",
    Module = "",
    Namespace = "",
    Null = "",
    Number = "",
    Object = "",
    Operator = "",
    Package = "",
    Property = "",
    Reference = "",
    Snippet = "",
    String = "",
    Struct = "",
    Text = "",
    TypeParameter = "",
    Unit = "",
    Value = "",
    Variable = "",
}

M.icons = {
    -- LSP diagnostic
    diagnostic = {
        error = "󰅚 ",
        warn = "󰀪 ",
        hint = "󰌶 ",
        info = "󰋽 ",
    },
    -- LSP kinds
    kind = kind_icons,
    kind_with_space = append_space(kind_icons),
    git = "",
}

M.cmp_format = {
    mode = "symbol",
    maxwidth = 50,
    menu = {
        lazydev = "[DEV]",
        luasnip = "[SNP]",
        nvim_lsp = "[LSP]",
        nvim_lua = "[VIM]",
        dap = "[DAP]",
        buffer = "[BUF]",
        path = "[PTH]",
        calc = "[CLC]",
        latex_symbols = "[TEX]",
        orgmode = "[ORG]",
        cmdline = "[CMD]",
    },
}

M.treesitter_parsers = {
    "astro",
    "c",
    "c_sharp",
    "css",
    "diff",
    "dockerfile",
    "git_config",
    "git_rebase",
    "gitattributes",
    "gitcommit",
    "gitignore",
    "go",
    "gomod",
    "gosum",
    "gowork",
    "html",
    "htmldjango",
    "hyprlang",
    "java",
    "javascript",
    "jsdoc",
    "json",
    "jsonc",
    "kdl",
    "kotlin",
    "lua",
    "luadoc",
    "luap",
    "luau",
    "markdown",
    "markdown_inline",
    "nu",
    "ocaml",
    "ocaml_interface",
    "ocamllex",
    "python",
    "query",
    "regex",
    "requirements",
    "rust",
    "scheme",
    "sql",
    "svelte",
    "toml",
    "tsx",
    "typescript",
    "vim",
    "vimdoc",
    "vue",
    "xml",
    "yaml",
    "zig",
}

return M
