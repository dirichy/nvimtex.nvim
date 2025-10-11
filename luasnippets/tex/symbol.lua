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
local makesnip = function(_, snip, _, con, out)
	local key = snip.captures[1]
	out = out or con[key]
	if not out then
		return sn(nil, { t(key) })
	end
	local _, count = string.gsub(out, "<>", "<>")
	if count == 0 then
		return sn(nil, { t(out) })
	else
		local nodes = {}
		for index = 1, count do
			table.insert(nodes, i(index))
		end
		return sn(nil, fmta(out, nodes))
	end
end

local makesnip2 = function(_, snip, _, con, out)
	local key = snip.captures[1]
	out = out or con[key]
	out = out .. snip.captures[2]
	if not out then
		return sn(nil, { t(key) })
	end
	local _, count = string.gsub(out, "<>", "<>")
	if count == 0 then
		return sn(nil, { t(out) })
	else
		local nodes = {}
		for index = 1, count do
			table.insert(nodes, i(index))
		end
		return sn(nil, fmta(out, nodes))
	end
end

local cmds = require("nvimtex.snip.math").luasnip
local autocmds = require("nvimtex.snip.math").snip
local function makecondition(tab)
	return function(_, _, captures)
		return tex.in_math() and tab[captures[1]]
	end
end
local M = {
	s({
		trig = "%f[%a\\](%a%a%a?%a?%a?)([^%a])",
		wordTrig = false,
		regTrig = true,
		priority = 500,
		snippetType = "autosnippet",
	}, {
		d(1, makesnip2, {}, { user_args = { cmds } }),
	}, { condition = makecondition(cmds) }),
	s({ trig = "%f[%a\\](%a%a%a?%a?%a?)", wordTrig = false, regTrig = true, priority = 500 }, {
		d(1, makesnip, {}, { user_args = { cmds } }),
	}, { condition = makecondition(cmds) }),
	s({
		trig = "%f[%a\\](%a%a%a?%a?%a?)",
		wordTrig = false,
		regTrig = true,
		priority = 500,
		snippetType = "autosnippet",
	}, {
		d(1, makesnip, {}, { user_args = { autocmds } }),
	}, {
		condition = function(_, _, captures)
			return tex.in_math() and autocmds[captures[1]] and string.match(cmds[captures[1]], "<>")
		end,
	}),
}
return M
