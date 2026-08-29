local conditions = require("nvimtex.conditions")
local parser = require("nvimtex.parser")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local util = require("nvimtex.latex.util")
local LNode = require("nvimtex.parser.lnode")
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
			return ""
		end
		end_col = -1
		end_row = end_row - 1
	end
	local lines = vim.api.nvim_buf_get_text(buf, start_row, start_col, end_row, end_col, {})
	return table.concat(lines, "\n")
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
		local ename = latex_nodes.environment_name(buf, mnode)
		if ename == "align" or ename == "align*" then
			return M.mtype.align
		end
		if ename == "equation" or ename == "equation*" then
			local body = latex_nodes.single_body_math_environment(mnode)
			if body and latex_nodes.environment_name(buf, body) == "aligned" then
				return M.mtype.aligned
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
		return util.relation_operator.generic_command(latex_nodes.command_name(buf, node))
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
	mnode = LNode:new(mnode)
	if M.get_math_type(buf, mnode) == M.mtype.aligned then
		mnode = LNode:new(latex_nodes.single_body_math_environment(mnode))
	end
	mnode = latex_nodes.without_math_boundary(mnode)
	--- 0 for normal, 1 for after newline, 2 for after `&`.
	local cache_state = 0
	local ra, rb, rc, rd
	for node in parser.iter_children(mnode, buf) do
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
	if not mnode then
		local a, b = unpack(vim.api.nvim_win_get_cursor(0))
		a = a - 1
		mnode = conditions.in_math(a, b, a, b)
	end
	if not mnode then
		vim.notify("Can't find math node on cursor!", vim.log.levels.WARN)
		return
	end
	local opts = format_arg[mtype]
	if not opts then
		vim.notify("Unknown math target type", vim.log.levels.WARN)
		return
	end
	local s, t, u, v = mnode:range()
	local lines = M.format_math(buf, mnode, opts)
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
		return
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
		return
	end
	local mtype = M.get_math_type(buf, mnode)
	mtype = (mtype - 1) % mtype_count
	M.change_math(mtype, mnode)
end
return M
