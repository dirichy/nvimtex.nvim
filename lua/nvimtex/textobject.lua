local parser = require("nvimtex.parser")
local util = require("nvimtex.conditions.util")
local LNode = require("nvimtex.parser.lnode")
local M = {}
---@param lnode Nvimtex.LNode
---@return table?
local function node2range(lnode)
	if not lnode then
		return
	end
	local a, b, c, d = lnode:range()
	return { from = { line = a + 1, col = b + 1 }, to = { line = c + 1, col = d } }
end

--- find a node satisfy a condition
---@param types string|string[]|fun(lnode:Nvimtex.LNode):Nvimtex.LNode?
---@return Nvimtex.LNode?
local function find_node(types)
	local f
	if type(types) == "string" then
		f = function(lnode)
			return lnode:type() == types and lnode
		end
	elseif type(types) == "table" then
		for _, value in ipairs(types) do
			types[value] = true
		end
		f = function(lnode)
			return types[lnode:type()] and lnode
		end
	else
		f = types
	end
	local lnodes = parser.descendants_node_covering_range()
	if not lnodes then
		return
	end
	local lnode
	for _, node in ipairs(lnodes) do
		lnode = f(node) or lnode
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
M.textobject = {}
local T = M.textobject

T.c = function(a_or_i, obj_type, opts)
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

T.e = function(a_or_i, _, _)
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
T.m = function(a_or_i, _, _)
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

T.a = function(a_or_i, _, _)
	local all_arg_fields = { "arg", "optional_arg", "name" }
	local lnode = find_node(function(node)
		local lnode = util.CMD_NODES[node:type()] and not on_cursor(node:child(0)) and node
		if not lnode then
			return
		end
		for _, field in ipairs(all_arg_fields) do
			for _, arg_node in ipairs(lnode:field(field)) do
				if on_cursor(arg_node) then
					return arg_node
				end
			end
		end
	end)
	if not lnode then
		return
	end
	if a_or_i == "a" then
		return node2range(lnode)
	else
		lnode = LNode.remove_bracket(lnode)
		return node2range(lnode)
	end
end

-- T.t = function(a, b, c)
-- 	vim.print(a, b, c)
-- end
function M.setup_buf(buf)
	if not buf then
		if vim.bo.filetype == "latex" or vim.bo.filetype == "tex" then
			buf = vim.api.nvim_win_get_buf(0)
		else
			return
		end
	end
	local cfg = vim.deepcopy(require("mini.ai").config)
	cfg.custom_textobjects = vim.tbl_extend("force", cfg.custom_textobjects or {}, M.textobject)
	vim.b[buf].miniai_config = cfg
end

vim.api.nvim_create_autocmd("FileType", {
	pattern = "*.tex",
	callback = function(evt)
		M.setup_buf(evt.buf)
	end,
})

return M
