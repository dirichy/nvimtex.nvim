---@class nvimtex.compile
local M = {}

---Run the arara backend for the current TeX file.
---@param opts? table Overrides passed to plenary.job.
---@return nil
function M.arara(opts)
	return require("nvimtex.compile.arara")(opts)
end

---Configure the default smart backend.
---@param opts? table
---@return nil
function M.setup(opts)
	return require("nvimtex.compile.smart").setup(opts)
end

---Run the default smart backend.
---@param opts? table
---@return nil
function M.default(opts)
	return require("nvimtex.compile.smart").compile(opts)
end

---Open the compile log for the current TeX file.
---@param path? string TeX file path. Defaults to the current buffer path.
---@return nil
function M.showlog(path)
	local smart = require("nvimtex.compile.smart")
	return require("nvimtex.compile.util").showlog(path, { build_root = smart.config.build_root })
end
setmetatable(M, {
	__call = M.default,
})
return M
