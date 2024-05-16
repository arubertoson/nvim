local g = vim.g
local o = vim.o
local opt = vim.opt

----- Interesting Options -----

-- You have to turn this one on :)
opt.inccommand = "split"
--
-- Best search settings :)
opt.smartcase = true
opt.ignorecase = true

opt.clipboard = "unnamedplus"

-- Don't have `o` add a comment
opt.formatoptions:remove "o"

----- Personal Preferences -----
opt.number = true
opt.relativenumber = true

-----------------------------------------------------------------------------//
-- Window splitting and buffers {{{1
-----------------------------------------------------------------------------//
opt.splitbelow = true
opt.splitright = true
opt.eadirection = 'hor'
-- exclude usetab as we do not want to jump to buffers in already open tabs
-- do not use split or vsplit to ensure we don't open any new windows
o.switchbuf = 'useopen,uselast'
opt.fillchars = {
	vert = '▕', -- alternatives │
	fold = ' ',
	eob = ' ', -- suppress ~ at EndOfBuffer
	diff = '╱', -- alternatives = ⣿ ░ ─
	msgsep = '‾',
	foldopen = '▾',
	foldsep = '│',
	foldclose = '▸',
}

-----------------------------------------------------------------------------//
-- Display {{{1
-----------------------------------------------------------------------------//
opt.conceallevel = 0
opt.breakindentopt = 'sbr'
opt.linebreak = true -- lines wrap at words rather than random characters
opt.synmaxcol = 1024 -- don't syntax highlight long lines
opt.signcolumn = 'auto:2-4'
opt.ruler = false
opt.cmdheight = 2 -- Set command line height to two lines
opt.showbreak = [[↪ ]] -- Options include -> '…', '↳ ', '→','↪ '
--- This is used to handle markdown code blocks where the language might
--- be set to a value that isn't equivalent to a vim filetype
g.markdown_fenced_languages = {
	'js=javascript',
	'ts=typescript',
	'shell=sh',
	'bash=sh',
	'console=sh',
}
-----------------------------------------------------------------------------//
-- List chars {{{1
-----------------------------------------------------------------------------//
vim.opt.list = true -- invisible chars
vim.opt.listchars = {
	eol = nil,
	tab = '  ', -- suppress first tab
	extends = '›', -- Alternatives: … »
	precedes = '‹', -- Alternatives: … «
	trail = '•', -- BULLET (U+2022, UTF-8: E2 80 A2)
	space = '•', -- BULLET (U+2022, UTF-8: E2 80 A2)
}
opt.shada = { "'10", "<0", "s10", "h" }

