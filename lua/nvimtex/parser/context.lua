local LNode = require("nvimtex.parser.lnode")

local M = {}
M.__index = M

---@class Nvimtex.Parser.Context
---@field stream Nvimtex.Parser.Stream
---@field source number|string
---@field parsers table

---@param stream Nvimtex.Parser.Stream
---@param source number|string
---@param parsers table
---@return Nvimtex.Parser.Context
function M:new(stream, source, parsers)
	return setmetatable({
		stream = stream,
		source = source,
		parsers = parsers,
	}, M)
end

---@param node_type string|Nvimtex.LNode?
---@return Nvimtex.LNode
function M:make_node(node_type)
	return LNode:new(node_type)
end

---@param node Nvimtex.LNode?
---@return string?
function M:node_text(node)
	if not node then
		return nil
	end
	return vim.treesitter.get_node_text(node, self.source)
end

---@return Nvimtex.LNode?, string?
function M:next_raw()
	return self.stream:next()
end

---@return Nvimtex.LNode?, string?
function M:peek_raw()
	return self.stream:peek()
end

---@param node Nvimtex.LNode
---@param field string?
function M:push_front(node, field)
	self.stream:push_front(node, field)
end

---@return Nvimtex.LNode?, string?
function M:next_atom()
	return self.parsers.parse_atom(self.stream, self.source)
end

---@return Nvimtex.LNode?, string?
function M:next_node()
	return self.parsers.parse_next(self.stream, self.source)
end

---@param node Nvimtex.LNode
---@param start_offset integer
---@param end_offset integer
---@param node_type string?
---@return Nvimtex.LNode
function M:slice_node(node, start_offset, end_offset, node_type)
	local row, col, byte, end_row, end_col, end_byte = node:range(true)
	local result = LNode:new(node_type or node:type())
	result:set_range(row, col + start_offset, byte + start_offset, end_row, end_col, end_byte)
	result:set_end(row, col + end_offset, byte + end_offset)
	return result
end

---@param node Nvimtex.LNode
---@param head_type string?
---@return Nvimtex.LNode, Nvimtex.LNode?
function M:split_first_char(node, head_type)
	local text = self:node_text(node) or ""
	if #text <= 1 then
		return node, nil
	end
	return self:slice_node(node, 0, 1, head_type), self:slice_node(node, 1, #text)
end

---@return Nvimtex.LNode?, string?
function M:read_char()
	local node, field = self:next_raw()
	if not node then
		return nil
	end
	local head, tail = self:split_first_char(node, "char")
	if tail then
		self:push_front(tail, field)
	end
	return head, field
end

---@param open_type string
---@param close_type string
---@param result_type string
---@param result_field string
---@return Nvimtex.LNode?, string?
function M:read_group(open_type, close_type, result_type, result_field)
	local open = self:next_raw()
	if not open or open:type() ~= open_type then
		if open then
			self:push_front(open)
		end
		return nil
	end

	local group = self:make_node(result_type)
	group:add_child(open)
	group:set_start(open)

	while true do
		local next_node = self:peek_raw()
		if next_node and next_node:type() == close_type then
			local close = self:next_raw()
			group:add_child(close)
			group:set_end(close)
			return group, result_field
		end

		local node, field = self:next_node()
		if not node then
			group:set_end()
			return group, result_field
		end

		group:add_child(node, field)
	end
end

---@return Nvimtex.LNode?, string?
function M:read_argument()
	local node, field = self:next_raw()
	if not node then
		return nil
	end

	if node:type() == "word" then
		local head, tail = self:split_first_char(node)
		if tail then
			self:push_front(tail, field)
		end
		return head, field
	end

	return node, field
end

---@param delimiter string
---@return Nvimtex.LNode, Nvimtex.LNode?
function M:read_until_char(delimiter)
	local content = self:make_node("verb_inner")
	local start_range
	local last_node

	while true do
		local node, field = self:next_raw()
		if not node then
			if start_range then
				local end_row, end_col, end_byte = last_node:end_()
				content:set_range(start_range[1], start_range[2], start_range[3], end_row, end_col, end_byte)
			else
				content:set_range(0, 0, 0, 0, 0, 0)
			end
			return content, nil
		end

		start_range = start_range or { node:start() }
		last_node = node
		local text = self:node_text(node) or ""
		local index = text:find(delimiter, 1, true)
		if index then
			local close = self:slice_node(node, index - 1, index, "char")
			content:set_range(start_range[1], start_range[2], start_range[3], close:start())
			if index < #text then
				self:push_front(self:slice_node(node, index, #text), field)
			end
			return content, close
		end
	end
end

return M
