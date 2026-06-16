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
---   `relative_path`. Keep arbitrary item pickers in fzf-lua for now.
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

vim.g.fff = {
  lazy_sync = true,
  debug = { enabled = true, show_scores = true },
}

require("fff").setup({
    wrap_around = true,
    layout = {
        prompt_position = "top",
    },
    preview = { enabled = false },
})
