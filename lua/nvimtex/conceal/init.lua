local M = {}
local State = require("nvimtex.conceal.state")
local processor = require("nvimtex.conceal.processor")
local concealer = require("nvimtex.conceal.concealer")
local extmark = require("nvimtex.conceal.extmark")
M.enabled = true
function M.toggle()
	M.enabled = not M.enabled
	M.refresh(vim.api.nvim_win_get_buf(0))
end
M.have_setup = {}

M.config = {
	processor = {},
	extmark = {},
	conceal_cursor = "nvic",
	refresh_events = { "InsertLeave", "BufWritePost" },
	local_refresh_events = { "TextChangedI", "TextChanged" },
	cursor_refresh_events = { "CursorMovedI", "CursorMoved" },
}
function M.refresh(buffer, root)
	vim.schedule(function()
		buffer = buffer or vim.api.nvim_win_get_buf(0)
		vim.api.nvim_buf_clear_namespace(buffer, extmark.ns_id.fast, 0, -1)
		if not root then
			local tree = vim.treesitter.get_parser(buffer, "latex")

			if tree and tree:trees() and tree:trees()[1] then
				root = tree:trees()[1]:root()
			end
		end
		if not root then
			return
		end
		local state = State:new()
		processor.default_processor(root, buffer, state)
	end)
end

--- init for a buffer
---@param buffer table|number
function M.setup_buf(buffer)
	if M.have_setup[buffer] then
		return
	end
	buffer = buffer and (type(buffer) == "number" and buffer or buffer.buf) or vim.api.nvim_get_current_buf()
	local parser = vim.treesitter.get_parser(buffer, "latex")
	if parser and parser:trees()[1] and parser:trees()[1]:root() then
		M.have_setup[buffer] = true
		vim.api.nvim_buf_attach(buffer, false, {
			on_bytes = vim.schedule_wrap(function(_, _, _, sr, sc, sb, oer, oec, oeb, ner, nec, neb)
				parser:parse()
				local mnode = require("nvimtex.conditions").in_math(sr, sc)
				if mnode then
					processor.default_processor(mnode, buffer, State:new())
				end
			end),
		})
		parser:register_cbs({
			on_changedtree = function(ranges, tree)
				---@type TSNode
				local root = tree:root()
				-- local range = ranges[1]
				-- if not range then
				-- 	return
				-- end
				-- local flag = vim.treesitter.node_contains(root, range)
				-- while flag do
				-- 	flag = false
				-- 	for n in root:iter_children() do
				-- 		if vim.treesitter.node_contains(n, range) then
				-- 			flag = n
				-- 		end
				-- 	end
				-- 	if flag then
				-- 		root = flag
				-- 	end
				-- end
				vim.schedule(function()
					M.refresh(buffer, root)
				end)
			end,
		})
		-- if M.config.refresh_events then
		-- 	vim.api.nvim_create_autocmd(M.config.refresh_events, {
		-- 		buffer = buffer,
		-- 		callback = function()
		-- 			M.refresh(buffer)
		-- 		end,
		-- 	})
		-- end
		-- if M.config.local_refresh_events then
		-- 	vim.api.nvim_create_autocmd(M.config.local_refresh_events, {
		-- 		buffer = buffer,
		-- 		callback = function()
		-- 			M.refresh(buffer)
		-- 		end,
		-- 	})
		-- end
		if M.config.cursor_refresh_events then
			vim.api.nvim_create_autocmd(M.config.cursor_refresh_events, {
				buffer = buffer,
				callback = function()
					processor.refresh_cursor()
				end,
			})
		end
		M.refresh(buffer)
		if M.config.conceal_cursor then
			vim.api.nvim_set_option_value("concealcursor", M.config.conceal_cursor, { scope = "local" })
		end

		vim.api.nvim_set_option_value("conceallevel", 2, { scope = "local" })
	else
		vim.defer_fn(function()
			M.setup_buf(buffer)
		end, 50)
	end
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts)
	-- counter.setup(M.config.counter)
	-- extmark.setup(M.config.extmark)
	-- processor.setup(M.config.processor)
	-- vim.schedule(function()
	-- 	M.setup_buf({ buf = vim.api.nvim_get_current_buf() })
	-- end)
	vim.api.nvim_create_autocmd("BufEnter", {
		pattern = "*.tex",
		callback = function(buffer)
			vim.schedule(function()
				M.setup_buf(buffer)
			end)
		end,
	})
	-- vim.keymap.set("n", "K", function()
	-- 	local math_node = require("latex_concealer.conditions.luasnip").in_math()
	-- 	if math_node then
	-- 		require("latex_concealer.processor").node2grid(vim.api.nvim_win_get_buf(0), math_node):show()
	-- 	else
	-- 		vim.api.nvim_exec2("Lspsaga hover_doc", {})
	-- 	end
	-- end)
end

return M
