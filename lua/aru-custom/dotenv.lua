-- rewrite, but this is nice to have for nvim setup.
local function parse_env_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return {}
  end

  local env = {}

  -- Read file line by line
  for line in file:lines() do
    -- Skip empty lines and comments
    if line:match "^%s*[^#]" then
      -- Remove leading/trailing whitespace
      line = line:match "^%s*(.-)%s*$"

      -- Remove optional "export" keyword
      line = line:gsub("^export%s+", "")

      -- Find the first equals sign
      local pos = line:find "="

      if pos then
        local key = line:sub(1, pos - 1):match "^%s*(.-)%s*$"
        local value = line:sub(pos + 1):match "^%s*(.-)%s*$"

        -- Remove quotes if they exist
        if value:match '^".*"$' or value:match "^'.*'$" then
          value = value:sub(2, -2)
        end

        -- Store in environment table
        env[key] = value
      end
    end
  end

  file:close()
  return env
end

local function load_env_vars(file_path, force)
  local parsed = parse_env_file(file_path)
  for k, v in pairs(parsed) do
    if force or not vim.env[k] then
      vim.env[k] = v
    end
  end
end

-- Automatically load environment variables from the config .env file
local config_env_path = vim.fs.joinpath(vim.fn.stdpath "config", ".env")
if vim.fn.filereadable(config_env_path) == 1 then
  load_env_vars(config_env_path)
end

return {}

