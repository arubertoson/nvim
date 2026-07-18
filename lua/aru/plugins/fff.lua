--- fff.nvim configuration.
---
--- Role:
---   Primary file/content interaction layer.
---
--- Use for:
---   - file search
---   - live grep
---   - git/path-constrained file queries
---
--- Boundary:
---   fff has a picker UI, but not a public generic picker API. Its search path is
---   wired to fff file/grep backends, and selection expects a file item with a
---   `relative_path`. Generic help/LSP/code-action flows use Neovim defaults.
---
--- See: docs/fzf-fff-migration.md

local function capped_width_ratio(columns)
  local max_columns = 75 -- roughly 600px at an 8px terminal cell width
  return math.min(0.8, max_columns / columns)
end

local function reset_fff_config_cache()
  -- fff.nvim can initialize from its own plugin/fff.lua UIEnter callback before
  -- this deferred config file runs. Its conf module caches the resolved config,
  -- so replace that cache after setting vim.g.fff below. Keep all of this here
  -- so fff runtime behavior stays isolated to this plugin file.
  package.loaded["fff.conf"] = nil

  -- If picker UI modules were also loaded early, drop them so they re-read the
  -- refreshed config on first real picker use. Do not unload fff.core/fuzzy:
  -- those may own Rust/backend state after an early UIEnter initialization.
  for name in pairs(package.loaded) do
    if name == "fff.layout" or name:match("^fff%.picker_ui") then
      package.loaded[name] = nil
    end
  end
end

vim.g.fff = {
  prompt = "",
  title = "fff",
  lazy_sync = true,
  wrap_around = true,
  debug = { enabled = false, show_scores = false },
  layout = {
    anchor = "center",
    prompt_position = "top",
    height = 0.7,
    width = capped_width_ratio,
    show_scrollbar = false,
  },
  preview = { enabled = false },
  file_picker = { current_file_label = "" },
}

reset_fff_config_cache()

local function ensure_fff_backend()
  local ok, download = pcall(require, "fff.download")
  if not ok then
    vim.notify("fff.nvim download helper unavailable: " .. tostring(download), vim.log.levels.ERROR)
    return false
  end

  if vim.uv.fs_stat(download.get_binary_path()) then return true end

  vim.notify("Installing fff.nvim Rust backend...", vim.log.levels.INFO)

  local install_ok, err = pcall(download.download_or_build_binary)
  if not install_ok then
    vim.notify("Failed to install fff.nvim Rust backend: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

local fff_backend_ready = ensure_fff_backend()

local function with_fff(action)
  return function(...)
    if not fff_backend_ready then fff_backend_ready = ensure_fff_backend() end
    if not fff_backend_ready then return end

    local ok, fff = pcall(require, "fff")
    if not ok then
      vim.notify("Failed to load fff.nvim: " .. tostring(fff), vim.log.levels.ERROR)
      return
    end

    return action(fff, ...)
  end
end

local map = vim.keymap.set

map(
  "n",
  "<leader>ff",
  with_fff(function(fff) fff.find_files({ cwd = vim.uv.cwd() }) end),
  { desc = "Find files" }
)
map(
  "n",
  "<leader>fc",
  with_fff(function(fff)
    fff.find_files({ cwd = vim.uv.cwd(), query = "git:modified " })
  end),
  { desc = "Find changed files" }
)
map(
  "n",
  "<leader>fs",
  with_fff(function(fff) fff.live_grep({ cwd = vim.uv.cwd() }) end),
  { desc = "Find string in project" }
)
