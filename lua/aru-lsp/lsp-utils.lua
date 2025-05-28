local M = {}

local fmt = string.format
local aru = require("aru")

---@type table<string, { clients: table<vim.lsp.Client, table<number, boolean>>, callback?: fun(client:vim.lsp.Client, buffer:number):nil }>
M._supports_method = {}

---@param on_attach fun(client:vim.lsp.Client, buffer)
---@param name? string
function M.on_attach(on_attach, name)
	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local buffer = args.buf
			local client = vim.lsp.get_client_by_id(args.data.client_id)

			-- Exit out early in case our client is invalid for whatever reason
			if not client then
				return
			end

			aru.log:debug(
				fmt("%s lsp client executing on_attach for scope %s", client.name, name or "global")
			)

			-- this acts as a filter that we can use to manage on_attach on many
			-- different abstractions. It acts as a filter to ensure that only wanted
			-- clients are calling their "on_attach" function.
			if client and (not name or client.name == name) then
				aru.log:debug(fmt("%s %s scope callback executed", client.name, name or "global"))

				on_attach(client, buffer)
			end
		end,
	})
end

---@param fn fun(client:vim.lsp.Client, buffer):boolean?
function M.on_dynamic_capability(fn)
	-- To enable the dynamic check we create start watching for a custom event that will be
	-- triggered manually when we encounter a new usable method during lsp runtime. We are then
	-- able to perform some extra setup through the given callback function, but only if we
	-- still have a valid client.
	vim.api.nvim_create_autocmd("User", {
		pattern = "LspDynamicCapability",
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			local buffer = args.data.buffer

			if not client then
				aru.log:error("failed to setup new capability missing client.")
				return
			end

			aru.log:debug(fmt("%s registered a dynamicCapability, executing setup.", client.name))

			fn(client, buffer)
		end,
	})
end

---@param method string
---@param fn fun(client:vim.lsp.Client, buffer)
function M.on_supports_method(method, fn)
	M._supports_method[method] = M._supports_method[method] or { clients = {} }
	M._supports_method[method].callback = fn
end

local function _on_support_autocmd()
	-- We populate the _supports_method table with methods we want to look for, these methods
	-- are attached with a event call back if the lsp dynamically lets us know that it's
	-- supported.
	vim.api.nvim_create_autocmd("User", {
		pattern = "LspSupportsMethod",
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			local buffer = args.data.buffer

			if not client then
				return
			end

			local method = M._supports_method[args.data.method]
			if method ~= nil then
				aru.log:debug(fmt("Registering %s capability for %s", args.data.method, client.name))

				method.callback(client, buffer)
			end
		end,
	})
end

---@param client vim.lsp.Client
---@param buffer number
function M._check_methods(client, buffer)
	-- We need to ensure that we are working with a valid buffer, if we are not, none of the
	-- checks will provide any meaningful results.
	if
		not vim.api.nvim_buf_is_valid(buffer)
		or not vim.bo[buffer].buflisted
		or vim.bo[buffer].buftype == "nofile"
	then
		return
	end

	-- We go through all the "registered" methods we want to check, if the client has already
	-- been triggered once we cache that in the _supports_method table to avoid additional
	-- setup.
	for method, clients in pairs(M._supports_method) do
		clients[client] = clients[client] or {}
		if not clients[client][buffer] and client.supports_method(method, { bufnr = buffer }) then
			clients[client][buffer] = true

			aru.log:debug(
				fmt(
					"%s supports method: %s, trigger LspSupportsMethod event for buffer %d",
					client.name,
					method,
					buffer
				)
			)

			vim.api.nvim_exec_autocmds("User", {
				pattern = "LspSupportsMethod",
				data = { client_id = client.id, buffer = buffer, method = method },
			})
		end
	end
end

function M.setup()
	local handler_name = "client/registerCapability"

	aru.log:debug(fmt("wrap original %s with custom LsreplacingpDynamicCapability trigger", handler_name))

	local orig_handler = vim.lsp.handlers[handler_name]
	vim.lsp.handlers[handler_name] = function(err, res, ctx)
		local ret = orig_handler(err, res, ctx)

		aru.log:debug(vim.inspect(ctx))

		local client = vim.lsp.get_client_by_id(ctx.client_id)
		if client then
			for buffer in pairs(client.attached_buffers) do
				vim.api.nvim_exec_autocmds("User", {
					pattern = "LspDynamicCapability",
					data = { client_id = client.id, buffer = buffer },
				})
			end
		end

		return ret
	end

	_on_support_autocmd()
	M.on_attach(M._check_methods)
	M.on_dynamic_capability(M._check_methods)
end

M.toggle = {}

function M.toggle.inlay_hint(bufnr)
	local ih = vim.lsp.inlay_hint

	ih.enable(not ih.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
end

function M.toggle.codelens(bufnr)
	vim.lsp.codelens.refresh({ bufnr = bufnr })

	vim.defer_fn(function()
		vim.lsp.codelens.clear()
	end, 5000)
end

return M
