local M = {}

M.symbol = require("nvimtex.latex.items")
M.snip = {
	-- ["mn"] = "-",
	["dot"] = "\\dot{<>}",
	-- ["fun"] = "\\fun{<>}{<>}",
	["deq"] = "\\overset{d}{=}",
	["sqrt"] = "\\sqrt{<>}",
	["ceil"] = "\\ceil{<>}",
	["aeeq"] = "\\overset{\\text{a.e.}}{=}",
	["hat"] = "\\hat{<>}",
	["abs"] = "|<>|",
	["udl"] = "\\underline{<>}",
	["lgd"] = "\\legendre{<>}{<>}",
	["tdl"] = "\\tidle{<>}",
	["flor"] = "\\floor{<>}",
	["bar"] = "\\overline{<>}",
	["cob"] = "\\binom{<>}{<>}",
	["res"] = "\\res{<>}{<>}",
	["pmod"] = "\\pmod{<>}",
	["vec"] = "\\vec{<>}",
	["norm"] = "\\norm{<>}",
	["dia"] = "\\diag(<>)",
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
M.luasnip = vim.deepcopy(M.snip)

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
