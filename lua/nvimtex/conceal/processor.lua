local State = require("nvimtex.conceal.state")
local extmark = require("nvimtex.conceal.extmark")
local concealer = require("nvimtex.conceal.concealer")
local inline = require("nvimtex.conceal.inline")
local mathstyle = require("nvimtex.latex.mathstyle")
local LNode = require("nvimtex.parser.lnode")
local hl = require("nvimtex.highlight")
local M = {}
local processor = M
local parser = require("nvimtex.parser")
local generic_command_arg_table = require("nvimtex.parser.generic_command")
---@enum Nvimtex.processor.feedback
M.feedback = {
	continue = 0,
	skip = 1,
	conceal = 2,
}
---@type table<string,fun(lnode:Nvimtex.LNode,source:number,state:Nvimtex.State):Nvimtex.processor.feedback,any>
M.processor = {
	line_comment = function(lnode, source, state)
		local comment = vim.treesitter.get_node_text(lnode, source)
		local match = comment:match("^%%%s*nvimtex:%s*(%S*)%s*$")
		if match then
			if match:match("^enable_parser_command_definition") then
				state:setglobal("parser_command_definition", true)
			end
			if match:match("^disable_parser_command_definition") then
				state:setglobal("parser_command_definition", false)
			end
		end
		return M.feedback.skip
	end,
	generic_command = function(lnode, source, state)
		local command_node = lnode:field("command")[1]
		local command_name = vim.treesitter.get_node_text(command_node, source):sub(2, -1)
		if concealer.map.command_name[command_name] then
			return M.feedback.conceal
		end
	end,
	inline_formula = function()
		return M.feedback.conceal, extmark.ns_id.inline
	end,
	new_command_definition = function(lnode, source, state)
		if not state:get("parser_command_definition") then
			return M.feedback.skip
		end
		local declaration = lnode:field("declaration")[1]
		if not declaration then
			return M.feedback.skip
		end
		local command_name = vim.treesitter.get_node_text(declaration:field("command")[1], source):sub(2, -1)
		if not command_name then
			return M.feedback.skip
		end
		local argc = lnode:field("argc")[1]
		argc = argc and tonumber(vim.treesitter.get_node_text(argc, source):sub(2, -2)) or 0
		local default = lnode:field("default")[1]
		if default then
			argc = argc - 1
		end
		local implementation = lnode:field("implementation")[1]
		if not implementation then
			return M.feedback.skip
		end
		implementation = LNode.remove_bracket(implementation)
		generic_command_arg_table[command_name] = { narg = argc, oarg = default }
		concealer.map.generic_command[command_name] = concealer.expand(implementation, source, argc, default)
		return M.feedback.skip
	end,

	-- (new_command_definition ; [11, 0] - [11, 41]
	--   declaration: (curly_group_command_name ; [11, 11] - [11, 18]
	--     command: (command_name)) ; [11, 12] - [11, 17]
	--   argc: (brack_group_argc ; [11, 18] - [11, 21]
	--     value: (argc)) ; [11, 19] - [11, 20]
	--   default: (brack_group ; [11, 21] - [11, 24]
	--     (text ; [11, 22] - [11, 23]
	--       word: (word))) ; [11, 22] - [11, 23]
	--   implementation: (curly_group ; [11, 24] - [11, 41]
	--     (generic_command ; [11, 25] - [11, 40]
	--       command: (command_name) ; [11, 25] - [11, 32]
	--       arg: (curly_group ; [11, 32] - [11, 40]
	--         (text ; [11, 33] - [11, 39]
	--           word: (word) ; [11, 33] - [11, 37]
	--           word: (placeholder)))))) ; [11, 37] - [11, 39]
}

---@param lnode Nvimtex.LNode
---@param state Nvimtex.State
---@param source number|string
---@param p fun(...:any):Nvimtex.processor.feedback
---@return Nvimtex.processor.feedback?,any
function M.process_node_with_state(lnode, source, state, p)
	state:addUndoPoint()
	local feedback, res = p(lnode, source, state)
	state:undo()
	return feedback, res
end

