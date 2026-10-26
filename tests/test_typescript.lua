local MiniTest = _G.MiniTest or require("mini.test")
local child = MiniTest.new_child_neovim()
local config_root = vim.fn.getcwd()
local sandbox
local project
local shared_typescript

local function restart_neovim()
    child.restart({ "-u", "NONE", "--noplugin" })
    child.lua(
        [[
        local config_root, sandbox = ...
        vim.env.XDG_CONFIG_HOME = sandbox .. "/config"
        vim.env.NVIM_APPNAME = "nvim"
        vim.env.PATH = config_root .. "/tools/lsp/node_modules/.bin:" .. vim.env.PATH
        dofile(config_root .. "/lua/aru/language/servers/javascript.lua")
    ]],
        { config_root, sandbox }
    )
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            sandbox = vim.fn.tempname()
            project = vim.fs.joinpath(sandbox, "project")
            local node_modules = sandbox .. "/config/nvim/tools/lsp/node_modules"
            shared_typescript = node_modules .. "/typescript"
            vim.fn.mkdir(project, "p")
            vim.fn.mkdir(node_modules, "p")
            assert(
                vim.uv.fs_symlink(
                    config_root .. "/tools/lsp/node_modules/typescript",
                    shared_typescript
                )
            )
            vim.fn.writefile({ "{}" }, project .. "/package-lock.json")
            vim.fn.writefile({ "const value: number = 1;", "value;" }, project .. "/index.ts")
            restart_neovim()
        end,
        post_case = function()
            child.stop()
            vim.fn.delete(sandbox, "rf")
        end,
    },
})

local function install_project_typescript(package_dir)
    vim.fn.mkdir(project .. "/node_modules", "p")
    assert(vim.uv.fs_symlink(package_dir, project .. "/node_modules/typescript"))
end

local function start_and_hover()
    return child.lua(
        [[
        local project = ...
        vim.cmd.edit(project .. "/index.ts")
        vim.bo.filetype = "typescript"
        local clients
        assert(vim.wait(10000, function()
            clients = vim.lsp.get_clients({ bufnr = 0 })
            return #clients > 0 and clients[1].initialized
        end, 20), "TypeScript language server did not initialize")
        assert(#clients == 1, "Expected exactly one TypeScript server")
        local client = clients[1]
        local response, err = client:request_sync("textDocument/hover", {
            textDocument = { uri = vim.uri_from_bufnr(0) },
            position = { line = 1, character = 2 },
        }, 10000, 0)
        assert(response, err)
        assert(not response.err, vim.inspect(response.err))
        return {
            name = client.name,
            tsserver = client.name == "ts_ls" and client.config.init_options.tsserver.path or nil,
            hover = response.result.contents.value,
        }
    ]],
        { project }
    )
end

T["uses shared native TypeScript without a project installation"] = function()
    local result = start_and_hover()

    MiniTest.expect.equality(result.name, "tsc")
    MiniTest.expect.equality(result.hover:find("const value: number", 1, true) ~= nil, true)
end

T["uses project-local legacy TypeScript instead of shared native TypeScript"] = function()
    install_project_typescript(config_root .. "/tests/fixtures/typescript/node_modules/typescript")

    local result = start_and_hover()

    MiniTest.expect.equality(result.name, "ts_ls")
    MiniTest.expect.equality(
        result.tsserver,
        project .. "/node_modules/typescript/lib/tsserver.js"
    )
    MiniTest.expect.equality(result.hover:find("const value: number", 1, true) ~= nil, true)
end

T["uses project-local native TypeScript without relying on the shared installation"] = function()
    install_project_typescript(config_root .. "/tools/lsp/node_modules/typescript")
    assert(vim.uv.fs_unlink(shared_typescript))

    local result = start_and_hover()

    MiniTest.expect.equality(result.name, "tsc")
    MiniTest.expect.equality(result.hover:find("const value: number", 1, true) ~= nil, true)
end

T["changes server selection only after restarting Neovim"] = function()
    MiniTest.expect.equality(start_and_hover().name, "tsc")
    install_project_typescript(config_root .. "/tests/fixtures/typescript/node_modules/typescript")
    vim.fn.writefile({ "const value: number = 1;", "value;" }, project .. "/second.ts")
    child.lua(
        [[
        vim.cmd.edit(... .. "/second.ts")
        vim.bo.filetype = "typescript"
        assert(vim.wait(10000, function()
            return #vim.lsp.get_clients({ bufnr = 0, name = "tsc" }) == 1
        end, 20), "Native server should remain selected until restart")
        assert(#vim.lsp.get_clients({ bufnr = 0, name = "ts_ls" }) == 0)
    ]],
        { project }
    )

    restart_neovim()

    MiniTest.expect.equality(start_and_hover().name, "ts_ls")
end

T["does not attach either TypeScript server in a Deno project"] = function()
    vim.fn.writefile({ "{}" }, project .. "/deno.json")
    local attached = child.lua(
        [[
        vim.cmd.edit(... .. "/index.ts")
        vim.bo.filetype = "typescript"
        return vim.wait(500, function()
            return #vim.lsp.get_clients({ bufnr = 0 }) > 0
        end, 20)
    ]],
        { project }
    )

    MiniTest.expect.equality(attached, false)
end

T["Ctrl-k enters diagnostic or hover details without hiding documentation behind diagnostics"] = function()
    child.lua(
        [[
        vim.opt.runtimepath:append(...)
        require("aru.language.lsp").setup()
    ]],
        { config_root }
    )
    start_and_hover()
    child.lua([[
        local function inspect()
            local key = vim.api.nvim_replace_termcodes("<C-k>", true, false, true)
            vim.api.nvim_feedkeys(key, "xt", false)
        end
        local buf = vim.api.nvim_get_current_buf()
        local source_win = vim.api.nvim_get_current_win()
        local ns = vim.api.nvim_create_namespace("inspect_test")
        vim.diagnostic.set(ns, buf, {
            { lnum = 1, col = 0, end_col = 5, message = "Inspection diagnostic" },
        })
        assert(vim.fn.maparg("M", "n") == "", "M should retain its native behavior")
        vim.api.nvim_win_set_cursor(source_win, { 1, 0 })
        vim.api.nvim_feedkeys("]d", "xt", false)
        assert(vim.wait(2000, function()
            local win = vim.b[buf].lsp_floating_preview
            return win ~= nil and vim.api.nvim_win_is_valid(win)
        end, 20), "Diagnostic navigation did not show details")
        local diagnostic_win = vim.b[buf].lsp_floating_preview
        inspect()
        assert(vim.api.nvim_get_current_win() == diagnostic_win,
            "Ctrl-k should enter the diagnostic window")
        vim.api.nvim_feedkeys("q", "xt", false)
        assert(vim.api.nvim_get_current_win() == source_win)

        -- The diagnostic remains on this line, but its popup is now closed.
        inspect()
        assert(vim.wait(10000, function()
            local win = vim.b[buf].lsp_floating_preview
            return win ~= nil and vim.api.nvim_win_is_valid(win)
        end, 20), "Ctrl-k did not open symbol documentation")
        local hover_win = vim.b[buf].lsp_floating_preview
        local text = table.concat(vim.api.nvim_buf_get_lines(
            vim.api.nvim_win_get_buf(hover_win), 0, -1, false
        ), "\n")
        assert(text:find("value", 1, true), "Expected symbol documentation")
        assert(not text:find("Inspection diagnostic", 1, true))
        inspect()
        assert(vim.api.nvim_get_current_win() == hover_win,
            "Second Ctrl-k should enter the documentation window")
    ]])
end

return T
