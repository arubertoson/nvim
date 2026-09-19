---@brief
--- https://github.com/tailwindlabs/tailwindcss-intellisense
---
--- Tailwind CSS Language Server can be installed via npm:
---
--- npm install -g @tailwindcss/language-server

local function buffer_dir(filename)
    if filename == "" then return vim.fn.getcwd() end
    return vim.fs.dirname(filename)
end

local function read_file(filename)
    local ok, lines = pcall(vim.fn.readfile, filename)
    if ok then return table.concat(lines, "\n") end
end

local function find_file_containing(filename, names, needle)
    local files = vim.fs.find(names, {
        path = buffer_dir(filename),
        upward = true,
        type = "file",
        limit = math.huge,
    })

    for _, file in ipairs(files) do
        local contents = read_file(file)
        if contents and contents:find(needle, 1, true) then return file end
    end
end

local function find_tailwind_package(filename)
    local packages = vim.fs.find("package.json", {
        path = buffer_dir(filename),
        upward = true,
        type = "file",
        limit = math.huge,
    })

    for _, package in ipairs(packages) do
        local contents = read_file(package)
        local ok, decoded = pcall(vim.json.decode, contents or "")
        if ok and type(decoded) == "table" then
            for _, field in ipairs({
                "dependencies",
                "devDependencies",
                "peerDependencies",
                "optionalDependencies",
            }) do
                local dependencies = decoded[field]
                if type(dependencies) == "table" and dependencies.tailwindcss then
                    return package
                end
            end
        end
    end
end

local function nearest_root(paths)
    local root
    for _, path in ipairs(paths) do
        if path then
            local candidate = vim.fs.dirname(path)
            if not root or #candidate > #root then root = candidate end
        end
    end
    return root
end

---@type vim.lsp.Config
vim.lsp.config("tailwindcss", {
    cmd = { "tailwindcss-language-server", "--stdio" },
    -- filetypes copied and adjusted from tailwindcss-intellisense
    filetypes = {
        -- html
        "aspnetcorerazor",
        "astro",
        "astro-markdown",
        "blade",
        "clojure",
        "django-html",
        "htmldjango",
        "edge",
        "eelixir", -- vim ft
        "elixir",
        "ejs",
        "erb",
        "eruby", -- vim ft
        "gohtml",
        "gohtmltmpl",
        "haml",
        "handlebars",
        "hbs",
        "html",
        "htmlangular",
        "html-eex",
        "heex",
        "jade",
        "leaf",
        "liquid",
        "markdown",
        "mdx",
        "mustache",
        "njk",
        "nunjucks",
        "php",
        "razor",
        "slim",
        "twig",
        -- css
        "css",
        "less",
        "postcss",
        "sass",
        "scss",
        "stylus",
        "sugarss",
        -- js
        "javascript",
        "javascriptreact",
        "reason",
        "rescript",
        "typescript",
        "typescriptreact",
        -- mixed
        "vue",
        "svelte",
        "templ",
    },
    capabilities = {
        workspace = {
            didChangeWatchedFiles = {
                dynamicRegistration = true,
            },
        },
    },
    ---@type lspconfig.settings.tailwindcss
    settings = {
        tailwindCSS = {
            validate = true,
            lint = {
                cssConflict = "warning",
                invalidApply = "error",
                invalidScreen = "error",
                invalidVariant = "error",
                invalidConfigPath = "error",
                invalidTailwindDirective = "error",
                recommendedVariantOrder = "warning",
            },
            classAttributes = {
                "class",
                "className",
                "class:list",
                "classList",
                "ngClass",
            },
            includeLanguages = {
                eelixir = "html-eex",
                elixir = "phoenix-heex",
                eruby = "erb",
                heex = "phoenix-heex",
                htmlangular = "html",
                templ = "html",
            },
        },
    },
    before_init = function(_, config)
        if not config.settings then config.settings = {} end
        if not config.settings.editor then config.settings.editor = {} end
        if not config.settings.editor.tabSize then
            config.settings.editor.tabSize = vim.lsp.util.get_effective_tabstop()
        end
    end,
    workspace_required = true,
    root_dir = function(bufnr, on_dir)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        local path = buffer_dir(filename)
        local config = vim.fs.find({
            -- Generic
            "tailwind.config.js",
            "tailwind.config.cjs",
            "tailwind.config.mjs",
            "tailwind.config.ts",
            "postcss.config.js",
            "postcss.config.cjs",
            "postcss.config.mjs",
            "postcss.config.ts",
            -- Django
            "theme/static_src/tailwind.config.js",
            "theme/static_src/tailwind.config.cjs",
            "theme/static_src/tailwind.config.mjs",
            "theme/static_src/tailwind.config.ts",
            "theme/static_src/postcss.config.js",
        }, { path = path, upward = true, type = "file" })[1]
        local package = find_tailwind_package(filename)
        local framework_lock =
            find_file_containing(filename, { "mix.lock", "Gemfile.lock" }, "tailwind")

        local css_import
        if vim.bo[bufnr].filetype == "css" then
            local contents = read_file(filename)
            if contents and contents:match("@import%s+[\"']tailwindcss[\"']") then
                css_import = filename
            end
        end

        local root = nearest_root({ config, package, framework_lock, css_import })
        if root then on_dir(root) end
    end,
})

vim.lsp.enable("tailwindcss")
