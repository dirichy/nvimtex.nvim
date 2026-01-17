local M = {}
M.zathura = require("nvimtex.view.zathura")
M.sioyek = require("nvimtex.view.sioyek")
M.opts = {}
function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts)
end
local handle = nil
vim.api.nvim_create_autocmd("VimLeave", {
	callback = function()
		if handle then
			handle:kill()
		end
	end,
})
function M.view()
	if handle and handle:is_active() then
		return M[M.opts.viewer]()
	else
		handle = M[M.opts.viewer]()
		return M[M.opts.viewer]()
	end
end
local sync_id
function M.sync()
	M.view()
	if not sync_id then
		sync_id = vim.api.nvim_create_autocmd("CursorMoved", {
			callback = function()
				if handle and handle:is_active() then
					M.view()
				end
			end,
			buffer = vim.api.nvim_win_get_buf(0),
		})
	else
		vim.api.nvim_del_autocmd(sync_id)
		sync_id = nil
	end
end
return M
