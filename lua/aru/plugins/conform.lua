local conform = require("conform")

local biome_config_files = { "biome.json", "biome.jsonc" }

local function package_json_has(dirname, needle)
    local package_json_files = vim.fs.find("package.json", {
        path = dirname,
        upward = true,
        type = "file",
        limit = math.huge,
    })

    for _, package_json in ipairs(package_json_files) do
        local ok, lines = pcall(vim.fn.readfile, package_json)
        if ok and table.concat(lines, "\n"):find(needle, 1, true) then return true end
    end

    return false
end

local function has_biome_project(_, ctx)
    return vim.fs.root(ctx.dirname, biome_config_files) ~= nil
        or package_json_has(ctx.dirname, '"@biomejs/biome"')
end

local web_formatters = { "biome-check", "prettier", stop_after_first = true }

conform.setup({
    formatters_by_ft = {
        lua = { "stylua" },
        javascript = web_formatters,
        javascriptreact = web_formatters,
        typescript = web_formatters,
        typescriptreact = web_formatters,
        json = web_formatters,
        jsonc = web_formatters,
        css = web_formatters,
        scss = web_formatters,
        html = { "prettier" },
        markdown = { "prettier" },
        yaml = { "prettier" },
        python = { "ruff" },
        zig = { "zigfmt" },
        ["*"] = { "trim_whitespace" },
    },
    formatters = {
        ["biome-check"] = {
            condition = has_biome_project,
        },
        biome = {
            condition = has_biome_project,
        },
    },
    -- Format on save
    -- format_on_save = function(bufnr)
    -- 	-- Disable with a global or buffer-local variable
    -- 	if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
    -- 		return
    -- 	end
    --
    -- 	return {
    -- 		timeout_ms = 500,
    -- 		lsp_fallback = true, -- Use LSP if no formatter configured
    -- 	}
    -- end,

    notify_on_error = true,
})

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
vim.keymap.set(
    "n",
    "<leader>lf",
    function() require("conform").format({ async = true, lsp_fallback = true }) end,
    { desc = "Format file" }
)
