local M = {}
--TODO: implement winid
function M.node_in_screen(lnode, win)
	local a, b, c, d = lnode:range()
	local top = vim.fn.line("w0")
	local btm = vim.fn.line("w$")
	return a <= btm and c >= top
end
return M
