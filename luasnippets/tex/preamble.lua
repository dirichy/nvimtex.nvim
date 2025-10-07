local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local line_begin = require("luasnip.extras.expand_conditions").line_begin
local rep = require("luasnip.extras").rep
local fmta = require("luasnip.extras.fmt").fmta
local tex = require("nvimtex.conditions.luasnip")
M = {
	s({ trig = "pkg", snippetType = "autosnippet" }, {
		t("\\usepackage{"),
		i(1),
		t("}"),
	}, { condition = tex.in_preamble * line_begin }),
	s(
		{ trig = "(%d?)(r?)env", regTrig = true, snippetType = "autosnippet" },
		fmta(
			[[
    \<>newenvironment{<>}<>%
    {<>}%
    {<>}
    ]],
			{
				f(function(_, snip)
					return snip.captures[2] ~= "" and "re" or ""
				end),
				i(1),
				f(function(_, snip)
					return snip.captures[1] ~= "" and "[" .. snip.captures[1] .. "]" or ""
				end),
				i(2),
				i(3),
			}
		),
		{ condition = tex.in_preamble * line_begin }
	),
	s(
		{ trig = "(%d?)(r?)cmd", regTrig = true, snippetType = "autosnippet" },
		fmta("\\<>newcommand{\\<>}<>{<>}", {
			f(function(_, snip)
				return snip.captures[2] ~= "" and "re" or ""
			end),
			i(1),
			f(function(_, snip)
				return snip.captures[1] ~= "" and "[" .. snip.captures[1] .. "]" or ""
			end),
			i(2),
		}),
		{ condition = tex.in_preamble * line_begin }
	),
	s(
		{ trig = "opt", snippetType = "autosnippet" },
		fmta("\\DeclareMathOperator{\\<>}{<>}", {
			i(1),
			rep(1),
		}),
		{ condition = tex.in_preamble * line_begin }
	),
	s(
		{ trig = "Opt", snippetType = "autosnippet" },
		fmta("\\DeclareMathOperator{\\<>}{<>}", {
			i(1),
			i(2),
		}),
		{ condition = tex.in_preamble * line_begin }
	),
	s(
		{ trig = "thm", snippetType = "autosnippet" },
		fmta("\\newtheorem{<>}{<>}", {
			i(1),
			i(2),
		}),
		{ condition = tex.in_preamble * line_begin }
	),
	s(
		{ trig = "@@@", snippetType = "autosnippet" },
		fmta(
			[[
\makeatletter
<>
\makeatother
    ]],
			{
				i(1),
			}
		),
		{ condition = tex.in_preamble * line_begin }
	),
	s(
		{ trig = " ", snippetType = "autosnippet", priority = 1000 },
		fmta(
			[[
%arara: <>
\documentclass{<>}
<>
\begin{document}
<>
\end{document}
      ]],
			{
				f(function(args, snip)
					if args and args[1] and args[1][1] == "ctexart" then
						return "xelatex"
					end
					return "pdflatex"
				end, { 1 }),
				i(1),
				d(2, function()
					-- local input = vim.fn.input({ prompt = "Math?y/n" }):lower()
					if true then
						return sn(
							nil,
							fmta(
								[=[
\usepackage{amsmath,amssymb,amsthm,bbm}
\newtheorem{definition}{Definition}
\newtheorem{theorem}{Theorem}
\newtheorem{problem}{Problem}
\newtheorem{solution}{Solution}
\everymath{\displaystyle}
\newlength\inlineHeight
\newlength\inlineWidth
\long\def\(#1\){%
  \settoheight{\inlineHeight}{$#1$}%
  \settowidth{\inlineWidth}{$#1$}%
  \ifdim \inlineWidth >> 0.5\textwidth%
  $$#1$$%
  \else%
  \ifdim \inlineHeight >> 1.5em%
  $$#1$$%
  \else%
  $#1$%
  \fi%
  \fi%
}
<>
]=],
								{ i(1) }
							)
						)
					end
					return sn(nil, { i(1) })
				end),
				i(0),
			}
		),
		{ condition = tex.in_preamble * line_begin * function()
			return vim.api.nvim_buf_line_count(0) == 1
		end }
	),
}
return M
