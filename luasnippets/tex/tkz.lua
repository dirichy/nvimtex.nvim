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
local position = { b = "below", r = "right", l = "left", a = "above" }
-- [
-- personal imports
-- ]
local tex = require("nvimtex.conditions.luasnip")
-- local auto_backslash_snippet = require("util.scaffolding").auto_backslash_snippet
-- local symbol_snippet = require("util.scaffolding").symbol_snippet
-- local single_command_snippet = require("util.scaffolding").single_command_snippet
local function condition(...)
	return tex.in_env("tikzpicture", false)
end
local M = {
	s(
		{ trig = "dpt", snippetType = "autosnippet" },
		fmta("\\tkzDefPoint(<>,<>){<>}<>", {
			i(1),
			i(2),
			i(3),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dac", snippetType = "autosnippet" },
		fmta("\\tkzDarc<><><>{<>}{<>}{<>}<>", {
			f(function(args, _)
				if args[1][1] ~= "" then
					return "["
				else
					return ""
				end
			end, { 1 }),
			i(1),
			f(function(args, _)
				if args[1][1] ~= "" then
					return "]"
				else
					return ""
				end
			end, { 1 }),
			i(2),
			i(3),
			i(4),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "lac", snippetType = "autosnippet" },
		fmta("\\tkzLabelArc[right=2pt](<>,<>,<>){\\(<>\\)}<>", {
			i(1),
			i(2),
			i(3),
			i(4),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dsg", snippetType = "autosnippet" },
		fmta("\\tkzDrawSegment[dash pattern={on 2pt off 2pt}](<>,<>)<>", {
			i(1),
			i(2),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dsp", snippetType = "autosnippet" },
		fmta("\\tkzDefPointWith[linear, K=<>](<>,<>)\\tkzGetPoint{<>}<>", {
			i(1),
			i(2),
			i(3),
			i(4),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dps", snippetType = "autosnippet" },
		fmta("\\tkzDrawPoints(<>)<>", {
			i(1),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "lp(%a)", regTrig = true, snippetType = "autosnippet" },
		fmta("\\tkzLabelPoints[<>](<>)<>", {
			f(function(_, snip)
				return position[snip.captures[1]]
			end),
			i(1),
			i(0),
		}),
		{
			condition = function(_, _, captures)
				if position[captures[1]] == nil then
					return false
				else
					return true
				end
			end,
		}
	),
	s(
		{ trig = "ls(%a)", regTrig = true, snippetType = "autosnippet" },
		fmta("\\tkzLabelSegment[<>](<>,<>){\\(<>\\)}<>", {
			f(function(_, snip)
				return position[snip.captures[1]]
			end),
			i(1),
			i(2),
			i(3),
			i(0),
		}),
		{
			condition = function(_, _, captures)
				if position[captures[1]] == nil then
					return false
				else
					return true
				end
			end,
		}
	),
	s(
		{ trig = "icc", snippetType = "autosnippet" },
		fmta("\\tkzInterCC(<>,<>)(<>,<>)\\tkzGetPoints{<>}{<>}<>", {
			i(1),
			i(2),
			i(3),
			i(4),
			i(5),
			i(6),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dc3", snippetType = "autosnippet" },
		fmta("\\tkzDefCircle[circum](<>,<>,<>)\\tkzGetPoint{<>}<>", {
			i(1),
			i(2),
			i(3),
			i(4),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dcc", snippetType = "autosnippet" },
		fmta("\\tkzDrawCircle(<>,<>)<>", {
			i(1),
			i(2),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dao", snippetType = "autosnippet" },
		fmta("\\tkzDrawArc(<>,<>)(<>)<>", {
			i(1),
			i(2),
			i(3),
			i(0),
		}),
		{ condition = condition }
	),
	s(
		{ trig = "dep", regTrig = true, snippetType = "autosnippet" },
		fmta([[\tkzDrawEllipse(<>,<>,<>,<>)<>]], {
			i(1),
			i(2),
			i(3),
			i(4),
			i(0),
		}),
		{ condition = condition }
	),
}
return M
-- local postfix_snippet = require("util.scaffolding").postfix_snippet
