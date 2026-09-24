vim.g.loaded_gzip = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_tar = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_zip = 1
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_netrwFileHandlers = 1
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_typecorr = 1
-- Better UX
vim.opt.autowriteall = true
vim.opt.autoread = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.clipboard = "unnamedplus"
vim.opt.scrolloff = 20

vim.opt.cmdheight = 0

-- Indents settings should be delegated to the .editorconfig file
-- vim.opt.tabstop = 2
-- vim.opt.shiftwidth = 2
-- vim.opt.expandtab = true
-- vim.opt.smartindent = true
vim.g.editorconfig = true

-- UI
vim.opt.shortmess:append("I") -- Do not flash the intro screen before workspace resume.
vim.opt.showcmd = false
vim.o.winborder = require("aru.config").ui.border
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.colorcolumn = "100"
vim.opt.showtabline = 1
vim.opt.signcolumn = "yes"
vim.opt.breakindent = true
vim.opt.termguicolors = true
vim.opt.updatetime = 250
vim.opt.showmode = false
vim.opt.laststatus = 3
vim.opt.fillchars = { eob = " " }
vim.go.guicursor = "n-v-sm:block,i-t-ci-ve-c:ver25,r-cr-o:hor20"
-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true

if vim.env.SSH_CLIENT or vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
    vim.g.clipboard = {
        name = "osc52-ssh",
        copy = {
            ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
            ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
        },
        paste = {
            ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
            ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
        },
    }
end
