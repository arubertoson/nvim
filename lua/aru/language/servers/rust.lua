---@brief
--- https://rust-analyzer.github.io/
---
--- Rust LSP implementation.
---
---@type vim.lsp.Config
vim.lsp.config("rust_analyzer", {
    cmd = { "rust-analyzer" },
    filetypes = { "rust" },
    root_markers = { "rust-project.json", "Cargo.toml", ".git" },
    workspace_required = false,
})

vim.lsp.enable("rust_analyzer")
