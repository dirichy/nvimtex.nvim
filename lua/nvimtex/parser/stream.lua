local LNode = require("nvimtex.parser.lnode")

local M = {}
M.__index = M

---@class Nvimtex.Parser.Stream
---@field stack (fun():Nvimtex.LNode?,string?)[]
---@field pushed Nvimtex.LNode.withfield[]
---@field fold_scripts boolean
---@field opts Nvimtex.Parser.StreamOptions

---@class Nvimtex.Parser.StreamOptions
---@field start_row? integer skip children ending before this zero-based row
---@field end_row? integer stop after children starting beyond this row
---@field binary_threshold? integer use binary seeking at or above this child count
---@field lookbehind? integer include this many children before the found boundary

---@param root Nvimtex.LNode
---@param opts Nvimtex.Parser.StreamOptions
---@return fun(): Nvimtex.LNode?, string?
local function child_iterator(root, opts)
	-- Small child lists are cheaper to scan and retain field names from the
	-- native iterator. Large lists seek by their ordered source end positions.
	local iter = root:iter_children()
	local child_count = root:child_count()
	if not opts.start_row or child_count < (opts.binary_threshold or 16) then
		return iter
	end

	local left, right = 0, child_count
	-- Find the first child whose end is after the requested start row.
	while left < right do
		local middle = math.floor((left + right) / 2)
		local child = root:child(middle)
		local end_row, end_col = child:end_()
		if end_row < opts.start_row or (end_row == opts.start_row and end_col == 0) then
			left = middle + 1
		else
			right = middle
		end
	end

	local index = math.max(left - (opts.lookbehind or 2), 0)
	if index == 0 then
		-- Keep the native iterator when starting from zero so callers still
		-- receive grammar field names alongside nodes.
		return function()
			local child, field = iter()
			if child and opts.end_row and child:start() > opts.end_row then
				return nil
			end
			return child, field
		end
	end
	return function()
		-- Indexed iteration cannot expose grammar field names, so the second
		-- return value is intentionally nil on this fast path.
		if index >= child_count then
			return nil
		end
		local child = root:child(index)
		index = index + 1
		if opts.end_row and child:start() > opts.end_row then
			return nil
		end
		return child
	end
end

---@param root Nvimtex.LNode
---@param opts? Nvimtex.Parser.StreamOptions
---@return Nvimtex.Parser.Stream
function M:new(root, opts)
	opts = opts or {}
	return setmetatable({
		stack = { child_iterator(root, opts) },
		pushed = {},
		fold_scripts = root:type() ~= "script",
		opts = opts,
	}, M)
end

---@param node Nvimtex.LNode
---@param field string?
function M:push_front(node, field)
	table.insert(self.pushed, { node, field })
end

---@return Nvimtex.LNode?, string?
function M:next()
	local pushed = table.remove(self.pushed)
	if pushed then
		return pushed[1], pushed[2]
	end

	while #self.stack > 0 do
		local iter = self.stack[#self.stack]
		local node, field = iter()
		if node then
			if node:type() == "text" then
				table.insert(self.stack, child_iterator(node, self.opts))
			else
				return node, field
			end
		else
			table.remove(self.stack)
		end
	end
end

---@return Nvimtex.LNode?, string?
function M:peek()
	local node, field = self:next()
	if node then
		self:push_front(node, field)
	end
	return node, field
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode
local function clone_node(node)
	local result = LNode:new(node:type())
	result:set_range(node)
	for child, field in node:iter_children() do
		result:add_child(child, field)
	end
	return result
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode, Nvimtex.LNode?
function M.split_word(node)
	local a, b, x, c, d, y = node:range(true)
	local head = clone_node(node)
	head:set_range(a, b, x, a, b + 1, x + 1)
	if d - b <= 1 then
		return head, nil
	end
	local tail = clone_node(node)
	tail:set_range(a, b + 1, x + 1, c, d, y)
	return head, tail
end

return M
