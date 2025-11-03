local ls = require("luasnip")
local tex = require("nvimtex.conditions.luasnip")
local puncts = {
	["<Esc>"] = true,
	["`"] = true,
	["/"] = true,
	['"'] = true,
	["."] = true,
	["'"] = true,
}
vim.on_key(function(key, typed)
	if vim.fn.mode() == "i" and tex.in_math() then
		if puncts[vim.fn.keytrans(typed)] then
			ls.expand()
		end
	end
end, vim.api.nvim_create_namespace("nvimtex"))
