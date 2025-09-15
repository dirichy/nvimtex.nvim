local parser = require("nvimtex.parser")
local util = require("nvimtex.conditions.util")
local LNode = require("nvimtex.parser.lnode")
local M = {}
---@param node LNode
---@return table?
local function node2range(lnode)
	if not lnode then
		return
	end
	local a, b, c, d = lnode:range()
	return { from = { line = a + 1, col = b + 1 }, to = { line = c + 1, col = d } }
end
local function find_node(types)
	if type(types) == "string" then
		types = { types }
	end
	local lnodes = parser.get_node()
	if not lnodes then
		return
	end
	local lnode
	for _, node in ipairs(lnodes) do
		if types[node:type()] or vim.tbl_contains(types, node:type()) then
			lnode = node
		end
	end
	return lnode
end

local function on_cursor(lnode)
	local a1, a2, b1, b2, c1, c2, d1, d2
	if lnode[1] then
		a1, b1, c1, d1 = unpack(lnode)
	else
		a1, b1, c1, d1 = lnode:range()
	end
	a2, b2 = unpack(vim.api.nvim_win_get_cursor(0))
	a2 = a2 - 1
	c2 = a2
	d2 = b2 + 1
	return (a1 < a2 or a1 == a2 and b1 <= b2) and (c2 < c1 or c2 == c1 and d2 <= d1)
end

M.c = function(a_or_i, obj_type, opts)
	local lnode = find_node(util.CMD_NODES)
	if not lnode then
		return
	end
	if a_or_i == "a" then
		return node2range(lnode)
	else
		return node2range(lnode:child(0))
	end
end

M.e = function(a_or_i, _, _)
	local lnode = find_node(util.ENV_NODES)
	if not lnode then
		return
	end
	lnode = LNode:new(lnode)
	if a_or_i == "a" then
		return node2range(lnode)
	else
		local a, b = lnode:child(0):end_()
		local c, d = lnode:child(-1):start()
		if a == c and b == d then
			return
		end
		if d == 0 then
			c = c - 1
			d = 9999999
		end
		return { from = { line = a + 1, col = b + 1 }, to = { line = c + 1, col = d } }
	end
end
M.m = function(a_or_i, _, _)
	local lnode = find_node(util.MATH_NODES)
	if not lnode then
		return
	end
	lnode = LNode:new(lnode)
	if a_or_i == "a" then
		return node2range(lnode)
	else
		local a, b = lnode:child(0):end_()
		local c, d = lnode:child(-1):start()
		if a == c and b == d then
			return
		end
		if d == 0 then
			c = c - 1
			d = 9999999
		end
		return { from = { line = a + 1, col = b + 1 }, to = { line = c + 1, col = d } }
	end
end

M.a = function(a_or_i, _, _)
	local all_arg_fields = { "arg", "optional_arg", "name" }
	local lnodes = parser.get_node()
	local lnode
	for _, node in ipairs(lnodes) do
		if util.CMD_NODES[node:type()] then
			if not on_cursor(node:child(0)) then
				lnode = node
			end
		end
	end
	if not lnode then
		return
	end
	local arg_node
	for _, field in ipairs(all_arg_fields) do
		for _, node in ipairs(lnode:field(field)) do
			if on_cursor(node) then
				arg_node = node
			end
		end
	end
	if a_or_i == "a" then
		return node2range(arg_node)
	else
		arg_node = LNode.remove_bracket(arg_node)
		return node2range(arg_node)
	end
end

M.t = function(a, b, c)
	vim.print(a, b, c)
end

return M
