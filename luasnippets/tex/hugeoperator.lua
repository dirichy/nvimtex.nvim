local items = require("nvimtex.latex.hugeoperator").items
local tex = require("nvimtex.conditions.luasnip")
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmta = require("luasnip.extras.fmt").fmta
local operators = {}
for key, value in pairs(items) do
	operators[value.alias] = value
end

return {
	s({
		trig = "%f[%a\\](%a%a%a?%a?%a?)",
		wordTrig = false,
		regTrig = true,
		priority = 500,
		snippetType = "autosnippet",
	}, {
		f(function(_, snip)
			return operators[snip.captures[1]].tex
		end),
	}, {
		condition = function(_, _, captures)
			return tex.in_math() and operators[captures[1]]
		end,
	}),
	s({
		trig = "\\(%a+)(%S)",
		wordTrig = false,
		regTrig = true,
		priority = 1000,
		snippetType = "autosnippet",
	}, {
		f(function(_, snip)
			return "\\" .. snip.captures[1] .. "_{" .. snip.captures[2]
		end),
		i(1),
		t("}"),
		i(0),
	}, {
		condition = function(_, _, captures)
			return tex.in_math
				and items[captures[1]]
				and items[captures[1]].auto_subscript
				and string.match(captures[2], items[captures[1]].auto_subscript)
		end,
	}),
	s({
		trig = "\\(%a+)(_%b{})(%S)",
		wordTrig = false,
		regTrig = true,
		priority = 1000,
		snippetType = "autosnippet",
	}, {
		f(function(_, snip)
			return "\\" .. snip.captures[1] .. snip.captures[2] .. "^{" .. snip.captures[3]
		end),
		i(1),
		t("}"),
		i(0),
	}, {
		condition = function(_, _, captures)
			if not tex.in_math() or not items[captures[1]] or not items[captures[1]].auto_subscript then
				return false
			end
			local flag
			if items[captures[1]].auto_superscript == nil then
				local str = captures[2]
				str = str:gsub("^_{(.-)}$", "%1")
				str = str:gsub("{.*}", "")
				flag = string.find(str, "=")
			else
				flag = items[captures[1]].auto_superscript
			end
			return flag
			-- and string.match(captures[3], items[captures[1]].auto_subscript)
		end,
	}),
}
