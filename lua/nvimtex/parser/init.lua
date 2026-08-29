local LNode = require("nvimtex.parser.lnode")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local Context = require("nvimtex.parser.context")
local command_specs = require("nvimtex.parser.command_specs")
local Stream = require("nvimtex.parser.stream")

local M = {}

local parse_atom
local parse_next

local function is_script_node(node)
	local node_type = node:type()
	return node_type == "subscript" or node_type == "superscript"
end

---@param node Nvimtex.LNode
---@param node_type string
---@return Nvimtex.LNode
local function command_marker(node, node_type)
	local marker = LNode:new(node:field("command")[1] or node:child(0))
	marker._type = node_type
	return marker
end

---@param node Nvimtex.LNode
---@param node_type string
---@return Nvimtex.LNode
local function empty_block(node, node_type)
	local block = LNode:new(node_type)
	local a, b, x = node:start()
	block:set_range(a, b, x, a, b, x)
	return block
end

---@param result Nvimtex.LNode
---@param block Nvimtex.LNode?
---@param node Nvimtex.LNode
---@param field string?
---@param in_else_branch boolean
---@return Nvimtex.LNode
local function append_to_block(result, block, node, field, in_else_branch)
	if block then
		block:add_child(node, field)
		return block
	end

	local node_type = in_else_branch and "else_block" or "if_block"
	block = LNode:new(node_type)
	block:add_child(node, field)
	block:set_start(node)
	result:add_child(block, node_type)
	return block
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@param node Nvimtex.LNode
---@param field string?
---@return Nvimtex.LNode, string?
local function parse_command(stream, source, node, field)
	local command_name = latex_nodes.command_name(source, node)
	if command_name == "ifmmode" then
		return M.parse_if_statement(stream, source, node, field)
	end

	local spec = command_specs[command_name]
	if not spec then
		return node, field
	end

	local ctx = Context:new(stream, source, {
		parse_atom = parse_atom,
		parse_next = parse_next,
	})
	if spec.parse then
		return spec.parse(ctx, node, field)
	end

	local result = LNode:new(node)
	if spec.oarg then
		local next_node = stream:peek()
		if next_node and next_node:type() == "[" then
			local optional_arg = ctx:read_group("[", "]", "brack_group", "optional_arg")
			if optional_arg then
				result:add_child(optional_arg, "optional_arg")
				result:set_end(optional_arg)
			end
		end
	end

	local arg_count = #result:field("arg")
	while arg_count < (spec.narg or 0) do
		local arg = ctx:read_argument()
		if not arg then
			result:set_end()
			return result, field
		end

		result:add_child(arg, "arg")
		result:set_end(arg)
		arg_count = arg_count + 1
	end

	return result, field
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@param begin_node Nvimtex.LNode
---@param result_field string?
---@return Nvimtex.LNode, string?
function M.parse_if_statement(stream, source, begin_node, result_field)
	local result = LNode:new("if_statement")
	result:add_child(command_marker(begin_node, "if"), "if")
	result:set_start(begin_node)

	local block
	local in_else_branch = false
	while true do
		local node, field = parse_next(stream, source)
		if not node then
			if block then
				block:set_end()
			end
			return result, result_field
		end

		local command_name = node:type() == "generic_command" and latex_nodes.command_name(source, node) or nil
		if command_name == "else" then
			if block then
				block:set_end()
			else
				result:add_child(empty_block(node, "if_block"), "if_block")
			end
			block = nil
			in_else_branch = true
			result:add_child(command_marker(node, "else"), "else")
		elseif command_name == "fi" then
			if block then
				block:set_end()
			elseif not in_else_branch then
				result:add_child(empty_block(node, "if_block"), "if_block")
			end
			result:add_child(command_marker(node, "fi"), "fi")
			result:set_end(node)
			return result, result_field
		else
			block = append_to_block(result, block, node, field, in_else_branch)
		end
	end
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@return Nvimtex.LNode?, string?
function parse_next(stream, source)
	local node, field = parse_atom(stream, source)
	if not node or is_script_node(node) or not stream.fold_scripts then
		return node, field
	end

	local next_node = stream:peek()
	if not next_node or not is_script_node(next_node) then
		return node, field
	end

	local result = LNode:new("script")
	result:add_child(node, "base")
	result:set_start(node)
	while next_node and is_script_node(next_node) do
		local script_node = stream:next()
		result:add_child(script_node, script_node:type())
		result:set_end(script_node)
		next_node = stream:peek()
	end
	return result, field
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@return Nvimtex.LNode?, string?
function parse_atom(stream, source)
	local node, field = stream:next()
	if not node then
		return nil
	end

	if node:type() == "generic_command" then
		return parse_command(stream, source, node, field)
	end

	return node, field
end

---@param root Nvimtex.LNode
---@param source number|string
---@return fun(): Nvimtex.LNode?, string?
function M.iter_children(root, source)
	local stream = Stream:new(root)
	return function()
		return parse_next(stream, source)
	end
end

function M:sexpr(node, field, source, result, range_comment)
	local root = false
	if not result then
		root = true
	end
	result = result or {}
	range_comment = range_comment or {}
	source = source or vim.api.nvim_win_get_buf(0)
	node = node or vim.treesitter.get_parser(source, "latex"):trees()[1]:root()
	table.insert(result, (field and field .. ": " or "") .. "(" .. node:type())
	local a, b, c, d = node:range()
	table.insert(range_comment, " ; [" .. a .. ", " .. b .. "] - [" .. c .. ", " .. d .. "]")
	for child, child_field in M.iter_children(node, source) do
		self:sexpr(child, child_field, source, result, range_comment)
	end
	result[#result] = result[#result] .. ")"
	if root then
		for index, value in ipairs(range_comment) do
			result[index] = result[index] .. value
		end
		return table.concat(result, "\n")
	end
end

---@param root Nvimtex.LNode?
---@param source number?
---@param a integer
---@param b integer
---@param c integer
---@param d integer
---@return Nvimtex.LNode[]
---@overload fun(root:Nvimtex.LNode?,source:number?,win:number?):Nvimtex.LNode[]
---@overload fun(root:Nvimtex.LNode?,source:number?,line:number,col:number):Nvimtex.LNode[]
function M.descendants_node_covering_range(root, source, a, b, c, d)
	if not source then
		if a and not b then
			source = vim.api.nvim_win_get_buf(a)
		else
			source = vim.api.nvim_win_get_buf(0)
		end
	end
	if not root then
		local tree = vim.treesitter.get_parser(source, "latex")
		if tree and tree:trees() and tree:trees()[1] then
			root = tree:trees()[1]:root()
		else
			return {}
		end
	end
	if not b then
		local cursor = vim.api.nvim_win_get_cursor(a or 0)
		a, b = cursor[1] - 1, cursor[2]
	end
	if not d then
		c, d = a, b + 1
	end

	local result = {}
	local node = root
	while LNode.contains(node, a, b, c, d) do
		table.insert(result, node)
		local child_covering_range
		for child in M.iter_children(node, source) do
			if LNode.contains(child, a, b, c, d) then
				child_covering_range = child
				break
			end
		end
		if not child_covering_range then
			break
		end
		node = child_covering_range
	end
	return result
end

return M
