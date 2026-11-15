local M = {}
---@type {setup_buf: fun(bufnr:integer):boolean}?
local integration
local filetypes = require("nvimtex.util").latex_filetypes
local adapters = { ["mini.ai"] = "mini_ai", pairwise = "pairwise" }

---@param bufnr? integer
---@return boolean installed
function M.setup_buf(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if integration and vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(filetypes, vim.bo[bufnr].filetype) then
		return integration.setup_buf(bufnr)
	end
	return false
end

---@class Nvimtex.Textobject.Options
---@field integration? "mini.ai"|"pairwise" Defaults to mini.ai.

---@param opts? Nvimtex.Textobject.Options|false
function M.setup(opts)
	local group = vim.api.nvim_create_augroup("nvimtex.textobject", { clear = true })
	if opts == false then
		integration = nil
		return
	end
	local name = opts and opts.integration or "mini.ai"
	assert(adapters[name], "unknown textobject integration: " .. tostring(name))
	integration = require("nvimtex.textobject.integrations." .. adapters[name])
	vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
		group = group,
		callback = function(event)
			M.setup_buf(event.buf)
		end,
	})
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		M.setup_buf(bufnr)
	end
end

return M
