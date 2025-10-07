local ls = require("luasnip")
local get_language = function()
	local lang = require("nvimtex.util").get_magic_comment("language")
	if lang then
		return lang
	end
	return "unknown"
end

local s = ls.snippet
local t = ls.text_node
local f = ls.function_node
local i = ls.insert_node
local fmta = require("luasnip.extras.fmt").fmta
local tex = require("nvimtex.conditions.luasnip")
local rep = require("luasnip.extras").rep
-- local pinyin = require("nvimtex.flypy")
local knowntypes = {
	pro = { en = "Problem", zh = "问题" },
	pp = { en = "Proposition", zh = "命题" },
	fig = { en = "Figure", zh = "图" },
	lem = { en = "Lemma", zh = "引理" },
	equ = { en = "Equation", zh = "公式" },
	unknown = { en = "", zh = "" },
	the = { en = "Theorem", zh = "定理" },
	cor = { en = "Corollary", zh = "推论" },
	def = { en = "Definition", zh = "定义" },
	exa = { en = "Example", zh = "例" },
	exe = { en = "Exercise", zh = "练习" },
}

return {
	s({ trig = "if" }, {
		t("\\text{\\ if\\ }"),
	}, { condition = tex.in_math }),
	s({ trig = "otherwise", snippetType = "autosnippet" }, {
		t("\\text{\\ otherwise\\ }"),
	}, { condition = tex.in_math }),
	s({ trig = "then" }, {
		t("\\text{\\ then\\ }"),
	}, { condition = tex.in_math }),
	s({ trig = "since" }, {
		t("\\text{\\ since\\ }"),
	}, { condition = tex.in_math }),

	s({ trig = "label", snippetType = "autosnippet" }, {
		t("\\label{"),
		i(1),
		t("}"),
	}, { condition = tex.in_text, show_condition = tex.in_text }),
	s(
		{ trig = "ref", snippetType = "autosnippet" },
		fmta("<><><>}", {
			f(function(args, _)
				local label = args[1][1]
				local type = string.match(label, "^[^:]*")
				type = knowntypes[type] and knowntypes[type] or knowntypes["unknown"]
				type = type[get_language()] and type[get_language()] .. " " or ""
				return type
			end, { 1 }),
			f(function(args, _)
				local label = args[1][1]
				local type = string.match(label, "^[^:]*")
				type = type == "equ" and "\\eqref{" or "\\ref{"
				return type
			end, { 1 }),
			i(1),
		}),
		{ condition = tex.in_text }
	),
	s(
		{ trig = "\\%)(%a)", regTrig = true, wordTrig = false, snippetType = "autosnippet", priority = 2000 },
		fmta("\\) <>", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		})
	),
	s(
		{ trig = "\\](%a)", regTrig = true, wordTrig = false, snippetType = "autosnippet", priority = 2000 },
		fmta("\\] <>", {
			f(function(_, snip)
				return snip.captures[1]
			end),
		})
	),
	-- s(
	--   { trig = "idx", snippetType = "autosnippet" },
	--   fmta("\\index{<>@<>}<>", {
	--     f(function(args, _)
	--       return pinyin(args[1][1])
	--     end, { 1 }),
	--     i(1),
	--     rep(1),
	--   }),
	--   { condition = tex.in_text }
	-- ),
	-- s(
	--   { trig = "bfidx", snippetType = "autosnippet" },
	--   fmta("\\index{<>@<>|textbf}\\textbf{<>}", {
	--     f(function(args, _)
	--       return pinyin(args[1][1])
	--     end, { 1 }),
	--     i(1),
	--     rep(1),
	--   }),
	--   { condition = tex.in_text }
	-- ),
	-- s({ trig = "psp", snippetType = "autosnippet" }, {
	--   t("\\(p\\)-subgroup"),
	-- }, { condition = tex.in_text }),
	-- s({ trig = "pgp", snippetType = "autosnippet" }, {
	--   t("\\(p\\)-subgroup"),
	-- }, { condition = tex.in_text }),
	-- s({ trig = "spsp", snippetType = "autosnippet" }, {
	--   t("Sylow \\(p\\)-subgroup"),
	-- }, { condition = tex.in_text }),
}
