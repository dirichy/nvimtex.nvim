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
	source_file = function(lnode, source, state)
		local flag = false
		for n, f in lnode:iter_children() do
			if n:type() == "generic_environment" then
				local text = vim.treesitter.get_node_text(n:child(0):child(1):child(1), source)
				flag = text == "document"
				break
			end
		end
		state:set("conceal", not flag)
		return M.feedback.continue
	end,
	generic_environment = function(lnode, source, state)
		local text = vim.treesitter.get_node_text(lnode:child(0):child(1):child(1), source)
		if text == "document" then
			state:set("conceal", true)
		end
		return M.feedback.continue
	end,
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
		if concealer.map.command_name[command_name] or concealer.map.generic_command[command_name] then
			return M.feedback.conceal
		end
	end,
	inline_formula = function(lnode, source, state)
		state:set("mmode", true)
		return M.feedback.conceal, extmark.ns_id.inline
	end,
	displayed_equation = function()
		return M.feedback.conceal, extmark.ns_id.inline
	end,
	math_environment = function()
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

-- ---@param lnode Nvimtex.LNode
-- ---@param state Nvimtex.State
-- ---@param source number|string
-- ---@param p fun(...:any):Nvimtex.processor.feedback
-- ---@return Nvimtex.processor.feedback?,any
-- function M.process_node_with_state(lnode, source, state, p)
-- 	state:addUndoPoint()
-- 	local feedback, res = p(lnode, source, state)
-- 	state:undo()
-- 	return feedback, res
-- end

local extmark_and_buffer_and_ns_id_on_cursor = {}
---@param lnode Nvimtex.LNode
---@param state Nvimtex.State
---@param source number|string
function M.default_processor(lnode, source, state)
	state:addUndoPoint()
	local ltype = lnode:type()
	local feedback = M.feedback.continue
	local res
	if M.processor[ltype] then
		feedback, res = M.processor[ltype](lnode, source, state)
	end
	if feedback == M.feedback.continue or (not state:get("conceal") and feedback == M.feedback.conceal) then
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
			cursor_in_node = vim.treesitter.node_contains(lnode, { line, col, line, col + 1 })
		end
		if cursor_in_node then
			local i = ext_mark[1]
			if i then
				vim.api.nvim_buf_del_extmark(source, res, i[1])
			end
			vim.api.nvim_buf_clear_namespace(source, extmark.ns_id.virtline, 0, -1)
			extmark_and_buffer_and_ns_id_on_cursor[1] =
				concealer
					.default_concealer(lnode, source, state)
					:conceal(source, lnode, extmark.ns_id.virtline, nil, { virtline = true })
			extmark_and_buffer_and_ns_id_on_cursor[2] = source
			extmark_and_buffer_and_ns_id_on_cursor[3] = res
		else
			if #ext_mark == 0 then
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
		state:undo()
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
	local state = State:new()
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	line = line - 1
	local cnode = require("nvimtex.conditions").find_node(line, col, function(node)
		local p = processor.processor[node:type()]
		if p and p(node, b, state) == processor.feedback.conceal then
			return true
		end
		return false
	end)
	if cnode then
		processor.default_processor(cnode, b, state)
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
