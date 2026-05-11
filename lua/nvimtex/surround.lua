local conditions = require("nvimtex.conditions")
local parser = require("nvimtex.parser")
local util = require("nvimtex.latex.util")
local lnode = require("nvimtex.parser.lnode")
local M = {}
---@enum Nvimtex.math.type
M.mtype = {
	unknown = -1,
	inline = 0,
	display = 1,
	equation = 2,
	aligned = 3,
	align = 4,
}
local mtype_count = 5

---@param buf integer
---@returns string
local function buf_range_get_text(buf, start_row, start_col, end_row, end_col)
	if end_col == 0 then
		if start_row == end_row then
			start_col = -1
			start_row = start_row - 1
		end
		end_col = -1
		end_row = end_row - 1
	end
	local lines = vim.api.nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, {})
	return table.concat(lines, "\n")
end
--- Get name of an environment node
---@param enode Nvimtex.LNode
---@return string
local function get_env_name(buf, enode)
	return vim.treesitter.get_node_text(enode:child(0):child(1):child(1), buf)
end
--- Get name of an command node
---@param buf number
---@param cnode Nvimtex.LNode
local function get_cmd_name(buf, cnode)
	local command_node = cnode:field("command")[1]
	local command_name = vim.treesitter.get_node_text(command_node, buf):sub(2, -1)
	return command_name
end
--- Get math type of a math node
---@param mnode Nvimtex.LNode
---@return Nvimtex.math.type
function M.get_math_type(buf, mnode)
	local nodetype = mnode:type()
	if nodetype == "inline_formula" then
		return M.mtype.inline
	elseif nodetype == "displayed_equation" then
		return M.mtype.display
	elseif nodetype == "math_environment" then
		local ename = get_env_name(buf, mnode)
		if ename == "align" or ename == "align*" then
			return M.mtype.align
		end
		if ename == "equation" or ename == "equation*" then
			local first_child = mnode:child(1)
			if first_child and first_child:type() == "math_environment" then
				local child_name = get_env_name(buf, first_child)
				if child_name == "aligned" then
					return M.mtype.aligned
				end
			end
			return M.mtype.equation
		end
	end
	vim.notify("Unknown math type", vim.log.levels.WARN)
	return M.mtype.unknown
end
local function is_new_line(buf, node)
	return node:type() == "generic_command" and vim.treesitter.get_node_text(node, buf) == "\\\\"
end
local function is_align_tab(buf, node)
	return (node:type() == "delimiter") and vim.treesitter.get_node_text(node, buf) == "&"
end
local function is_relation_operator(buf, node)
	local t = node:type()
	if t == "generic_command" then
		t = get_cmd_name(buf, node)
	end
	return util.relation_operator[t]
end
--- Format math with given parameter
---@param mnode Nvimtex.LNode
function M.format_math(buf, mnode, opts)
	---@type string,string,boolean,boolean
	local prefix, suffix, newline, split = unpack(opts)
	local line = { prefix }
	if newline then
		line[2] = "\n"
	end
	local met_first_relation = false
	mnode = lnode:new(mnode)
	if M.get_math_type(buf, mnode) == M.mtype.aligned then
		mnode = lnode:new(mnode:child(1))
		table.remove(mnode._childrens, 1)
		table.remove(mnode._childrens)
	else
		table.remove(mnode._childrens, 1)
		table.remove(mnode._childrens)
	end
	local iter = parser.iter_children(mnode, buf)
	--- 0 for normal, 1 for after newline, 2 for after `&`.
	local cache_state = 0
	local ra, rb, rc, rd
	local node = iter()
	while node do
		if is_new_line(buf, node) then
			if cache_state ~= 0 then
				vim.notify("Can't guess how to deal with align tab or newline", vim.log.levels.WARN)
				return
			end
			cache_state = 1
			if ra then
				table.insert(line, buf_range_get_text(buf, ra, rb, rc, rd))
				ra = nil
			end
			goto continue
		end
		if is_align_tab(buf, node) then
			if cache_state ~= 0 and cache_state ~= 1 then
				vim.notify("Can't guess how to deal with align tab or newline", vim.log.levels.WARN)
				return
			end
			cache_state = 2
			if ra then
				table.insert(line, buf_range_get_text(buf, ra, rb, rc, rd))
				ra = nil
			end
			goto continue
		end
		if is_relation_operator(buf, node) then
			cache_state = 0
			if split then
				if ra then
					table.insert(line, buf_range_get_text(buf, ra, rb, rc, rd))
					ra = nil
				end
				if met_first_relation then
					table.insert(line, " \\\\\n")
				else
					met_first_relation = true
				end
				table.insert(line, "&" .. vim.treesitter.get_node_text(node, buf) .. " ")
				goto continue
			else
				if ra then
					_, _, rc, rd = node:range()
				else
					ra, rb, rc, rd = node:range()
				end
			end
		end
		if cache_state ~= 0 then
			vim.notify("Can't guess how to deal with align tab or newline", vim.log.levels.WARN)
			return
		end
		if ra then
			_, _, rc, rd = node:range()
		else
			ra, rb, rc, rd = node:range()
		end
		::continue::
		node = iter()
	end
	if ra then
		table.insert(line, buf_range_get_text(buf, ra, rb, rc, rd))
		ra = nil
	end
	if newline then
		table.insert(line, "\n" .. suffix)
	else
		table.insert(line, suffix)
	end
	return vim.split(table.concat(line, ""), "\n")
end
local format_arg = {
	[M.mtype.inline] = { "\\(", "\\)", false, false },
	[M.mtype.display] = { "\\[", "\\]", true, false },
	[M.mtype.equation] = { "\\begin{equation}", "\\end{equation}", true, false },
	[M.mtype.aligned] = { "\\begin{equation}\\begin{aligned}", "\\end{aligned}\\end{equation}", true, true },
	[M.mtype.align] = { "\\begin{align}", "\\end{align}", true, true },
}
function M.change_math(mtype, mnode)
	local buf = vim.api.nvim_win_get_buf(0)
	local a, b = unpack(vim.api.nvim_win_get_cursor(0))
	a = a - 1
	-- mnode = mnode or conditions.in_math(a, b, a, b)
	-- if not mnode then
	-- 	vim.notify("Can't find math node on cursor!", vim.log.levels.WARN)
	-- 	return
	-- end
	local s, t, u, v = mnode:range()
	-- local mtype = M.get_math_type(buf, mnode)
	-- mtype = (mtype + 1) % 5
	local lines = M.format_math(buf, mnode, format_arg[mtype])
	if lines then
		vim.api.nvim_buf_set_text(buf, s, t, u, v, lines)
	end
end
function M.upgrade_math()
	local buf = vim.api.nvim_win_get_buf(0)
	local a, b = unpack(vim.api.nvim_win_get_cursor(0))
	a = a - 1
	local mnode = conditions.in_math(a, b, a, b)
	if not mnode then
		vim.notify("Can't find math node on cursor!", vim.log.levels.WARN)
	end
	local mtype = M.get_math_type(buf, mnode)
	mtype = (mtype + 1) % mtype_count
	M.change_math(mtype, mnode)
end
function M.downgrade_math()
	local buf = vim.api.nvim_win_get_buf(0)
	local a, b = unpack(vim.api.nvim_win_get_cursor(0))
	a = a - 1
	local mnode = conditions.in_math(a, b, a, b)
	if not mnode then
		vim.notify("Can't find math node on cursor!", vim.log.levels.WARN)
	end
	local mtype = M.get_math_type(buf, mnode)
	mtype = (mtype - 1) % mtype_count
	M.change_math(mtype, mnode)
end
return M
