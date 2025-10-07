local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node

local tex =require("nvimtex.conditions.luasnip")
return {
  s({ trig = "...", wordTrig = false, snippetType = "autosnippet" }, {
    t("\\cdots"),
  }, { condition = tex.in_math }),
  s({ trig = ";;;", wordTrig = false, snippetType = "autosnippet" }, {
    t("\\vdots"),
  }, { condition = tex.in_math }),
  s({ trig = "==", wordTrig = false, snippetType = "autosnippet" }, {
    t("&="),
  }, { condition = tex.in_math }),
  s({ trig = "~", wordTrig = false, snippetType = "autosnippet" }, {
    t("\\sim"),
  }, { condition = tex.in_math }),
  s({ trig = "--", wordTrig = false, snippetType = "autosnippet" }, {
    t("\\setminus"),
  }, { condition = tex.in_math }),
  s({ trig = "=>", wordTrig = false, snippetType = "autosnippet" }, {
    t("\\implies"),
  }, { condition = tex.in_math }),
  s({ trig = "<=", snippetType = "autosnippet" }, {
    t("\\impliedby"),
  }, { condition = tex.in_math }),
  s({ trig = "=>", wordTrig = false, snippetType = "autosnippet" }, {
    t("``\\(\\implies\\)'':"),
  }, { condition = tex.in_text }),
  s({ trig = "<=", snippetType = "autosnippet" }, {
    t("``\\(\\impliedby\\)'':"),
  }, { condition = tex.in_text }),
  s({ trig = "##", wordTrig = false, snippetType = "autosnippet" }, {
    t("\\# "),
  }, { condition = tex.in_math }),
  s({ trig = "0set", snippetType = "autosnippet", priority = 2000 }, {
    t("\\varnothing"),
  }, { condition = tex.in_math }),
}
