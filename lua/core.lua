--
-- Core Plugins
--
return {
	{ "nvim-lua/plenary.nvim" },
	{ "Tastyep/structlog.nvim", lazy = true },

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
	  "yetone/avante.nvim",
	  event = "VeryLazy",
	  version = false, -- Never set this value to "*"! Never!
	  opts = {
	    -- add any opts here
	    -- for example
	    provider = "openai",
	    openai = {
	      endpoint = "https://api.openai.com/v1",
	      model = "gpt-4o", -- your desired model (or use gpt-4o, etc.)
	      timeout = 30000, -- Timeout in milliseconds, increase this for reasoning models
	      temperature = 0,
	      max_completion_tokens = 8192, -- Increase this to include reasoning tokens (for reasoning models)
	      --reasoning_effort = "medium", -- low|medium|high, only used for reasoning models
	    },
	  },
	  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
	  build = "make",
	  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
	  dependencies = {
	    "nvim-treesitter/nvim-treesitter",
	    "stevearc/dressing.nvim",
	    "nvim-lua/plenary.nvim",
	    "MunifTanjim/nui.nvim",
	    --- The below dependencies are optional,
	    "echasnovski/mini.pick", -- for file_selector provider mini.pick
	    "nvim-telescope/telescope.nvim", -- for file_selector provider telescope
	    "hrsh7th/nvim-cmp", -- autocompletion for avante commands and mentions
	    "ibhagwan/fzf-lua", -- for file_selector provider fzf
	    "nvim-tree/nvim-web-devicons", -- or echasnovski/mini.icons
	    "zbirenbaum/copilot.lua", -- for providers='copilot'
	    {
	      -- support for image pasting
	      "HakonHarnes/img-clip.nvim",
	      event = "VeryLazy",
	      opts = {
		-- recommended settings
		default = {
		  embed_image_as_base64 = false,
		  prompt_for_file_name = false,
		  drag_and_drop = {
		    insert_mode = true,
		  },
		  -- required for Windows users
		  use_absolute_path = true,
		},
	      },
	    },
	    {
	      -- Make sure to set this up properly if you have lazy=true
	      'MeanderingProgrammer/render-markdown.nvim',
	      opts = {
		file_types = { "markdown", "Avante" },
	      },
	      ft = { "markdown", "Avante" },
	    },
	  },
	},
	{
		"b0o/SchemaStore.nvim",
		lazy = true,
		version = false, -- last release is way too old
	},
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		---@type snacks.Config
		opts = {
			-- your configuration comes here
			-- or leave it empty to use the default settings
			-- refer to the configuration section below
			bigfile = { enabled = true },
			dim = { enabled = true },
			zen = { enabled = true },
			input = { 
			  layout = {
			    cycle = true,
			    --- Use the default layout or vertical if the window is too narrow
			    preset = function()
			      return vim.o.columns >= 79 and "default" or "vertical"
			    end,
			  },
			},
			picker = { enabled = true },
			notifier = { enabled = true, timeout = 3000 },
			terminal = { enabled = true },
			quickfile = { enabled = true },
			scope = { enabled = true },
			statuscolumn = { enabled = true },
			words = { enabled = true },
			styles = {
				zen = {
					enter = true,
					fixbuf = false,
					minimal = false,
					width = 180,
					height = 0,
					backdrop = { transparent = false },
					keys = { q = false },
					zindex = 40,
					wo = {
						winhighlight = "NormalFloat:Normal",
					},
					w = {
						snacks_main = true,
					},
				},
			},
		},
		keys = {
			-- Top Pickers & Explorer
			{
				"<leader>ff",
				function()
					Snacks.picker.smart()
				end,
				desc = "Smart Find Files",
			},
			{
				"<leader>fs",
				function()
					Snacks.picker.grep()
				end,
				desc = "Grep",
			},
			{
				"<leader>fw",
				function()
					Snacks.picker.grep_word()
				end,
				desc = "Visual selection or word",
				mode = { "n", "x" },
			},
			{
				"<leader>fl",
				function()
					Snacks.picker.lines()
				end,
				desc = "Buffer Lines",
			},
			{
				"<leader>:",
				function()
					Snacks.picker.command_history()
				end,
				desc = "Command History",
			},
			{
				"<leader>fc",
				function()
					Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
				end,
				desc = "Find Config File",
			},
			{
				"<leader>fg",
				function()
					Snacks.picker.git_files()
				end,
				desc = "Find Git Files",
			},
			{
				"<leader>gd",
				function()
					Snacks.picker.git_diff()
				end,
				desc = "Git Diff (Hunks)",
			},
			-- search
			{
				"<leader>sd",
				function()
					Snacks.picker.diagnostics()
				end,
				desc = "Diagnostics",
			},
			{
				"<leader>sD",
				function()
					Snacks.picker.diagnostics_buffer()
				end,
				desc = "Buffer Diagnostics",
			},
			{
				"<leader>sh",
				function()
					Snacks.picker.help()
				end,
				desc = "Help Pages",
			},
			{
				"<leader>sj",
				function()
					Snacks.picker.jumps()
				end,
				desc = "Jumps",
			},
			{
				"<leader>sk",
				function()
					Snacks.picker.keymaps()
				end,
				desc = "Keymaps",
			},
			{
				"<leader>sl",
				function()
					Snacks.picker.loclist()
				end,
				desc = "Location List",
			},
			{
				"<leader>sm",
				function()
					Snacks.picker.marks()
				end,
				desc = "Marks",
			},
			{
				"<leader>sM",
				function()
					Snacks.picker.man()
				end,
				desc = "Man Pages",
			},
			{
				"<leader>sp",
				function()
					Snacks.picker.lazy()
				end,
				desc = "Search for Plugin Spec",
			},
			{
				"<leader>sq",
				function()
					Snacks.picker.qflist()
				end,
				desc = "Quickfix List",
			},
			-- LSP
			{
				"gd",
				function()
					Snacks.picker.lsp_definitions()
				end,
				desc = "Goto Definition",
			},
			{
				"gD",
				function()
					Snacks.picker.lsp_declarations()
				end,
				desc = "Goto Declaration",
			},
			{
				"gr",
				function()
					Snacks.picker.lsp_references()
				end,
				nowait = true,
				desc = "References",
			},
			{
				"gI",
				function()
					Snacks.picker.lsp_implementations()
				end,
				desc = "Goto Implementation",
			},
			{
				"gy",
				function()
					Snacks.picker.lsp_type_definitions()
				end,
				desc = "Goto T[y]pe Definition",
			},
			{
				"<leader>ss",
				function()
					Snacks.picker.lsp_symbols()
				end,
				desc = "LSP Symbols",
			},
			{
				"<leader>sS",
				function()
					Snacks.picker.lsp_workspace_symbols()
				end,
				desc = "LSP Workspace Symbols",
			},
			{
				"<c-n>",
				function()
					Snacks.terminal()
				end,
				desc = "Toggle Terminal",
			},
			{
				"]]",
				function()
					Snacks.words.jump(vim.v.count1)
				end,
				desc = "Next Reference",
				mode = { "n", "t" },
			},
			{
				"[[",
				function()
					Snacks.words.jump(-vim.v.count1)
				end,
				desc = "Prev Reference",
				mode = { "n", "t" },
			},
			{
				"<leader>gg",
				function()
					Snacks.lazygit()
				end,
				desc = "Lazygit",
			},
			{
				"<leader>bd",
				function()
					Snacks.bufdelete()
				end,
				desc = "Delete Buffer",
			},
			{
				"<leader>.",
				function()
					Snacks.scratch()
				end,
				desc = "Toggle Scratch Buffer",
			},
			{
				"<leader>S",
				function()
					Snacks.scratch.select()
				end,
				desc = "Select Scratch Buffer",
			},
			{
				"<leader>z",
				function()
					Snacks.zen()
				end,
				desc = "Toggle Zen Mode",
			},
			{
				"<leader>Z",
				function()
					Snacks.zen.zoom()
				end,
				desc = "Toggle Zoom",
			},
		},
	},
}
