local LNode = require("nvimtex.parser.lnode")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local Context = require("nvimtex.parser.context")
local command_specs = require("nvimtex.parser.command_specs")
local Stream = require("nvimtex.parser.stream")

local M = {}

-- Document definitions must not change parsing in another buffer.
---@type table<integer,table<string,table>>
M.buffer_command_specs = {}

---@param name string
---@param source number|string
---@return table?
function M.command_spec(name, source)
	local specs = type(source) == "number" and M.buffer_command_specs[source]
	return specs and specs[name] or command_specs[name]
end

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
	local marker = LNode:new(latex_nodes.command(node) or node:child(0))
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
---@param in_else_branch boolean
---@return Nvimtex.LNode
local function append_to_block(result, block, node, in_else_branch)
	if block then
		block:add_child(node)
		return block
	end

	local node_type = in_else_branch and "else_block" or "if_block"
	block = LNode:new(node_type)
	block:add_child(node)
	block:set_start(node)
	result:add_child(block)
	return block
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@param node Nvimtex.LNode
---@return Nvimtex.LNode
local function parse_command(stream, source, node)
	local command_name = latex_nodes.command_name(source, node)
	if command_name == "ifmmode" then
		return M.parse_if_statement(stream, source, node)
	end

	local spec = M.command_spec(command_name, source)
	if not spec then
		return node
	end

	local ctx = Context:new(stream, source, {
		parse_atom = parse_atom,
		parse_next = parse_next,
	})
	if spec.parse then
		return spec.parse(ctx, node)
	end

	local result = LNode:new(node)
	if spec.oarg then
		local next_node = stream:peek()
		if next_node and next_node:type() == "[" then
			local optional_arg = ctx:read_group("[", "]", "brack_group")
			if optional_arg then
				result:add_child(optional_arg)
				result:set_end(optional_arg)
			end
		end
	end

	local arg_count = #latex_nodes.arguments(result)
	while arg_count < (spec.narg or 0) do
		local arg = ctx:read_argument()
		if not arg then
			result:set_end()
			return result
		end

		result:add_child(arg)
		result:set_end(arg)
		arg_count = arg_count + 1
	end

	return result
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@param begin_node Nvimtex.LNode
---@return Nvimtex.LNode
function M.parse_if_statement(stream, source, begin_node)
	local result = LNode:new("if_statement")
	result:add_child(command_marker(begin_node, "if"))
	result:set_start(begin_node)

	local block
	local in_else_branch = false
	while true do
		local node = parse_next(stream, source)
		if not node then
			if block then
				block:set_end()
			end
			return result
		end

		local command_name = node:type() == "generic_command" and latex_nodes.command_name(source, node) or nil
		if command_name == "else" then
			if block then
				block:set_end()
			else
				result:add_child(empty_block(node, "if_block"))
			end
			block = nil
			in_else_branch = true
			result:add_child(command_marker(node, "else"))
		elseif command_name == "fi" then
			if block then
				block:set_end()
			elseif not in_else_branch then
				result:add_child(empty_block(node, "if_block"))
			end
			result:add_child(command_marker(node, "fi"))
			result:set_end(node)
			return result
		else
			block = append_to_block(result, block, node, in_else_branch)
		end
	end
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@return Nvimtex.LNode?
function parse_next(stream, source)
	local node = parse_atom(stream, source)
	if not node or is_script_node(node) or not stream.fold_scripts then
		return node
	end

	local next_node = stream:peek()
	if not next_node or not is_script_node(next_node) then
		return node
	end

	local result = LNode:new("script")
	result:add_child(node)
	result:set_start(node)
	while next_node and is_script_node(next_node) do
		local script_node = stream:next()
		result:add_child(script_node)
		result:set_end(script_node)
		next_node = stream:peek()
	end
	return result
end

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@return Nvimtex.LNode?
function parse_atom(stream, source)
	local node = stream:next()
	if not node then
		return nil
	end

	if node:type() == "generic_command" then
		return parse_command(stream, source, node)
	end

	return node
end

---@param root Nvimtex.LNode
---@param source number|string
---@param opts? Nvimtex.Parser.StreamOptions
---@return fun(): Nvimtex.LNode?
function M.iter_children(root, source, opts)
	local stream = Stream:new(root, opts)
	return function()
		return parse_next(stream, source)
	end
end

---Collect logical children, removing only a group's own delimiter tokens.
---Literal brackets inside the group remain part of its contents.
---@param node Nvimtex.LNode
---@param source number|string
---@return Nvimtex.LNode[]
function M.content_nodes(node, source)
	local children = {}
	for child in M.iter_children(node, source) do
		children[#children + 1] = child
	end
	local opening, closing = latex_nodes.group_delimiters(node)
	if opening then
		if children[#children] and children[#children]:type() == closing then
			table.remove(children)
		end
		if children[1] and children[1]:type() == opening then
			table.remove(children, 1)
		end
	end
	return children
end

---Lay out command arguments with the optional slot first. The array may have
---a hole at slot 1; callers must use the returned count instead of # or ipairs.
---@param node Nvimtex.LNode
---@param optional? boolean
---@return table<integer,Nvimtex.LNode> nodes
---@return integer count
function M.command_arguments(node, optional)
	local nodes = {}
	local shift = optional and 1 or 0
	if optional then
		nodes[1] = latex_nodes.optional_argument(node)
	end
	local required = latex_nodes.arguments(node)
	for index, argument in ipairs(required) do
		nodes[index + shift] = argument
	end
	return nodes, #required + shift
end

function M:sexpr(node, source, result, range_comment)
	local root = false
	if not result then
		root = true
	end
	result = result or {}
	range_comment = range_comment or {}
	source = source or vim.api.nvim_win_get_buf(0)
	node = node or vim.treesitter.get_parser(source, "latex"):trees()[1]:root()
	table.insert(result, "(" .. node:type())
	local a, b, c, d = node:range()
	table.insert(range_comment, " ; [" .. a .. ", " .. b .. "] - [" .. c .. ", " .. d .. "]")
	for child in M.iter_children(node, source) do
		self:sexpr(child, source, result, range_comment)
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
