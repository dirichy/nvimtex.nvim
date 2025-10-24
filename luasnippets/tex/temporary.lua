local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta
local line_begin = require("luasnip.extras.expand_conditions").line_begin

local tex = require("nvimtex.conditions.luasnip")

return {
	s(
		{ trig = "eng", snippetType = "autosnippet" },
		fmta("\\item \\eng{<>} <>", {
			i(1),
			i(2),
		}),
		{ condition = line_begin * tex.in_text }
	),
	s(
		{ trig = "  eng", snippetType = "autosnippet" },
		fmta("\\item \\eng{<>} <>", {
			i(1),
			i(2),
		}),
		{ condition = line_begin * tex.in_text }
	),
}
