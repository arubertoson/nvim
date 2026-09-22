local function project_command(args)
    return function(dispatchers, config)
        return vim.lsp.rpc.start(
            vim.list_extend({ "mise", "exec", "--", "uv", "run" }, args),
            dispatchers,
            {
                cwd = config.root_dir,
                env = config.cmd_env,
                detached = config.detached,
            }
        )
    end
end

vim.lsp.config("pyrefly", {
    cmd = project_command({ "pyrefly", "lsp" }),
    filetypes = { "python" },
    root_markers = {
        "pyrefly.toml",
        "pyproject.toml",
        "uv.lock",
        "setup.py",
        "setup.cfg",
        "requirements.txt",
        ".git",
    },
})

vim.lsp.config("ruff", {
    cmd = project_command({ "ruff", "server" }),
    filetypes = { "python" },
    root_markers = { "pyproject.toml", "uv.lock", "ruff.toml", ".ruff.toml", ".git" },
    on_attach = function(client) client.server_capabilities.hoverProvider = false end,
})

vim.lsp.enable({ "pyrefly", "ruff" })
