--- fzf-lua configuration.
---
--- Role:
---   Generic picker layer retained during the fff migration.
---
--- Keep here:
---   - vim.ui.select
---   - help tags
---   - LSP symbols, diagnostics, locations, and code actions
---   - custom selection actions, such as copying picker entries
---
--- Do not add new file search or live-grep workflows here. Use fff for those.
---
--- See: docs/fzf-fff-migration.md

local fzf = require("fzf-lua")

local function copy_fzf_selection(selected)
	if #selected == 0 then
		return
	end

	local text = table.concat(selected, "\n")
	vim.fn.setreg("+", text)
	vim.notify(string.format("Copied %d fzf item(s) to clipboard", #selected))
end

fzf.setup({
	"hide",
	fzf_opts = { ["--cycle"] = true },
	files = {
		git_icons = false,
	},
	winopts = {
		row = 0.25,
		width = 0.6,
		height = 0.5,
		title_flags = false,
		preview = {
			hidden = true,
			scrollbar = false,
		},
		backdrop = 100,
	},
    actions = {
        files = {
            ["default"] = fzf.actions.file_edit,
			["ctrl-y"] = copy_fzf_selection,
			["alt-y"] = { fn = copy_fzf_selection, prefix = "select-all+" },
        }
    },
	keymap = {
		fzf = {
			["ctrl-q"] = "select-all+accept",
            ["ctrl-y"] = "accept",
		},
		builtin = {
			true,
			["<esc>"] = "hide",
			["<C-d>"] = "preview-page-down",
			["<C-u>"] = "preview-page-up",
		},
	},
})
fzf.register_ui_select()
