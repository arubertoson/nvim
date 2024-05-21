local M = {}

-- Table to cache detected roots for buffers
M.cache = {}

-- Root detection specs
M.spec = { ".git", "lua", "cwd" }

-- Function to get the current working directory
function M.cwd()
  return vim.loop.cwd() or ""
end

-- Function to get the real path
function M.realpath(path)
  if not path or path == "" then
    return nil
  end
  return vim.loop.fs_realpath(path) or path
end

-- Function to get the buffer path
function M.bufpath(buf)
  return M.realpath(vim.api.nvim_buf_get_name(buf))
end

-- Function to detect the root based on patterns
function M.detect_pattern(buf, patterns)
  patterns = type(patterns) == "string" and { patterns } or patterns
  local path = M.bufpath(buf) or M.cwd()
  local pattern = vim.fs.find(function(name)
    for _, p in ipairs(patterns) do
      if name == p or (p:sub(1, 1) == "*" and name:find(vim.pesc(p:sub(2)) .. "$")) then
        return true
      end
    end
    return false
  end, { path = path, upward = true })[1]
  return pattern and { vim.fs.dirname(pattern) } or {}
end

-- Function to detect the root based on LSP workspace folders
function M.detect_lsp(buf)
  local bufpath = M.bufpath(buf)
  if not bufpath then return {} end
  local roots = {}
  for _, client in pairs(vim.lsp.get_active_clients({ bufnr = buf })) do
    if client.config.workspace_folders then
      for _, ws in pairs(client.config.workspace_folders) do
        roots[#roots + 1] = vim.uri_to_fname(ws.uri)
      end
    end
    if client.config.root_dir then
      roots[#roots + 1] = client.config.root_dir
    end
  end
  return vim.tbl_filter(function(path)
    return bufpath:find(M.realpath(path), 1, true) == 1
  end, roots)
end

-- Main function to detect the root directory
function M.detect(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local specs = opts.spec or M.spec
  local roots = {}

  for _, spec in ipairs(specs) do
    local paths = {}
    if type(spec) == "string" then
      if spec == "cwd" then
        paths = { M.cwd() }
      else
        paths = M.detect_pattern(buf, spec)
      end
    elseif type(spec) == "table" then
      paths = M.detect_pattern(buf, spec)
    end
    if #paths > 0 then
      table.sort(paths, function(a, b) return #a > #b end)
      roots = paths
      break
    end
  end

  return roots
end

-- Function to get the root directory
function M.get(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local root = M.cache[buf]
  if not root then
    local roots = M.detect({ buf = buf })
    root = roots[1] or M.cwd()
    M.cache[buf] = root
  end
  return root
end

-- Setup function to create user command and autocommands
function M.setup()
  vim.api.nvim_create_user_command("Root", function()
    print("Project root: " .. M.get())
  end, { desc = "Show project root for the current buffer" })

  vim.api.nvim_create_autocmd({ "BufWritePost", "DirChanged", "BufEnter" }, {
    callback = function(event)
      M.cache[event.buf] = nil
    end,
  })
end

return M
