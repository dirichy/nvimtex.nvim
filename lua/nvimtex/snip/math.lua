local M = {}

M.symbol = require("nvimtex.latex.items")
M.snip = {
	["mn"] = "-",
	["dot"] = "\\dot{<>}",
	-- ["fun"] = "\\fun{<>}{<>}",
	["deq"] = "\\overset{d}{=}",
	["sta"] = "^{*}",
	["rhs"] = "\\mathrm{R.H.S}",
	["sqrt"] = "\\sqrt{<>}",
	["ceil"] = "\\ceil{<>}",
	["aeeq"] = "\\overset{\\text{a.e.}}{=}",
	["hat"] = "\\hat{<>}",
	["abs"] = "|<>|",
	["lhs"] = "\\mathrm{L.H.S}",
	["pto"] = "\\overset{\\mathbb{P}}{\\to}",
	["asto"] = "\\overset{\\text{a.s.}}{\\to}",
	["udl"] = "\\underline{<>}",
	["lgd"] = "\\legendre{<>}{<>}",
	["ad"] = "+",
	["tdl"] = "\\tidle{<>}",
	["flor"] = "\\floor{<>}",
	["aseq"] = "\\overset{\\text{a.s.}}{=}",
	["bar"] = "\\overline{<>}",
	["pmat"] = "pmat",
	["cob"] = "\\binom{<>}{<>}",
	["res"] = "\\res{<>}{<>}",
	["dto"] = "\\overset{d}{\\to}",
	["pmod"] = "\\pmod{<>}",
	["vec"] = "\\vec{<>}",
	["norm"] = "\\norm{<>}",
}
M.snip2expand = {
	["(%a)tr"] = [[%1^{\mathsf{T}}]],
	["(%a)sta"] = [[%1^{*}]],
	-- ["frk(%a)"] = [[\mathfrak{%1}]],
	-- ["(%a)bar"] = [[\overline{%1}]],
	["(%a)hat"] = [[\hat{%1}]],
	["(%a)tdl"] = [[\tilde{%1}]],
	["(%a)vec"] = [[\vec{%1}]],
	["(%a)dot"] = [[\dot{%1}]],
	["(%a)cob"] = [[\binom{%1}{<>}]],
}
M.luasnip = M.snip

for _, value in pairs(M.symbol) do
	local narg = value.narg or 0
	M.luasnip[value.alias] = value.tex .. string.rep("{<>}", narg)
end

for k, v in pairs(M.snip2expand) do
	local k1 = string.gsub(k, "%(%%a%)", "%%s")
	for i = string.byte("a"), string.byte("z") do
		local c = string.char(i)
		local cmd = string.format(k1, c)
		M.luasnip[cmd] = string.gsub(cmd, k, v)
	end
	for i = string.byte("A"), string.byte("Z") do
		local c = string.char(i)
		local cmd = string.format(k1, c)
		M.luasnip[cmd] = string.gsub(cmd, k, v)
	end
end
return M
