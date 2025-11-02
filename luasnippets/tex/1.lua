local ls = require("luasnip")
local tex = require("nvimtex.conditions.luasnip")
vim.on_key(function(key, typed)
	if vim.fn.mode() == "i" and tex.in_math() then
		if vim.fn.keytrans(typed):match("[^%a]") then
			ls.expand()
		end
	end
end, vim.api.nvim_create_namespace("nvimtex"))
