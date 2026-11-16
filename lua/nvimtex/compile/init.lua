---@class nvimtex.compile
local M = {}

---Run the arara backend for the current TeX file.
---@param opts? table Overrides passed to plenary.job.
---@return nil
function M.arara(opts)
	return require("nvimtex.compile.arara")(opts)
end

---Configure the default latexmk backend.
---@param opts? table
---@return nil
function M.setup(opts)
	return require("nvimtex.compile.latexmk").setup(opts)
end

---Run the default latexmk backend.
---@param opts? nvimtex.compile.Options
---@return nil
function M.default(opts)
	return require("nvimtex.compile.latexmk").compile(opts)
end

---Open the compile log for the current TeX file.
---@param path? string TeX file path. Defaults to the current buffer path.
---@return nil
function M.showlog(path)
	local latexmk = require("nvimtex.compile.latexmk")
	path = path or require("nvimtex.util").main_file()
	return require("nvimtex.compile.util").showlog(path, { build_root = latexmk.config.build_root })
end
setmetatable(M, {
	__call = function(_, opts)
		return M.default(opts)
	end,
})
return M
