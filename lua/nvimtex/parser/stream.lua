local LNode = require("nvimtex.parser.lnode")

local M = {}
M.__index = M

---@class Nvimtex.Parser.Stream
---@field stack (fun():Nvimtex.LNode?,string?)[]
---@field pushed Nvimtex.LNode.withfield[]
---@field fold_scripts boolean

---@param root Nvimtex.LNode
---@return Nvimtex.Parser.Stream
function M:new(root)
	return setmetatable({
		stack = { root:iter_children() },
		pushed = {},
		fold_scripts = root:type() ~= "script",
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
				table.insert(self.stack, node:iter_children())
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
