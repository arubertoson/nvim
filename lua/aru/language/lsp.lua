---@module "aru.language.lsp"
---
---Personal LSP glue. Keeps everything in one place so it's easy to tweak
---without digging through several abstraction layers.

local config = require("aru.config")

local M = {}

local diagnostic_signs = {
    [vim.diagnostic.severity.ERROR] = config.icons.diagnostic.error,
    [vim.diagnostic.severity.WARN] = config.icons.diagnostic.warn,
    [vim.diagnostic.severity.HINT] = config.icons.diagnostic.hint,
    [vim.diagnostic.severity.INFO] = config.icons.diagnostic.info,
}

local diagnostic_config = {
    virtual_lines = false,
    virtual_text = {
        spacing = 4,
        prefix = "●",
        severity = vim.diagnostic.severity.ERROR,
    },
    float = {
        severity_sort = true,
        border = config.ui.border,
    },
    update_in_insert = false,
    severity_sort = true,
    signs = {
        text = diagnostic_signs,
    },
}

local function map_buffer_keys(bufnr)
    local function map(lhs, rhs, desc, mode)
        vim.keymap.set(mode or "n", lhs, rhs, {
            buffer = bufnr,
            noremap = true,
            silent = true,
            desc = desc,
        })
    end

    local function picker_opts()
        return { window = { config = require("aru.interface.picker").window_config } }
    end

    local function pick_lsp(scope)
        require("mini.extra").pickers.lsp({ scope = scope }, picker_opts())
    end

    local function pick_diagnostics(scope)
        require("mini.extra").pickers.diagnostic(
            { scope = scope },
            vim.tbl_deep_extend("force", picker_opts(), {
                source = { show = require("aru.interface.picker").show_diagnostics },
            })
        )
    end

    -- stylua: ignore start
	map("fs", function() pick_lsp("document_symbol") end, "Document symbols")
	map("fS", function() pick_lsp("workspace_symbol") end, "Workspace symbols")
	map("fd", function() pick_diagnostics("current") end, "Buffer diagnostics")
	map("fD", function() pick_diagnostics("all") end, "Workspace diagnostics")
	map("gd", function() pick_lsp("definition") end, "Goto definition")
	map("gr", function() pick_lsp("references") end, "References")
	map("go", vim.lsp.buf.code_action, "Code actions")
	map("gi", function() pick_lsp("implementation") end, "Implementations")
	map("gy", function() pick_lsp("type_definition") end, "Type definitions")

	map("]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
	map("[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Prev diagnostic")
	map("M", vim.diagnostic.open_float, "Line diagnostics")
    -- stylua: ignore end

    map(
        "<leader>oi",
        function()
            vim.lsp.buf.code_action({
                context = {
                    only = { "source.organizeImports" },
                    diagnostics = {},
                },
                apply = true,
            })
        end,
        "Organize imports"
    )

    map("<leader>ws", vim.lsp.buf.workspace_symbol, "Workspace symbol")
    map("<leader>wa", vim.lsp.buf.add_workspace_folder, "Add workspace folder")
    map("<leader>wr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
    map(
        "<leader>wl",
        function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end,
        "List workspace folders"
    )

    map("<leader>li", "<cmd>checkhealth vim.lsp<cr>", "LSP health")
end

local function setup_buffer(bufnr)
    if vim.b[bufnr].aru_lsp_buffer_setup then return end

    map_buffer_keys(bufnr)
    vim.b[bufnr].aru_lsp_buffer_setup = true
end

local function setup_inlay_hints(client, bufnr)
    if vim.b[bufnr].aru_lsp_inlay_hints_setup then return end
    if not client:supports_method("textDocument/inlayHint", bufnr) then return end

    vim.b[bufnr].aru_inlay_hints = true
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

    local function current_state() return vim.b[bufnr].aru_inlay_hints end

    local function set_state(value)
        vim.b[bufnr].aru_inlay_hints = value
        vim.lsp.inlay_hint.enable(value, { bufnr = bufnr })
    end

    local group =
        vim.api.nvim_create_augroup(("aru_inlay_hints_%d"):format(bufnr), { clear = true })

    vim.api.nvim_create_autocmd("InsertEnter", {
        group = group,
        buffer = bufnr,
        callback = function() vim.lsp.inlay_hint.enable(false, { bufnr = bufnr }) end,
        desc = "Hide inlay hints while typing",
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
        group = group,
        buffer = bufnr,
        callback = function()
            if current_state() then vim.lsp.inlay_hint.enable(true, { bufnr = bufnr }) end
        end,
        desc = "Restore inlay hints on insert leave",
    })

    vim.keymap.set(
        "n",
        "<leader>lh",
        function() set_state(not current_state()) end,
        { buffer = bufnr, noremap = true, silent = true, desc = "Toggle inlay hints" }
    )

    vim.b[bufnr].aru_lsp_inlay_hints_setup = true
end

local function setup_codelens(client, bufnr)
    if vim.b[bufnr].aru_lsp_codelens_setup then return end
    if not client:supports_method("textDocument/codeLens", bufnr) then return end

    vim.keymap.set("n", "<leader>lc", vim.lsp.codelens.run, {
        buffer = bufnr,
        noremap = true,
        silent = true,
        desc = "Run code lens",
    })

    vim.lsp.codelens.enable(true, { bufnr = bufnr })
    vim.b[bufnr].aru_lsp_codelens_setup = true
end

local function on_attach(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client then return end

    local bufnr = event.buf
    setup_buffer(bufnr)
    setup_inlay_hints(client, bufnr)
    setup_codelens(client, bufnr)
end

local gc_timers = {}
local gc_ttl = 5 * 60 * 1000 -- ms

local function clear_timer(id)
    local timer = gc_timers[id]
    if not timer then return end
    timer:stop()
    timer:close()
    gc_timers[id] = nil
end

local function has_loaded_buffers(client)
    for bufnr in pairs(client.attached_buffers or {}) do
        if vim.api.nvim_buf_is_loaded(bufnr) then return true end
    end
    return false
end

local function arm_gc(client)
    local current = vim.lsp.get_client_by_id(client.id)
    if not current then
        clear_timer(client.id)
        return
    end

    client = current
    if has_loaded_buffers(client) then
        clear_timer(client.id)
        return
    end

    clear_timer(client.id)

    local timer = vim.uv.new_timer()
    if not timer then return end

    timer:start(
        gc_ttl,
        0,
        vim.schedule_wrap(function()
            clear_timer(client.id)
            local current = vim.lsp.get_client_by_id(client.id)
            if current and not has_loaded_buffers(current) then current:stop(true) end
        end)
    )

    gc_timers[client.id] = timer
end

local function setup_gc()
    local group = vim.api.nvim_create_augroup("aru_lsp_gc", { clear = true })

    vim.api.nvim_create_autocmd("LspDetach", {
        group = group,
        desc = "Stop clients once no loaded buffers remain",
        callback = function(ev)
            local client = vim.lsp.get_client_by_id(ev.data.client_id)
            if client then vim.defer_fn(function() arm_gc(client) end, 50) end
        end,
    })

    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        desc = "Cancel pending LSP GC timers",
        callback = function(ev) clear_timer(ev.data.client_id) end,
    })
end

function M.setup()
    vim.diagnostic.config(diagnostic_config)
    setup_gc()

    vim.keymap.set(
        "n",
        "<leader>lf",
        function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
        { desc = "Format file" }
    )
    vim.keymap.set(
        "n",
        "<leader>ld",
        function() vim.diagnostic.enable(not vim.diagnostic.is_enabled()) end,
        { desc = "Toggle diagnostics" }
    )
    vim.keymap.set(
        "n",
        "<leader>lh",
        function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end,
        { desc = "Toggle inlay hints" }
    )
    vim.keymap.set("n", "<leader>li", "<cmd>checkhealth vim.lsp<CR>", { desc = "LSP info" })

    vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("aru_lsp_attach", { clear = true }),
        desc = "Configure LSP buffer glue",
        callback = on_attach,
    })
end

return M
