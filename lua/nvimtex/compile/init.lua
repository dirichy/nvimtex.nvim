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

---Open a TeX log; pass a .log path for custom output directories/jobnames.
---@param path? string TeX or log file path. Defaults to the declared main file.
---@return nil
function M.showlog(path)
	path = path or require("nvimtex.util").main_file()
	return require("nvimtex.compile.util").showlog(path)
end

setmetatable(M, {
	__call = function(_, opts)
		return M.default(opts)
	end,
})
return M
