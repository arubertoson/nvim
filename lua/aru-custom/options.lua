local g = vim.g
local o = vim.o
local opt = vim.opt

-----------------------------------------------------------------------------//
-- General Behavior & Saving
-----------------------------------------------------------------------------//
-- Enable auto write when switching buffers, quitting, etc. (fallback save mechanism)
opt.autowrite = true
-- Confirm to save changes before exiting modified buffer (safety net)
opt.confirm = true
-- Enable persistent undo history saved to a file
opt.undofile = true
-- Set a deep undo history limit
opt.undolevels = 10000

-----------------------------------------------------------------------------//
-- System Integration
-----------------------------------------------------------------------------//
-- Sync with system clipboard for copy/paste between Neovim and other applications
opt.clipboard = "unnamedplus"

-----------------------------------------------------------------------------//
-- Appearance & UI
-----------------------------------------------------------------------------//
-- Hide * markup for bold and italic, but not markers with substitutions (useful for markdown)
opt.conceallevel = 2
-- Enable highlighting of the current line (default, managed dynamically by autocmds)
opt.cursorline = true
-- Custom characters for UI elements like folds and diffs
opt.fillchars = {
	foldopen = "",
	foldclose = "",
	fold = "│", -- Use vertical line for fold column
	foldsep = "│", -- Use vertical line for fold separator
	diff = "╱",
	eob = " ",
}
-- Set command line height to zero to hide it when not in use
opt.cmdheight = 0
-- opt.shortmess:append({ W = true, I = true, c = true, C = true }) -- Commented out (unsure if needed)
-- opt.wrap = false -- Commented out (reverts to default wrap=true)

-----------------------------------------------------------------------------//
-- Navigation & Scrolling
-----------------------------------------------------------------------------//
-- Keep 4 lines of context above/below cursor when scrolling vertically
opt.scrolloff = 4
-- Keep 8 columns of context left/right of cursor when scrolling horizontally
opt.sidescrolloff = 8

-----------------------------------------------------------------------------//
-- Editing & Formatting
-----------------------------------------------------------------------------//
-- Prevent 'o' from automatically inserting comments when opening new lines
opt.formatoptions:remove("o")
-- Insert indents automatically based on filetype
opt.smartindent = true
-- Set spell checking language
opt.spelllang = { "en" }
-- Preview incremental substitute commands in a split window
opt.inccommand = "split"

-----------------------------------------------------------------------------//
-- Searching
-----------------------------------------------------------------------------//
-- Ignore case in searches by default
opt.ignorecase = true
-- Don't ignore case in searches if the pattern contains capitals
opt.smartcase = true

-----------------------------------------------------------------------------//
-- Window Management
-----------------------------------------------------------------------------//
-- Put new windows below current when splitting horizontally
opt.splitbelow = true
-- Maintain screen view when splitting windows
opt.splitkeep = "screen"
-- Put new windows right of current when splitting vertically
opt.splitright = true

-----------------------------------------------------------------------------//
-- Folding
-----------------------------------------------------------------------------//
-- Open all folds by default when opening a file
opt.foldlevel = 99
-- opt.foldexpr = "v:lua.require'aru.utils'.foldexpr()" -- Removed (managed by treesitter plugin)
-- opt.foldmethod = "expr" -- Removed (managed by treesitter plugin)
-- opt.foldtext = "" -- Removed (move to treesitter config for locality)

-----------------------------------------------------------------------------//
-- Performance
-----------------------------------------------------------------------------//
-- Time in ms to wait before triggering CursorHold events (for diagnostics, etc.)
opt.updatetime = 200
-- Don't syntax highlight lines longer than 256 characters for performance
opt.synmaxcol = 256

-----------------------------------------------------------------------------//
-- Disabled Built-ins
-----------------------------------------------------------------------------//
-- Disable built-in archive/compression handlers
vim.g.loaded_gzip = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1

-- Disable older plugin management features
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_2html_plugin = 1

-- Disable basic editing helpers often replaced by plugins (like Treesitter)
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_syntax_tools = 1 -- Added: Disable basic syntax tools (recommended with Treesitter)

-- Disable built-in file explorer
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_netrwFileHandlers = 1

-- Disable legacy remote plugin providers (recommended when using LSP)
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0

-----------------------------------------------------------------------------//
-- Removed/Moved Options (for reference)
-----------------------------------------------------------------------------//
-- opt.completeopt = "menu,menuone,noselect" -- Moved to lua/aru/utils/snippets.lua
-- opt.formatexpr = "v:lua.require'aru.helper'.foldexpr()" -- Handled by conform.nvim
-- opt.grepformat = "%f:%l:%c:%m" -- Removed (using other search methods)
-- opt.grepprg = "rg --vimgrep" -- Removed (using other search methods)
-- opt.laststatus = 3 -- global statusline -- Moved to lua/aru/viewport/statusline.lua
-- opt.mouse = "a" -- Removed (not using mouse)
-- opt.pumblend = 10 -- Removed (using default opaque popup)
-- opt.pumheight = 10 -- Removed (using default popup height)
-- opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" } -- Removed (managing sessions differently)
-- opt.showmode = false -- Dont show mode since we have a statusline -- Moved to lua/aru/viewport/statusline.lua
-- opt.signcolumn = "yes:1" -- Removed (managed dynamically by autocmds)
-- opt.termguicolors = true -- True color support -- Already in lua/aru/config/theme.lua
-- opt.virtualedit = "block" -- Removed (not using virtual edit)
-- opt.wildmode = "longest:full,full" -- Removed (not relevant)
-- opt.winminwidth = 5 -- Removed (no minimum window width needed)
-- opt.smoothscroll = true -- Removed (not useful)
-- opt.shada = { "'10", "<0", "s10", "h" } -- Removed (using default shada settings)
-- o.switchbuf = "useopen,uselast" -- Removed (not useful)
-- opt.linebreak = true -- Removed (using default linebreak=false when wrap=true)
-- vim.diagnostic.config -- Moved to lua/aru/lsp/init.lua

-- NOTE: This seems to break keeping the visual selection, among other things.
-- opt.list = true -- invisible chars
-- opt.listchars = {
-- 	eol = nil,
-- 	tab = "› ", -- suppress first tab
-- 	extends = "›", -- Alternatives: … »
-- 	precedes = "‹", -- Alternatives: … «
-- 	trail = "•", -- BULLET (U+2022, UTF-8: E2 80 A2)
-- 	-- space = '•', -- BULLET (U+2022, UTF-8: E2 80 A2)
-- }

