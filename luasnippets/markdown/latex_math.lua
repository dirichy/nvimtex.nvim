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

local md = require("nvimtex.conditions.markdown")
return {
	s(
		{ trig = "[;j]j", regTrig = true, snippetType = "autosnippet" },
		fmta(
			[[
      $<> $<>
      ]],
			{
				i(1),
				i(0),
			}
		),
		{ condition = md.in_text }
	),
	s(
		{ trig = "[;t]t", regTrig = true, snippetType = "autosnippet" },
		fmta(
			[[
      $$ 
        <>
      $$ 
      ]],
			{
				i(1),
			}
		),
		{ condition = md.in_text }
	),
}
