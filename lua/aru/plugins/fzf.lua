local fzf = require("fzf-lua")
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
			["ctrl-y"] = function(selected)
				if #selected > 0 then
					local msg = selected[1]
					vim.fn.setreg("+", msg)
					vim.notify("Copied to clipboard: " .. msg)
				end
			end,
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
