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
M = {
  autosnippet(
    {
      trig = "([%a%)%]])(%d)",
      wordTrig = true,
      regTrig = true,
      hidden = true,
    },
    fmta(
      [[
   <>_<><>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math, show_condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "(\\[^%(%[][%a%d%[%]{}]-[%a}%]])(%d)",
      regTrig = true,
      hidden = true,
    },
    fmta(
      [[
   <>_<><>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%)}%]])_([^{\\][%d%a%+%-]+) ",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>_{<>} <>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%d%)}%]])^([^{\\][%d%a%+%-]+) ",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>^{<>} <>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%)}%]|])%.([%a%d])",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>_<><>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%d%)}%]|])'([%a%d%*])",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>^<><>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%)}%]|])%.%.([^%.%s])",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>_{<><>}<>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(1),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%d%)}%]|])''([^%.%s])",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>^{<><>}<>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        f(function(_, snip)
          return snip.captures[2]
        end),
        i(1),
        i(0),
      }
    ),
    { condition = tex.in_math }
  ),
  autosnippet(
    {
      trig = "([%a%d%)}%]|])`",
      regTrig = true,
      wordTrig = false,
      hidden = true,
    },
    fmta(
      [[
   <>^{(<>)}<>
    ]],
      {
        f(function(_, snip)
          return snip.captures[1]
        end),
        i(1),
        i(0),
      }
    ),
    { condition = tex.in_math, show_condition = tex.in_math }
  ),
}
return M
