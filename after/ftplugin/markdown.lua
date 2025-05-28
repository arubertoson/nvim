local setlocal = vim.opt_local

setlocal.spelllang = "en"
setlocal.spell = true
setlocal.number = false
setlocal.relativenumber = false
setlocal.smartindent = true
setlocal.wrap = true

-- local ok, cmp = pcall(require, "cmp")
-- if not ok then
-- 	require("aru.logging").get_logger("AruMarkdown").log:debug(string.format("failed to load cmp: %s", cmp))
--
-- 	return
-- end

-- cmp.setup.filetype({ "markdown", "telekasten" }, {
-- 	completion = {
-- 		autocomplete = false,
-- 	},
-- 	sources = cmp.config.sources({
-- 		{ name = "dictionary" },
-- 		{ name = "spell" },
-- 	}, {
-- 		{ name = "emoji", trigger_characters = ":" },
-- 		{ name = "latex_symbols", trigger_characters = "\\" },
-- 		{ name = "calc" },
-- 		{ name = "buffer" },
-- 	}),
-- })
