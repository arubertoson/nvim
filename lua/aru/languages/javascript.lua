local package_root_markers =
    { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock" }
local biome_config_files = { "biome.json", "biome.jsonc" }

local function root_markers_with_git()
    if vim.fn.has("nvim-0.11.3") == 1 then return { package_root_markers, { ".git" } } end

    return vim.list_extend(vim.deepcopy(package_root_markers), { ".git" })
end

local function buf_dir(bufnr)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    if filename == "" then return vim.fn.getcwd() end

    return vim.fs.dirname(filename)
end

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

local function find_node_path(root_dir, relative_path, executable)
    local node_modules_dirs = vim.fs.find("node_modules", {
        path = root_dir,
        upward = true,
        type = "directory",
        limit = math.huge,
    })

    for _, node_modules in ipairs(node_modules_dirs) do
        local candidate = node_modules .. "/" .. relative_path
        if executable then
            if vim.fn.executable(candidate) == 1 then return candidate end
        elseif vim.uv.fs_stat(candidate) then
            return candidate
        end
    end
end

local function find_node_bin(root_dir, name) return find_node_path(root_dir, ".bin/" .. name, true) end

local function find_tsserver(root_dir)
    return find_node_path(root_dir, "typescript/lib/tsserver.js", false)
end

local function start_rpc(cmd, dispatchers, config)
    return vim.lsp.rpc.start(cmd, dispatchers, {
        cwd = config.cmd_cwd,
        env = config.cmd_env,
        detached = config.detached,
    })
end

local function typescript_language_server_cmd(dispatchers, config)
    local executable = find_node_bin(
        config.root_dir or vim.fn.getcwd(),
        "typescript-language-server"
    ) or "typescript-language-server"
    return start_rpc({ executable, "--stdio" }, dispatchers, config)
end

local function biome_cmd(dispatchers, config)
    local executable = find_node_bin(config.root_dir or vim.fn.getcwd(), "biome") or "biome"
    return start_rpc({ executable, "lsp-proxy" }, dispatchers, config)
end

local function typescript_root_dir(bufnr, on_dir)
    -- The project root is where the LSP can be started from.
    -- This LSP supports monorepos and simple projects. We select from the project root,
    -- identified by the presence of a package-manager lock file.
    local root_markers = root_markers_with_git()

    -- Exclude Deno projects.
    local deno_root = vim.fs.root(bufnr, { "deno.json", "deno.jsonc" })
    local deno_lock_root = vim.fs.root(bufnr, { "deno.lock" })
    local project_root = vim.fs.root(bufnr, root_markers)
    if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then
        -- deno lock is closer than package manager lock, abort
        return
    end
    if deno_root and (not project_root or #deno_root >= #project_root) then
        -- deno config is closer than or equal to package manager lock, abort
        return
    end

    -- We fallback to the current working directory if no project root is found.
    on_dir(project_root or vim.fn.getcwd())
end

local function biome_root_dir(bufnr, on_dir)
    local dirname = buf_dir(bufnr)
    local biome_root = vim.fs.root(dirname, biome_config_files)
    if biome_root then
        on_dir(biome_root)
        return
    end

    if package_json_has(dirname, '"@biomejs/biome"') then
        on_dir(
            vim.fs.root(dirname, package_root_markers)
                or vim.fs.root(dirname, { "package.json" })
                or vim.fn.getcwd()
        )
    end
end

vim.lsp.config("ts_ls", {
    init_options = { hostInfo = "neovim" },
    cmd = typescript_language_server_cmd,
    filetypes = {
        "javascript",
        "javascriptreact",
        "typescript",
        "typescriptreact",
    },
    root_dir = typescript_root_dir,
    before_init = function(init_params, config)
        local tsserver = find_tsserver(config.root_dir or vim.fn.getcwd())
        if tsserver then
            config.init_options = vim.tbl_deep_extend("force", config.init_options or {}, {
                tsserver = {
                    path = tsserver,
                },
            })
            init_params.initializationOptions = config.init_options
        end
    end,
    handlers = {
        -- handle rename request for certain code actions like extracting functions / types
        ["_typescript.rename"] = function(_, result, ctx)
            local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
            vim.lsp.util.show_document({
                uri = result.textDocument.uri,
                range = {
                    start = result.position,
                    ["end"] = result.position,
                },
            }, client.offset_encoding)
            vim.lsp.buf.rename()
            return vim.NIL
        end,
    },
    commands = {
        ["editor.action.showReferences"] = function(command, ctx)
            local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
            local file_uri, position, references = unpack(command.arguments)

            local quickfix_items =
                vim.lsp.util.locations_to_items(references --[[@as any]], client.offset_encoding)
            vim.fn.setqflist({}, " ", {
                title = command.title,
                items = quickfix_items,
                context = {
                    command = command,
                    bufnr = ctx.bufnr,
                },
            })

            vim.lsp.util.show_document({
                uri = file_uri --[[@as string]],
                range = {
                    start = position --[[@as lsp.Position]],
                    ["end"] = position --[[@as lsp.Position]],
                },
            }, client.offset_encoding)
            ---@diagnostic enable: assign-type-mismatch

            vim.cmd("botright copen")
        end,
    },
    on_attach = function(client, bufnr)
        -- ts_ls provides `source.*` code actions that apply to the whole file. These only appear in
        -- `vim.lsp.buf.code_action()` if specified in `context.only`.
        vim.api.nvim_buf_create_user_command(bufnr, "LspTypescriptSourceAction", function()
            local source_actions = vim.tbl_filter(
                function(action) return vim.startswith(action, "source.") end,
                client.server_capabilities.codeActionProvider.codeActionKinds
            )

            vim.lsp.buf.code_action({
                context = {
                    only = source_actions,
                    diagnostics = {},
                },
            })
        end, {})

        -- Go to source definition command
        vim.api.nvim_buf_create_user_command(bufnr, "LspTypescriptGoToSourceDefinition", function()
            local win = vim.api.nvim_get_current_win()
            local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
            client:exec_cmd({
                command = "_typescript.goToSourceDefinition",
                title = "Go to source definition",
                arguments = { params.textDocument.uri, params.position },
            }, { bufnr = bufnr }, function(err, result)
                if err then
                    vim.notify(
                        "Go to source definition failed: " .. err.message,
                        vim.log.levels.ERROR
                    )
                    return
                end
                if not result or vim.tbl_isempty(result) then
                    vim.notify("No source definition found", vim.log.levels.INFO)
                    return
                end
                vim.lsp.util.show_document(result[1], client.offset_encoding, { focus = true })
            end)
        end, { desc = "Go to source definition" })
    end,
})

vim.lsp.config("biome", {
    cmd = biome_cmd,
    filetypes = {
        "css",
        "javascript",
        "javascriptreact",
        "json",
        "jsonc",
        "typescript",
        "typescriptreact",
    },
    root_dir = biome_root_dir,
})

vim.lsp.enable({ "ts_ls", "biome" })
