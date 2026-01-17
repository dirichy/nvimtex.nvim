local M = {}

M.__index = M

M._defaults = {
	view = {
		viewer = "sioyek",
	},
}

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", M._defaults, opts == nil and {} or opts)
	M.args = opts
	require("nvimtex.view").setup(opts.view)
end

function M._deinit() end

return M
