local M = {}
M.ns_id = {
	inline = vim.api.nvim_create_namespace("nvimtex.inline"),
	command = vim.api.nvim_create_namespace("nvimtex.command"),
	virtline = vim.api.nvim_create_namespace("nvimtex.virtline"),
	fast = vim.api.nvim_create_namespace("nvimtex.fast"),
	conceal = vim.api.nvim_create_namespace("nvimtex"),
}
return M
