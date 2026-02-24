local util = require("nvimtex.conditions.util")
local parser = require("nvimtex.parser")
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
function M.find_node(a, b, condition, smallest)
	local buf = vim.api.nvim_win_get_buf(0)
	local root = vim.treesitter.get_parser(buf, "latex")
	local nodes = parser.descendants_node_covering_range(root:trees()[1]:root(), buf, a, b)
	if smallest then
		local res = false
		for _, node in ipairs(nodes) do
			if condition(node) then
				res = node
			end
		end
		return res
	else
		for _, node in ipairs(nodes) do
			if condition(node) then
				return node
			end
		end
		return false
	end
end
return M
