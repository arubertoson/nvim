--
-- Core Plugins
--
return {

	{
	  "mozanunal/sllm.nvim",
	  dependencies = {
	    "echasnovski/mini.notify",
	    "echasnovski/mini.pick",
	  },
	  config = function()
	    require("sllm").setup({
	      -- your custom options here
	    })
	  end,
	},
	
	{
		"b0o/SchemaStore.nvim",
		lazy = true,
		version = false, -- last release is way too old
	},
	
}
