return {
	{
		"L3MON4D3/LuaSnip",
		build = "make install_jsregexp",
		dependencies = {
			"nvim-cmp",
			"saadparwaiz1/cmp_luasnip",
		},
		config = function()
			local ls = require("luasnip")

			-- vim.snippet.expand = ls.lsp_expand

			------@diagnostic disable-next-line: duplicate-set-field
			---vim.snippet.active = function(filter)
			---	filter = filter or {}
			---	filter.direction = filter.direction or 1
			---
			---	if filter.direction == 1 then
			---		return ls.expand_or_jumpable()
			---	else
			---		return ls.jumpable(filter.direction)
			---	end
			---end
			---
			------@diagnostic disable-next-line: duplicate-set-field
			---vim.snippet.jump = function(direction)
			---	if direction == 1 then
			---		if ls.expandable() then
			---			return ls.expand_or_jump()
			---		else
			---			return ls.jumpable(1) and ls.jump(1)
			---		end
			---	else
			---		return ls.jumpable(-1) and ls.jump(-1)
			---	end
			---end
			---
			---vim.snippet.stop = ls.unlink_current

			ls.config.set_config({
				history = true,
				updateevents = "TextChanged,TextChangedI",
				override_builtin = true,
			})

			-- for _, ft_path in ipairs(vim.api.nvim_get_runtime_file("lua/custom/snippets/*.lua", true)) do
			--   loadfile(ft_path)()
			-- end

			vim.keymap.set({ "i", "s" }, "<c-k>", function()
				if ls.expand_or_jumpable() then
					ls.expand_or_jump()
				end
			end, { silent = true })

			vim.keymap.set({ "i", "s" }, "<c-l>", function()
				if ls.jumpable(-1) then
					ls.jump(-1)
				end
			end, { silent = true })
			-- vim.keymap.set({ "i", "s" }, "<c-k>", function()
			-- 	return vim.snippet.active({ direction = 1 }) and vim.snippet.jump(1)
			-- end, { silent = true })
			--
			-- vim.keymap.set({ "i", "s" }, "<c-j>", function()
			-- 	return vim.snippet.active({ direction = -1 }) and vim.snippet.jump(-1)
			-- end, { silent = true })
		end,
	},
}
