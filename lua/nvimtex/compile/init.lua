local M = {}
M.arara = require("nvimtex.compile.arara")
M.default = require("nvimtex.compile.smart").compile
M.showlog = require("nvimtex.compile.util").showlog
setmetatable(M, {
	__call = M.default,
})
return M
