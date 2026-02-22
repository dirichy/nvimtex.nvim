local util = require("nvimtex.conditions.util")
local M = {}
function M.in_math(a, b, c, d)
	local cursor = { a, b }
	local node = vim.treesitter.get_node({ pos = { a, b } })
	while node do
		if util.TEXT_NODES[node:type()] then
			return false
		elseif util.MATH_NODES[node:type()] then
			local x, y = node:start()
			if x == cursor[1] and y == cursor[2] then
				return false
			end
			return node
		end
		node = util.node_parent(node)
	end
	return false
end
return M
