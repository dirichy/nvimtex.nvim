local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local rep = require("luasnip.extras").rep
local line_begin = require("luasnip.extras.expand_conditions").line_begin
local fmta = require("luasnip.extras.fmt").fmta

-- [
-- personal imports
-- ]
local tex = require("nvimtex.conditions.luasnip")
local text_line_begin_leader = "%."
local envs = {
	al = {
		name = function()
			if tex.in_math() then
				return "aligned"
			else
				return "align"
			end
		end,
		condition = 2,
	},
	co = { name = "corollary", condition = 2, label = "cor" },
	cr = { name = "center", condition = 2 },
	ct = { name = "center", condition = 2 },
	de = { name = "definition", condition = 2, label = "def" },
	en = { name = "enumerate", condition = 2, prefix = "\\item " },
	ep = { name = "example", confition = 2, label = "exa" },
	eq = { name = "equation", condition = 2, label = "equ" },
	ex = { name = "exercise", condition = 2, label = "exe" },
	fg = { name = "figure", condition = 2, prefix = "\\centering", option = "!htbp" },
	fr = { name = "frame", condition = 2 },
	it = { name = "itemize", condition = 2, prefix = "\\item " },
	le = { name = "lemma", condition = 2, label = "lem" },
	pf = { name = "proof", condition = 2 },
	pr = { name = "problem", condition = 2, label = "pro" },
	so = { name = "solution", condition = 2 },
	th = { name = "theorem", condition = 2, label = "the" },
	tp = { name = "tikzpicture", condition = 2 },
	pp = { name = "proposition", condition = 2, label = "pp" },
}
local make_label = function(_, snip)
	local env = envs[snip.captures[1]]
	local label = env.label
	if label then
		return sn(nil, {
			f(function(args, _)
				if args[1][1] ~= "" then
					return "\\label{" .. label .. ":"
				else
					return " "
				end
			end, { 1 }),
			i(1),
			f(function(args, _)
				if args[1][1] ~= "" then
					return "}"
				else
					return ""
				end
			end, { 1 }),
		})
	else
		return sn(nil, { t("") })
	end
end
M = {
	s(
		{ trig = text_line_begin_leader .. "(%a%a)", regTrig = true, snippetType = "autosnippet", priority = 10000 },
		fmta(
			[[
\begin{<>}<><>
  <><>
\end{<>}
<>
      ]],
			{
				f(function(_, snip)
					local name = envs[snip.captures[1]].name
					if type(name) == "string" then
						return name
					else
						return name()
					end
				end),
				f(function(_, snip)
					return envs[snip.captures[1]].option and "[" .. envs[snip.captures[1]].option .. "]" or ""
				end),
				d(1, make_label),
				f(function(_, snip)
					return envs[snip.captures[1]].prefix or ""
				end),
				i(2),
				f(function(_, snip)
					local name = envs[snip.captures[1]].name
					if type(name) == "string" then
						return name
					else
						return name()
					end
				end),
				i(0),
			}
		),
		{ condition = line_begin * function(_, _, captures)
			return envs[captures[1]]
		end }
	),
	s({ trig = "。", snippetType = "autosnippet", priority = 2000 }, {
		t("."),
	}, { condition = line_begin }),
	s(
		{ trig = text_line_begin_leader .. "eg", regTrig = true, snippetType = "autosnippet", priority = 1000 },
		fmta(
			[[
\begin{<>}
  <>
\end{<>}
<>
      ]],
			{
				i(1),
				i(2),
				rep(1),
				i(0),
			}
		),
		{ condition = tex.in_text * line_begin }
	),
	s({ trig = "  item", snippetType = "autosnippet" }, {
		t("\\item"),
	}, { condition = tex.in_item * line_begin }),
	s({ trig = "item", snippetType = "autosnippet", priority = 100 }, {
		t("\\item"),
	}, { condition = tex.in_item * line_begin }),
	s(
		{ trig = "[;j]j", regTrig = true, snippetType = "autosnippet" },
		fmta(
			[[
      \(<> \)<>
      ]],
			{
				i(1),
				i(0),
			}
		),
		{ condition = tex.in_text }
	),
	s(
		{ trig = "[;t]t", regTrig = true, snippetType = "autosnippet" },
		fmta(
			[[
      \[
        <>
      \]
      ]],
			{
				i(1),
			}
		),
		{ condition = tex.in_text }
	),
}
return M
