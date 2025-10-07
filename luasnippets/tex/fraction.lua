local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local f = ls.function_node
local fmta = require("luasnip.extras.fmt").fmta
local tex =require("nvimtex.conditions.luasnip")
M = {
  s(
    { trig = "(%d+)/", regTrig = true, snippetType = "autosnippet", priority = 100 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(%a+)/", regTrig = true, snippetType = "autosnippet", priority = 100 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(%b())/", regTrig = true, wordTrig = false, snippetType = "autosnippet" },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]:gsub("^%(%s*(.-)%s*%)$", "%1")
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(\\%a+)/", regTrig = true, snippetType = "autosnippet", priority = 3000 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(\\%a+%b[])/", regTrig = true, snippetType = "autosnippet", priority = 3000 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(\\%a+%b{})/", regTrig = true, snippetType = "autosnippet", priority = 3000 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(\\%a+%b{}%b{})/", regTrig = true, snippetType = "autosnippet", priority = 3000 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "(\\%a+%b[]%b{}%b{})/", regTrig = true, snippetType = "autosnippet", priority = 3000 },
    fmta("\\frac{<>}{<>}", {
      f(function(_, snip)
        return snip.captures[1]
      end),
      i(1),
    }),
    { condition = tex.in_math }
  ),
  s(
    { trig = "//", regTrig = true, snippetType = "autosnippet", priority = 3000 },
    fmta("\\frac{<>}{<>}", {
      i(1),
      i(2),
    }),
    { condition = tex.in_math }
  ),
}
return M
