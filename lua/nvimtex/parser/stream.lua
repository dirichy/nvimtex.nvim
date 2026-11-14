local LNode = require("nvimtex.parser.lnode")

local M = {}
M.__index = M

---@class Nvimtex.Parser.Stream
---@field stack (fun():Nvimtex.LNode?)[]
---@field pushed Nvimtex.LNode[]
---@field fold_scripts boolean
---@field opts Nvimtex.Parser.StreamOptions

---@class Nvimtex.Parser.StreamOptions
---@field start_row? integer skip children ending before this zero-based row
---@field end_row? integer stop after children starting beyond this row
---@field binary_threshold? integer use binary seeking at or above this child count
---@field lookbehind? integer include this many children before the found boundary

---@param root Nvimtex.LNode
---@param opts Nvimtex.Parser.StreamOptions
---@return fun(): Nvimtex.LNode?
local function child_iterator(root, opts)
	local child_count = root:child_count()
	local index = 0
	if opts.start_row and child_count >= (opts.binary_threshold or 16) then
		local left, right = 0, child_count
		-- Seek by ordered source ends, retaining a little context for commands
		-- and scripts whose tokens may straddle the viewport boundary.
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
		index = math.max(left - (opts.lookbehind or 2), 0)
	end
	-- Indexed access avoids querying grammar field names, even for small lists.
	return function()
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
function M:push_front(node)
	self.pushed[#self.pushed + 1] = node
end

---@return Nvimtex.LNode?
function M:next()
	local pushed = table.remove(self.pushed)
	if pushed then
		return pushed
	end

	while #self.stack > 0 do
		local iter = self.stack[#self.stack]
		local node = iter()
		if node then
			if node:type() == "text" then
				table.insert(self.stack, child_iterator(node, self.opts))
			else
				return node
			end
		else
			table.remove(self.stack)
		end
	end
end

---@return Nvimtex.LNode?
function M:peek()
	local node = self:next()
	if node then
		self:push_front(node)
	end
	return node
end

---@param node Nvimtex.LNode
---@return Nvimtex.LNode
local function clone_node(node)
	local result = LNode:new(node:type())
	result:set_range(node)
	for index = 0, node:child_count() - 1 do
		local child = node:child(index)
		if child then
			result:add_child(child)
		end
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
