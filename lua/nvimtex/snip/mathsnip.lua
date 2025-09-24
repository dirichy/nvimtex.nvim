local mathfont = require("nvimtex.symbol.mathfont")
local M = {
	mathbb = {
		conceal = mathfont.mathbb,
		class = "font",
		tex = function(char)
			if char and #char > 0 then
				return [[\mathbb{]] .. string.upper(char) .. "}"
			end
			return "\\mathbb"
		end,
		alias = "bb(%a)",
		narg = 1,
	},
	mathbm = {
		conceal = mathfont.mathbm,
	},
}

return M
