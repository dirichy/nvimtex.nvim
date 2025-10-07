local ls = require("luasnip")
local s = ls.snippet
local i = ls.insert_node
local f = ls.function_node
local fmta = require("luasnip.extras.fmt").fmta
local autosnippet = ls.extend_decorator.apply(s, { snippetType = "autosnippet" })

-- [
-- personal imports
-- ]
local tex =require("nvimtex.conditions.luasnip")
local brackets = {
  a = { "(", ")" },
  A = { "\\left(", "\\right)" },
  s = { "[", "]" },
  S = { "\\left[", "\\right]" },
  d = { "{", "}" },
  D = { "\\left.", "\\right." },
  f = { "\\{", "\\}" },
  F = { "\\left\\{", "\\right\\}" },
  g = { "\\langle ", "\\rangle " },
  G = { "\\left\\langle ", "\\right\\rangle " },
  b = { "|", "|" },
  B = { "\\left|", "\\right|" },
  q = { "``", "''" },
  w = { "`", "'" },
  u = { "\\lceil", "\\rceil" },
  U = { "\\left\\lceil", "\\right\\rceil" },
  n = { "\\lfloor", "\\rfloor" },
  N = { "\\left\\lfloor", "\\right\\rfloor" },
}

M = {
  autosnippet(
    {
      trig = ";([aAsSdfFgGbBuUnN])",
      name = "left right",
      dscr = "left right delimiters",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
    <><><><>
    ]],
      {
        f(function(_, snip)
          local cap = snip.captures[1]
          return brackets[cap][1]
        end),
        i(1),
        f(function(_, snip)
          local cap = snip.captures[1]
          return brackets[cap][2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = ";h([aAsSdDfFgGbBuUnN])",
      name = "left right",
      dscr = "left right delimiters",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>
    ]],
      {
        f(function(_, snip)
          local cap = snip.captures[1]
          return brackets[string.upper(cap)][1]
        end),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = ";l([aAsSdDfFgGbBuUnN])",
      name = "left right",
      dscr = "left right delimiters",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>
    ]],
      {
        f(function(_, snip)
          local cap = snip.captures[1]
          return brackets[string.upper(cap)][2]
        end),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = ";;([asdfbqw])",
      name = "left right",
      dscr = "left right delimiters",
      regTrig = true,
      wordTrig = false,
      hidden = true,
      priority = 10000,
    },
    fmta(
      [[
    <><><><>
    ]],
      {
        f(function(_, snip)
          local cap = snip.captures[1]
          return brackets[cap][1]
        end),
        i(1),
        f(function(_, snip)
          local cap = snip.captures[1]
          return brackets[cap][2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_text }
  ),
  -- accent.grave,
  -- accent.circonflexe,
  -- accent.trema,
  -- accent.aigu,
  -- accent.cedille
}

return M
