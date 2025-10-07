-- local font = require("nvimtex.latex.mathfont")

local function iter_on_alphabet()
	local i = string.byte("a") - 1
	return function()
		if i == string.byte("z") then
			i = string.byte("A")
		elseif i == string.byte("Z") then
			return
		else
			i = i + 1
		end
		return string.char(i)
	end
end
local M = vim.tbl_extend(
	"force",
	{},
	require("nvimtex.latex.symbols"),
	require("nvimtex.latex.hugeoperator").items,
	require("nvimtex.latex.mathfont").items
)

local function withonearg(source)
	local alias = source.alias
	local conceal = source.conceal
	local tex = source.tex
	local class = source.class
	if string.match(alias, "%%a") then
		for c in iter_on_alphabet() do
			table.insert(M, {
				conceal = type(conceal) == "function" and (conceal(c) or "") or conceal[c],
				class = class,
				tex = type(tex) == "function" and tex(c) or string.gsub(tex, "%%1", c),
				alias = type(alias) == "function" and alias(c) or string.gsub(alias, "%(%%a%)", c),
			})
		end
	else
		error("can't parse one arg latex item", 3)
	end
end

for key, value in pairs(M) do
	if value.onechar_expand then
		withonearg(value.onechar_expand)
	end
end
return M
