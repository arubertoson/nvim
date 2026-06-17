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

vim.api.nvim_create_autocmd('PackChanged', {
  callback = function(ev)
    local name, kind = ev.data.spec.name, ev.data.kind
    if name == 'fff.nvim' and (kind == 'install' or kind == 'update') then
      if not ev.data.active then vim.cmd.packadd('fff.nvim') end
      require('fff.download').download_or_build_binary()
    end
  end,
})

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

local with_file_mark = require("aru.jump").with_file_mark
local map = vim.keymap.set

map(
  "n",
  "<leader>ff",
  with_file_mark(function() require("fff").find_files({ cwd = vim.uv.cwd() }) end),
  { desc = "Find files" }
)
map(
  "n",
  "<leader>fc",
  with_file_mark(function()
    require("fff").find_files({ cwd = vim.uv.cwd(), query = "git:modified " })
  end),
  { desc = "Find changed files" }
)
map(
  "n",
  "<leader>fs",
  with_file_mark(function() require("fff").live_grep({ cwd = vim.uv.cwd() }) end),
  { desc = "Find string in project" }
)
