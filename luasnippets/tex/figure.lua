local ls = require("luasnip")
local s = ls.snippet
local sn = ls.snippet_node
local isn = ls.indent_snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local events = require("luasnip.util.events")
local ai = require("luasnip.nodes.absolute_indexer")
local extras = require("luasnip.extras")
local l = extras.lambda
local rep = extras.rep
local p = extras.partial
local m = extras.match
local n = extras.nonempty
local dl = extras.dynamic_lambda
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local conds = require("luasnip.extras.expand_conditions")
local postfix = require("luasnip.extras.postfix").postfix
local types = require("luasnip.util.types")
local parse = require("luasnip.util.parser").parse_snippet
local ms = ls.multi_snippet
local autosnippet = ls.extend_decorator.apply(s, { snippetType = "autosnippet" })

-- [
-- personal imports
-- ]
local tex = require("nvimtex.conditions.luasnip")
-- local auto_backslash_snippet = require("util.scaffolding").auto_backslash_snippet
-- local symbol_snippet = require("util.scaffolding").symbol_snippet
-- local single_command_snippet = require("util.scaffolding").single_command_snippet
-- local postfix_snippet = require("util.scaffolding").postfix_snippet
local M = {
	s(
		{ trig = "grf", snippetType = "autosnippet" },
		fmta("\\includegraphics{<>}%![](<>)", {
			i(1),
			rep(1),
		}),
		{ condition = tex.in_fig }
	),
	s(
		{ trig = "cpt", snippetType = "autosnippet" },
		fmta("\\caption{<>}\\label{fig:<>}<>", {
			i(1),
			i(2),
			i(0),
		}),
		{ condition = tex.in_env({ "figure", "subfigure" }, false) }
	),
	s(
		{ trig = "sbf", snippetType = "autosnippet" },
		fmta(
			[[
      \begin{subfigure}[<>]{<>\textwidth}
      \centering
      <>
      \end{subfigure}\qquad
      <>
      ]],
			{
				i(1),
				i(2),
				i(3),
				i(0),
			}
		),
		{ condition = tex.in_fig }
	),
}
return M
