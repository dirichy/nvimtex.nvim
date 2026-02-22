local M = {}
M.ns_id = {
	inline = vim.api.nvim_create_namespace("nvimtex.inline"),
	virtline = vim.api.nvim_create_namespace("nvimtex.virtline"),
	fast = vim.api.nvim_create_namespace("nvimtex.fast"),
}
return M
