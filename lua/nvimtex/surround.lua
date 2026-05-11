local conditions = require("nvimtex.conditions")
local M = {}
---@param buf integer
---@param range Range
---@returns string
local function buf_range_get_text(buf, range)
	local start_row, start_col, end_row, end_col = M._range.unpack4(range)
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

---@enum Nvimtex.math.type
M.mtype = {
	unknown = 0,
	inline = 1,
	display = 2,
	equation = 3,
	aligned = 4,
	align = 5,
}
--- Get name of an environment node
---@param enode Nvimtex.LNode
---@return string
local function get_env_name(buf, enode)
	return vim.treesitter.get_node_text(enode:child(0):child(1):child(1), buf)
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
function M.upgrade_math()
	local buf = vim.api.nvim_win_get_buf(0)
	local a, b = unpack(vim.api.nvim_win_get_cursor(0))
	a = a - 1
	local mnode = conditions.in_math(a, b, a, b)
	if not mnode then
		vim.notify("Can't find math node on cursor!", vim.log.levels.WARN)
		return
	end
	local type = mnode:type()
	local s, t, c, d = mnode:range()
	if type == "inline_formula" then
		local lines = vim.api.nvim_buf_get_text(buf, s, t + 2, c, d - 2, {})
		if lines[1] == "" then
			table.insert(lines, 2, "\\[")
		else
			table.insert(lines, 1, "")
			table.insert(lines, 2, "\\[")
		end
		if lines[#lines] == "" then
			table.insert(lines, #lines, "\\]")
		else
			table.insert(lines, "\\]")
			table.insert(lines, "")
		end
		vim.api.nvim_buf_set_text(buf, s, t, c, d, lines)
	elseif type == "displayed_equation" then
		local lines = vim.api.nvim_buf_get_text(buf, s, t + 2, c, d - 2, {})
		if lines[1] == "" then
			table.insert(lines, 2, "\\begin{equation}")
		else
			table.insert(lines, 1, "")
			table.insert(lines, 2, "\\begin{equation}")
		end
		if lines[#lines] == "" then
			table.insert(lines, #lines, "\\end{equation}")
		else
			table.insert(lines, "\\end{equation}")
			table.insert(lines, "")
		end
		vim.api.nvim_buf_set_text(buf, s, t, c, d, lines)
	elseif type == "math_environment" then
	end
end
return M
