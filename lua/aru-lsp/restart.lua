function restart_lsp(name)
	local settings = {}
	for _, client in pairs(vim.lsp.get_clients()) do
		if client.name == name then
			vim.print("Killing `" .. name .. "'")
			settings = client.config
			client.stop()
		end
	end

	vim.print("Starting `" .. name .. "'")
	require("lspconfig")[name].setup({
		capabilities = settings.capabilities,
		settings = settings.settings,
		flags = settings.flags,
	})
end

vim.api.nvim_create_user_command("LspRefresh", function(o)
	RestartLsp(o.fargs[1])
end, {
	nargs = "?",
	complete = function()
		local clients = {}
		for idx, client in pairs(vim.lsp.get_clients()) do
			clients[idx] = client.name
		end
		return clients
	end,
})

return {}


