-- local ls = require("luasnip")
-- local s = ls.snippet
-- local t = ls.text_node
-- local i = ls.insert_node
-- local f = ls.function_node
-- local fmta = require("luasnip.extras.fmt").fmta

-- [
-- personal imports
-- ]
-- local tex = require("nvimtex.conditions.luasnip")
local Operators = {
	["bigwedge"] = {
		conceal = "⋀",
		class = "hugeoperator",
		tex = "\\bigwedge",
		alias = "band",
		auto_subscript = "[%a%d]",
	},
	["bigvee"] = { conceal = "⋁", class = "hugeoperator", tex = "\\bigvee", alias = "bor", auto_subscript = "[%a%d]" },
	["bigcap"] = {
		conceal = "∩",
		class = "hugeoperator",
		tex = "\\bigcap",
		alias = "bcap",
		auto_subscript = "[%a%d]",
	},
	["bigcup"] = {
		conceal = "∪",
		class = "hugeoperator",
		tex = "\\bigcup",
		alias = "bcup",
		auto_subscript = "[%a%d]",
	},
	["bigcirc"] = {
		conceal = "○",
		class = "hugeoperator",
		tex = "\\bigcirc",
		alias = "bcir",
		auto_subscript = "[%a%d]",
	},
	["bigodot"] = {
		conceal = "⊙",
		class = "hugeoperator",
		tex = "\\bigodot",
		alias = "bodt",
		auto_subscript = "[%a%d]",
	},
	["bigoplus"] = {
		conceal = "⊕",
		class = "hugeoperator",
		tex = "\\bigoplus",
		alias = "bopl",
		auto_subscript = "[%a%d]",
	},
	["bigotimes"] = {
		conceal = "⊗",
		class = "hugeoperator",
		tex = "\\bigotimes",
		alias = "boti",
		auto_subscript = "[%a%d]",
	},
	["bigsqcup"] = {
		conceal = "⊔",
		class = "hugeoperator",
		tex = "\\bigsqcup",
		alias = "bscp",
		auto_subscript = "[%a%d]",
	},
	["bigtriangledown"] = {
		conceal = "∇",
		class = "hugeoperator",
		tex = "\\bigtriangledown",
		alias = "",
		auto_subscript = "[%a%d]",
	},
	["bigtriangleup"] = {
		conceal = "∆",
		class = "hugeoperator",
		tex = "\\bigtriangleup",
		alias = "",
		auto_subscript = "[%a%d]",
	},
	["idotsint"] = {
		conceal = "∫⋯∫",
		class = "hugeoperator",
		tex = "\\idotsint",
		alias = "",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["iiiint"] = {
		conceal = "∬∬",
		class = "hugeoperator",
		tex = "\\iiiint",
		alias = "iiii",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["iiint"] = {
		conceal = "∭",
		class = "hugeoperator",
		tex = "\\iiint",
		alias = "iiit",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["iint"] = {
		conceal = "∬",
		class = "hugeoperator",
		tex = "\\iint",
		alias = "iint",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["int"] = {
		conceal = "∫",
		class = "hugeoperator",
		tex = "\\int",
		alias = "int",
		auto_subscript = "[%a%d]",
		auto_superscript = true,
	},
	["oiiint"] = {
		conceal = "∰",
		class = "hugeoperator",
		tex = "\\oiiint",
		alias = "",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["oiint"] = {
		conceal = "∯",
		class = "hugeoperator",
		tex = "\\oiint",
		alias = "",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["oint"] = {
		conceal = "∮",
		class = "hugeoperator",
		tex = "\\oint",
		alias = "oint",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["prod"] = { conceal = "∏", class = "hugeoperator", tex = "\\prod", alias = "prod", auto_subscript = "[%a%d]" },
	["sum"] = { conceal = "∑", class = "hugeoperator", tex = "\\sum", alias = "sum", auto_subscript = "[%a%d]" },
	["lim"] = {
		conceal = "lim",
		class = "operatorname",
		tex = "\\lim",
		alias = "lim",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["liminf"] = {
		conceal = "liminf",
		class = "operatorname",
		tex = "\\liminf",
		alias = "lmi",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["limsup"] = {
		conceal = "limsup",
		class = "operatorname",
		tex = "\\limsup",
		alias = "lms",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["log"] = {
		conceal = "log",
		class = "operatorname",
		tex = "\\log",
		alias = "log",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["max"] = {
		conceal = "max",
		class = "operatorname",
		tex = "\\max",
		alias = "max",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["min"] = {
		conceal = "min",
		class = "operatorname",
		tex = "\\min",
		alias = "min",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["sup"] = {
		conceal = "sup",
		class = "operatorname",
		tex = "\\sup",
		alias = "sup",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
	["inf"] = {
		conceal = "inf",
		class = "operatorname",
		tex = "\\inf",
		alias = "inf",
		auto_subscript = "[%a%d]",
		auto_superscript = false,
	},
}
local M = {}
M.items = Operators

return M
