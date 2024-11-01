local M = {}

M.__index = M

M._defaults = {}

function M.setup(args)
	args = vim.tbl_deep_extend("force", M._defaults, args == nil and {} or args)
	M.args = args
end

function M._deinit() end

return M
