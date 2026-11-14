local LNode = require("nvimtex.parser.lnode")

local M = {}

---@param buf number|string
---@param node Nvimtex.LNode?
---@return string?
local function node_text(buf, node)
	if not node then
		return nil
	end
	return vim.treesitter.get_node_text(node, buf)
end

---@param buf number|string
---@param node Nvimtex.LNode?
---@return string?
function M.command_name(buf, node)
	local command = node and node:field("command")[1]
	local text = node_text(buf, command or node)
	if not text then
		return nil
	end
	local name = text:gsub("^\\", "")
	return name
end

---@param buf number|string
---@param node Nvimtex.LNode?
---@return string?
function M.environment_name(buf, node)
	if not node then
		return nil
	end
	local begin = node:type() == "begin" and node or node:field("begin")[1]
	local name = begin and begin:field("name")[1]
	local text = node_text(buf, name)
	if not text then
		return nil
	end
	return vim.trim(text:gsub("^%{", ""):gsub("%}$", ""))
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
			if node:type() == "generic_environment" and M.environment_name(source, node) == "document" then
				return node
			end
		end
	else
		for node in root:iter_children() do
			if node:type() == "generic_environment" and M.environment_name(source, node) == "document" then
				return node
			end
		end
	end
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode?
function M.single_body_math_environment(node)
	local result
	for child, field in node:iter_children() do
		if field ~= "begin" and field ~= "end" then
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
	local index = 0
	for child, field in node:iter_children() do
		index = index + 1
		if child and index ~= 1 and index ~= count and field ~= "begin" and field ~= "end" then
			result:add_child(child, field)
		end
	end
	return result
end

return M
