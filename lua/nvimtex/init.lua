local M = {}

M.__index = M

M._defaults = {
	view = {
		viewer = "sioyek",
	},
	compile = {},
	conceal = {},
}

function M.setup(opts)
	opts = vim.tbl_deep_extend("force", M._defaults, opts == nil and {} or opts)
	M.args = opts
	require("nvimtex.compile").setup(opts.compile)
	require("nvimtex.view").setup(opts.view)
	require("nvimtex.conceal").setup(opts.conceal)
	require("nvimtex.textobject").setup_buf()
end

function M._deinit() end

return M
