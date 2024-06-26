local function golden_ratio()
	-- We check the current width of the existing window and
	-- overwrite the no-neck-pain config
	return math.floor(vim.o.columns / 1.618)
end

return {
	{
		"shortcuts/no-neck-pain.nvim",
		cmd = { "NoNeckPain" },
		keys = {
			{
				"<leader>o",
				function()
					local nnp = require("no-neck-pain")

					-- For some reason if we don't use the normal "command"
					-- routes we have to set the options our selves.
					if nnp.config == nil then
						local opts = require("no-neck-pain.config")
						nnp.config = opts.options
					end

					nnp.config.width = golden_ratio()
					nnp.toggle()
				end,
			},
		},
		config = function()
			require("aru.utils").create_augroup("no-neck-pain-resize", {
				{
					event = { "VimResized" },
					command = function()
						local nnp = require("no-neck-pain")

						if nnp.state == nil then
							return
						end

						nnp.resize(golden_ratio())
					end,
				},
			})
		end,
	},
}