local extmark_and_buffer_and_ns_id_on_cursor = {}
---@param lnode Nvimtex.LNode
---@param state Nvimtex.State
---@param source number|string
function M.default_processor(lnode, source, state)
	local ltype = lnode:type()
	local feedback = M.feedback.continue
	local res
	if M.processor[ltype] then
		state:addUndoPoint()
		feedback, res = M.processor[ltype](lnode, source, state)
		state:undo()
	end
	if feedback == M.feedback.continue then
		for node in parser.iter_children(lnode, source) do
			state:addUndoPoint()
			M.default_processor(node, source, state)
			state:undo()
		end
	end
	if feedback == M.feedback.conceal then
		if type(source) == "string" then
			return
		end
		res = res or vim.api.nvim_create_namespace("nvimtex")

		local cur_buf = vim.api.nvim_win_get_buf(0)
		local cursor_in_node = false
		local a, b, c, d = lnode:range()
		local ext_mark = vim.api.nvim_buf_get_extmarks(source, res, { a, b }, { a, b + 1 }, {})
		if cur_buf == source then
			local cursor = vim.api.nvim_win_get_cursor(0)
			local line, col = cursor[1], cursor[2]
			line = line - 1
			cursor_in_node = (a == line and b <= col or a < line) and (c == line and d >= col or c > line)
		end
		-- vim.print(vim.api.nvim_buf_get_extmarks(source, res, { a, b }, { a, b + 1 }, { details = true }))
		if #ext_mark == 0 then
			if cursor_in_node then
				vim.api.nvim_buf_clear_namespace(source, extmark.ns_id.virtline, 0, -1)
				extmark_and_buffer_and_ns_id_on_cursor[1] =
					concealer
						.default_concealer(lnode, source, state)
						:conceal(source, lnode, extmark.ns_id.virtline, nil, { virtline = true })
				extmark_and_buffer_and_ns_id_on_cursor[2] = source
				extmark_and_buffer_and_ns_id_on_cursor[3] = res
			else
				concealer.default_concealer(lnode, source, state):conceal(source, lnode, res)
				-- vim.print(
				-- 	vim.api.nvim_buf_get_extmark_by_id(
				-- 		source,
				-- 		res,
				-- 		concealer.default_concealer(lnode, source, state):conceal(source, lnode, res),
				-- 		{ details = true }
				-- 	)
				-- )
			end
		end
	end
	if feedback == M.feedback.skip then
	end
end

function M.refresh_cursor()
	local b, e = extmark_and_buffer_and_ns_id_on_cursor[2], extmark_and_buffer_and_ns_id_on_cursor[1]
	local ns_id_tbl = extmark.ns_id
	if b then
		local cur_b = vim.api.nvim_win_get_buf(0)
		if b == cur_b then
			local line, col = unpack(vim.api.nvim_buf_get_extmark_by_id(b, ns_id_tbl.virtline, e, {}))
			if line then
				local root = LNode.root(b)
				if root then
					local nodes_contain_extmark = parser.descendants_node_covering_range(root, b, line, col)
					local state = State:new()
					for _, n in ipairs(nodes_contain_extmark) do
						local ntype = n:type()
						if
							processor.processor[ntype]
							and processor.processor[ntype](n, b, state) == M.feedback.conceal
						then
							vim.api.nvim_buf_del_extmark(b, extmark.ns_id.virtline, e)
							processor.default_processor(n, b, state)
							break
						end
					end
				end
			end
		end
	end
	b = vim.api.nvim_win_get_buf(0)
	local r, c = unpack(vim.api.nvim_win_get_cursor(0))
	r = r - 1
	local extmarks = vim.api.nvim_buf_get_extmarks(b, extmark.ns_id.inline, { r, 0 }, { r, c }, { details = true })
	for _, mark in ipairs(extmarks) do
		local extstart = mark[3]
		local extend = mark[4].end_col
		if extstart <= c and c <= extend then
			local text = inline:new(mark[4].virt_text)
			extmark_and_buffer_and_ns_id_on_cursor = {
				text:conceal(
					b,
					{ mark[2], mark[3], mark[4].end_row, mark[4].end_col },
					ns_id_tbl.virtline,
					{},
					{ virtline = true }
				),
				b,
				ns_id_tbl.virtline,
			}
			vim.api.nvim_buf_del_extmark(b, ns_id_tbl.inline, mark[1])
			-- mark[4].virt_lines = { mark[4].virt_text }
			-- mark[4].virt_text = nil
			-- mark[4].ns_id = nil
			-- mark[4].conceal = nil
			-- mark[4].id = mark[1]
			break
		end
	end
end

function M.test()
	local buffer = vim.api.nvim_win_get_buf(0)
	local root
	local tree = vim.treesitter.get_parser(buffer, "latex")
	if tree and tree:trees() and tree:trees()[1] then
		root = tree:trees()[1]:root()
	end
	local state = State:new()
	M.default_processor(root, buffer, state)
end

return M
