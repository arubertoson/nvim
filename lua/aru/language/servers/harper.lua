---English prose assistance for documents and supported source-language comments.
---@type vim.lsp.Config
vim.lsp.config("harper_ls", {
    cmd = { vim.fs.joinpath(vim.fn.stdpath("config"), "tools", "bin", "harper-ls"), "--stdio" },
    filetypes = {
        "asciidoc",
        "c",
        "clojure",
        "cmake",
        "cpp",
        "cs",
        "daml",
        "dart",
        "elixir",
        "gitcommit",
        "gleam",
        "go",
        "groovy",
        "haskell",
        "html",
        "ink",
        "java",
        "javascript",
        "javascriptreact",
        "jjdescription",
        "kotlin",
        "lhaskell",
        "lua",
        "mail",
        "markdown",
        "nix",
        "org",
        "php",
        "plaintex",
        "plaintext",
        "ps1",
        "python",
        "quarto",
        "ruby",
        "rust",
        "scala",
        "sh",
        "solidity",
        "swift",
        "tex",
        "text",
        "toml",
        "typescript",
        "typescriptreact",
        "typst",
        "zig",
    },
    root_markers = { ".harper-dictionary.txt", ".jj", ".git" },
    get_language_id = function(_, filetype)
        -- Harper's protocol names differ from these Neovim filetypes.
        local aliases = { cs = "csharp", sh = "shellscript", ps1 = "powershell" }
        return aliases[filetype] or filetype
    end,
    settings = {
        ["harper-ls"] = { diagnosticSeverity = "hint" },
    },
    on_attach = function(client)
        -- Keep prose hints quiet, including while typing.
        vim.diagnostic.config({
            update_in_insert = true,
            virtual_text = false,
            virtual_lines = false,
            signs = false,
        }, vim.lsp.diagnostic.get_namespace(client.id))
    end,
})

vim.lsp.enable("harper_ls")
