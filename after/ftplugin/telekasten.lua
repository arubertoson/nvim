vim.opt_local.spelllang = "en_gb"
vim.opt_local.spell = true
vim.opt_local.number = false
vim.opt_local.relativenumber = false

local ok, cmp = pcall(require, "cmp")
if not ok then
	require("aru").log:debug(string.format("failed to load cmp: %s", cmp))

	return
end

cmp.setup.filetype({"markdown", "telekasten"}, {
	completion = {
		autocomplete = false,
	},
	sources = cmp.config.sources({
		{ name = "dictionary" },
		{ name = "spell" },
	}, {
		{ name = "emoji", trigger_characters = ":" },
		{ name = "latex_symbols", trigger_characters = "\\" },
		{ name = "calc" },
		{ name = "buffer" },
	})
})
