local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta

local tex = require("nvimtex.conditions.luasnip")

return {
	-- s(
	-- 	{ trig = "test", snippetType = "autosnippet" },
	-- 	fmta("\\<>{<>}", {
	-- 		i(1),
	-- 		f(function()
	-- 			return vim.fn.input("input something")
	-- 		end),
	-- 	}),
	-- 	{ condition = tex.in_math }
	-- ),
}
