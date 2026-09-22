local M = {}
--TODO: implement winid
function M.viewport(win)
	win = win or vim.api.nvim_get_current_win()
	return vim.fn.line("w0", win) - 1, vim.fn.line("w$", win) - 1
end

function M.node_in_screen(lnode, top, bottom)
	if top == nil then
		top, bottom = M.viewport()
	end
	local start_row, _, end_row = lnode:range()
	return start_row <= bottom and end_row >= top
end
return M
