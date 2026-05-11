local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmta = require("luasnip.extras.fmt").fmta
local align_relation = {
	neq = "\\neq",
	eq = "=",
	leq = "\\leq",
	geq = "\\geq",
	["<"] = "<",
	[">"] = ">",
	["="] = "=",
}

local line_begin = require("luasnip.extras.expand_conditions").line_begin
local tex = require("nvimtex.conditions.luasnip")

local get_visual = function(args, parent)
	if #parent.snippet.env.SELECT_RAW > 0 then
		return sn(nil, t(parent.snippet.env.SELECT_RAW))
	else -- If SELECT_RAW is empty, return a blank insert node
		return sn(nil, i(1))
	end
end

local M = {
	s(
		{ trig = "(%d)sqrt", regTrig = true, snippetType = "autosnippet" },
		fmta("\\sqrt[<>]{<>}", {
			f(function(_, snip)
				return snip.captures[1]
			end),
			i(1),
		}),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "(\\%a+)res", regTrig = true, priority = 3000, snippetType = "autosnippet" },
		fmta("\\res{<>}{<>}", {
			f(function(_, snip)
				return snip.captures[1]
			end),
			i(1),
		}),
		{ condition = tex.in_math }
	),
	-- s(
	--   { trig = "bar", snippetType = "autosnippet" },
	--   fmta("\\overline{<>} ", {
	--     i(1),
	--   }),
	--   { condition = tex.in_math }
	-- ),
	s(
		{ trig = "(\\%a+)inv", regTrig = true, snippetType = "autosnippet" },
		fmta("<>^{-1}", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		}),
		{ condition = tex.in_math }
	),
	s({ trig = "\\?inv", regTrig = true, wordTrig = false, snippetType = "autosnippet" }, {
		t("^{-1}"),
	}, { condition = tex.in_math }),
	s(
		{ trig = "(\\%a+)bar", regTrig = true, snippetType = "autosnippet" },
		fmta("\\overline{<>} ", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		}),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "(\\%a+)hat", regTrig = true, snippetType = "autosnippet" },
		fmta("\\hat{<>}", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		}),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "(\\%a+)~", regTrig = true, snippetType = "autosnippet" },
		fmta("\\tilde{<>}", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		}),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "(%a)~", regTrig = true, snippetType = "autosnippet" },
		fmta("\\tilde{<>}", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		}),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "tag", regTrig = true, snippetType = "autosnippet" },
		fmta("\\triangle", {}),
		{ condition = tex.in_math }
	),
	s(
		{ trig = "sag", regTrig = true, snippetType = "autosnippet" },
		fmta([[S_{\triangle <>}<>]], {
			i(1),
			i(0),
		}),
		{ condition = tex.in_math }
	),
	s({ trig = "ang", regTrig = true, snippetType = "autosnippet" }, fmta("\\angle", {}), { condition = tex.in_math }),
	s(
		{ trig = "arc", regTrig = true, snippetType = "autosnippet" },
		fmta("\\wideparen{<>}<>", { i(1), i(0) }),
		{ condition = tex.in_math }
	),
}
for key, value in pairs(align_relation) do
	table.insert(
		M,
		s(
			{ trig = key .. " ", regTrig = false, snippetType = "autosnippet" },
			{ t("&" .. value .. " ") },
			{ condition = line_begin * tex.in_align }
		)
	)
end
return M
