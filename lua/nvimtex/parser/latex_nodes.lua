local LNode = require("nvimtex.parser.lnode")

local M = {}

-- Neovim reads range/start/end here; LNode implements the same read contract.
---@overload fun(node:Nvimtex._LNode,source:integer|string,opts?:table):string
local get_node_text = vim.treesitter.get_node_text

---Find a direct child by syntax type, without requesting grammar field names.
---@param node? Nvimtex.LNode
---@param node_type string
---@return Nvimtex.LNode?
function M.find_child(node, node_type)
	if node then
		for index = 0, node:child_count() - 1 do
			local child = node:child(index)
			if child and child:type() == node_type then
				return child
			end
		end
	end
end

---Commands start with a command_name or an anonymous command token. A
---declaration group instead contains the command_name between its braces.
---@param node? Nvimtex.LNode
---@return Nvimtex.LNode?
function M.command(node)
	if not node then
		return nil
	end
	if node:type() == "command_name" then
		return node
	end
	local first = node:child(0)
	if first and (first:type() == "command_name" or first:type():sub(1, 1) == "\\") then
		return first
	end
	return M.find_child(node, "command_name")
end

---@param source number|string
---@param node? Nvimtex.LNode
---@return string?
function M.command_name(source, node)
	local command = M.command(node)
	if command then
		local name = get_node_text(command, source):gsub("^\\", "")
		return name
	end
end

---A parsed command owns its command token, optional bracket group, then required
---arguments. Required arguments may be bare tokens, including `[` and `]`.
---Comments do not occupy argument slots. Raw TSNodes use the same child order.
---@param node Nvimtex.LNode
---@return Nvimtex.LNode[]
function M.arguments(node)
	local arguments = {}
	for index = 1, node:child_count() - 1 do
		local child = node:child(index)
		local node_type = child and child:type()
		if
			child
			and node_type ~= "line_comment"
			and node_type ~= "command_name"
			and not node_type:match("^brack_group")
		then
			arguments[#arguments + 1] = child
		end
	end
	return arguments
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.optional_argument(node)
	for index = 1, node:child_count() - 1 do
		local child = node:child(index)
		if child and child:type():match("^brack_group") then
			return child
		end
	end
end

---Definition groups have distinct syntax types, so missing options do not
---change how the declaration, argument count, default and body are identified.
---@param node Nvimtex.LNode
---@return Nvimtex.LNode? declaration
---@return Nvimtex.LNode? argc
---@return Nvimtex.LNode? default
---@return Nvimtex.LNode? body
function M.definition_parts(node)
	local declaration, argc, default, body
	for index = 1, node:child_count() - 1 do
		local child = node:child(index)
		local node_type = child and child:type()
		if node_type == "command_name" or node_type == "curly_group_command_name" then
			declaration = child
		elseif node_type == "brack_group_argc" then
			argc = child
		elseif node_type == "brack_group" then
			default = child
		elseif node_type == "curly_group" then
			body = child
		end
	end
	return declaration, argc, default, body
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.definition_body(node)
	return M.find_child(node, "curly_group")
end

---@param node Nvimtex.LNode
---@param alternative? boolean select the else branch
---@return Nvimtex.LNode?
function M.branch(node, alternative)
	return M.find_child(node, alternative and "else_block" or "if_block")
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.script_base(node)
	return node:child(0)
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.script_argument(node)
	return node:named_child(0)
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.environment_begin(node)
	return node:type() == "begin" and node or M.find_child(node, "begin")
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.environment_name_node(node)
	return M.find_child(M.environment_begin(node), "curly_group_text")
end

---@param source number|string
---@param node? Nvimtex.LNode
---@return string?
function M.environment_name(source, node)
	local name = node and M.environment_name_node(node)
	if name then
		return vim.trim(get_node_text(name, source):gsub("^%{", ""):gsub("%}$", ""))
	end
end

---A verb_group is ordered as delimiter, verb_inner, optional closing delimiter.
---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.verb_open(node)
	return node:child(0)
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.verb_content(node)
	return node:child(1)
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.verb_close(node)
	return node:child(2)
end

---Return the anonymous tokens owned by an argument group, if any.
---@param node Nvimtex.LNode
---@return string?, string?
function M.group_delimiters(node)
	local node_type = node:type()
	if node_type:match("^curly_group") then
		return "{", "}"
	elseif node_type:match("^brack_group") then
		return "[", "]"
	end
end

---Anchor replacement text before a group's closing token, or at a bare arg's end.
---@param node? Nvimtex.LNode
---@return integer?, integer?
function M.closing_delimiter_start(node)
	if not node then
		return nil, nil
	end
	if M.group_delimiters(node) then
		local closing = node:child(node:child_count() - 1)
		if closing then
			return closing:start()
		end
	end
	return node:end_()
end

---Find the document without walking the often large body before it.
---@param root Nvimtex.LNode
---@param source number|string
---@return Nvimtex.LNode?
function M.find_document(root, source)
	if type(root) == "userdata" and root.named_child_count then
		for index = root:named_child_count() - 1, 0, -1 do
			local node = root:named_child(index)
			if node and node:type() == "generic_environment" and M.environment_name(source, node) == "document" then
				return node
			end
		end
	else
		for index = 0, root:child_count() - 1 do
			local node = root:child(index)
			if node and node:type() == "generic_environment" and M.environment_name(source, node) == "document" then
				return node
			end
		end
	end
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.single_body_math_environment(node)
	local result
	for index = 0, node:child_count() - 1 do
		local child = node:child(index)
		if child and child:type() ~= "begin" and child:type() ~= "end" then
			if child:type() ~= "math_environment" or result then
				return nil
			end
			result = child
		end
	end
	return result
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode
function M.without_math_boundary(node)
	local result = LNode:new(node:type())
	result:set_range(node)
	local count = node:child_count()
	for index = 1, count - 2 do
		local child = node:child(index)
		if child and child:type() ~= "begin" and child:type() ~= "end" then
			result:add_child(child)
		end
	end
	return result
end

return M
