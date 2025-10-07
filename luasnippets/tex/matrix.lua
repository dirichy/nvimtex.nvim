-- [
-- snip_env + autosnippets
-- ]
local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local r = ls.restore_node
local fmta = require("luasnip.extras.fmt").fmta
local autosnippet = ls.extend_decorator.apply(s, { snippetType = "autosnippet" })
local line_begin = require("luasnip.extras.expand_conditions").line_begin
local latex = require("nvimtex.conditions.luasnip")
latex.in_table = function()
	return false
end
local function get_column_in_tblr()
	local curcol = vim.api.nvim_win_get_cursor(0)[1]
	local line = ""
	while curcol > 1 do
		line = vim.api.nvim_buf_get_lines(0, curcol - 1, curcol, false)[1]
		if string.match(line, "^\\begin{tblr}") then
			return tonumber(string.match(line, "%%!column%s*=%s*(.*)$"))
		end
		curcol = curcol - 1
	end
end
local generate_oneline = function(col)
	if not col or col == 0 then
		return sn(nil, { r(1, "1", i(1)) })
	end
	local nodes = {}
	for j = 1, col - 1 do
		table.insert(nodes, r(j, tostring(j), i(1)))
		table.insert(nodes, t(" & "))
	end
	table.insert(nodes, r(col, tostring(col), i(1)))
	table.insert(nodes, t({ "\\\\" }))
	return sn(nil, nodes)
end
-- Generating functions for Matrix/Cases - thanks L3MON4D3!
---@param str string
local function count_column(str)
	if string.find(str, "colspec") then
		str = string.match(str, "colspec%s*=%s*(%b{})")
		str = string.match(str, "^{(.*)}$")
	else
		local test = string.gsub(str, "%b{}", "")
		if string.find(test, "=") then
			return nil
		end
	end
	str = string.gsub(str, [[|]], "")
	str = string.gsub(str, [=[%b[]]=], "")
	str = string.gsub(str, [=[%b{}]=], "")
	return string.len(str)
end
-- [
-- personal imports
-- ]
local tex = require("nvimtex.conditions.luasnip")

-- Generating functions for Matrix/Cases - thanks L3MON4D3!
local generate_matrix = function(args, snip)
	local rows = snip.captures[2] and tonumber(snip.captures[2]) or 2
	local cols = snip.captures[3] and tonumber(snip.captures[3]) or rows
	local nodes = {}
	local ins_indx = 1
	for j = 1, rows do
		table.insert(nodes, r(ins_indx, tostring(j) .. "x1", i(1)))
		ins_indx = ins_indx + 1
		for k = 2, cols do
			table.insert(nodes, t(" & "))
			table.insert(nodes, r(ins_indx, tostring(j) .. "x" .. tostring(k), i(1)))
			ins_indx = ins_indx + 1
		end
		table.insert(nodes, t({ "\\\\", "" }))
	end
	-- fix last node.
	nodes[#nodes] = t("\\\\")
	return sn(nil, nodes)
end

-- update for cases
local generate_cases = function(args, snip)
	local rows = tonumber(snip.captures[1]) or 2 -- default option 2 for cases
	local cols = 2 -- fix to 2 cols
	local nodes = {}
	local ins_indx = 1
	for j = 1, rows do
		table.insert(nodes, r(ins_indx, tostring(j) .. "x1", i(1)))
		ins_indx = ins_indx + 1
		for k = 2, cols do
			table.insert(nodes, t(" & "))
			table.insert(nodes, r(ins_indx, tostring(j) .. "x" .. tostring(k), i(1)))
			ins_indx = ins_indx + 1
		end
		table.insert(nodes, t({ "\\\\", "" }))
	end
	-- fix last node.
	table.remove(nodes, #nodes)
	return sn(nil, nodes)
end
local generate_equs = function(args, snip)
	local rows = tonumber(snip.captures[1]) or 2 -- default option 2 for equs
	local nodes = {}
	local ins_indx = 1
	for j = 1, rows do
		table.insert(nodes, r(ins_indx, tostring(j) .. "x1", i(1)))
		ins_indx = ins_indx + 1
		table.insert(nodes, t({ "\\\\", "" }))
	end
	-- fix last node.
	table.remove(nodes, #nodes)
	return sn(nil, nodes)
end

M = {
	s(
		{
			trig = "([bBpvV]?)mat(%d*)x?(%d*) ",
			name = "[bBpvV]matrix",
			dscr = "matrices",
			regTrig = true,
			hidden = true,
			snippetType = "autosnippet",
		},
		fmta(
			[[
    \begin{<>}
    <>
    \end{<>}]],
			{
				f(function(_, snip)
					return snip.captures[1] .. "matrix"
				end),
				d(1, generate_matrix),
				f(function(_, snip)
					return snip.captures[1] .. "matrix"
				end),
			}
		),
		{ condition = tex.in_math }
	),

	autosnippet(
		{
			trig = "(%d?)cases",
			name = "cases",
			dscr = "cases",
			regTrig = true,
			hidden = true,
			snippetType = "autosnippet",
		},
		fmta(
			[[
    \begin{cases}
    <>
    \end{cases}
    ]],
			{ d(1, generate_cases) }
		),
		{ condition = tex.in_math }
	),
	autosnippet(
		{ trig = "(%d?)equs", name = "equs", dscr = "equs", regTrig = true, hidden = true, snippetType = "autosnippet" },
		fmta(
			[[
    \begin{cases}
    <>
    \end{cases}
    ]],
			{ d(1, generate_equs) }
		),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "tblr", snippetType = "autosnippet" },
		fmta(
			[[
\begin{tblr}<><><>{<>} %!column = <>
<>
<>
\end{tblr}
    ]],
			{
				f(function(args, snip)
					return args[1][1] ~= "" and "[" or ""
				end, { 1 }),
				i(1),
				f(function(args, snip)
					return args[1][1] ~= "" and "]" or ""
				end, { 1 }),
				i(2),
				f(function(args, snip)
					local col = count_column(args[1][1])
					return tostring(col)
				end, { 2 }),
				d(3, function(args, snip)
					local col = count_column(args[1][1])
					return generate_oneline(col)
				end, { 2 }),
				i(4),
			}
		),
		{ condition = line_begin }
	),
	s(
		{ trig = "([^%s])", regTrig = true, snippetType = "autosnippet" },
		fmta(
			[[
<><>
<>
]],
			{
				f(function(_, snip)
					return snip.captures[1]
				end),
				d(1, function()
					local col = get_column_in_tblr()
					return generate_oneline(col)
				end),
				i(0),
			}
		),
		{
			condition = function()
				if not latex.in_table() then
					return false
				end
				local curcol = vim.api.nvim_win_get_cursor(0)[1]
				local line = vim.api.nvim_buf_get_lines(0, curcol - 1, curcol, false)[1]
				return string.match(line, "^%s*[^%s]$")
			end,
		}
	),
}

return M
