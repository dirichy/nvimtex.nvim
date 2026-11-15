local util = require("nvimtex.conditions.util")
local parser = require("nvimtex.parser")
local M = {}
--- find a math node cover a range
---@param a number start_line
---@param b number start_col
---@param c number end_line
---@param d number end_col
---@param bufnr? integer
---@return TSNode?
function M.in_math(a, b, c, d, bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ft = vim.bo[bufnr].filetype
	local language = (ft == "tex" or ft == "plaintex" or ft == "latex") and "latex" or nil
	local ok, tree = pcall(vim.treesitter.get_parser, bufnr, language)
	if not ok or not tree or not pcall(tree.parse, tree, { { a, c + 1 } }) then
		return nil
	end
	local res
	local cursor = { a, b }
	local node = tree:named_node_for_range({ a, b, c, d }, { ignore_injections = false })
	while node do
		if util.TEXT_NODES[node:type()] then
			return res
		elseif util.MATH_NODES[node:type()] then
			local x, y = node:start()
			if x == cursor[1] and y == cursor[2] then
				return res
			end
			res = node
		end
		node = util.node_parent(node)
	end
	return res
end
--- find a node satisfy condition cover a position
---@param a number line
---@param b number col
---@param condition fun(lnode:Nvimtex.LNode):boolean
---@param smallest boolean find smallest node or biggest node, default false
---@return Nvimtex.LNode|false
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
