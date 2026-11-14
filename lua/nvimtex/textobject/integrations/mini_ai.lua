local core = require("nvimtex.textobject.core")
local M = {}

---@class Nvimtex.MiniAi.Position
---@field line integer One-based line.
---@field col integer One-based byte column.
---@class Nvimtex.MiniAi.Region
---@field from Nvimtex.MiniAi.Position
---@field to? Nvimtex.MiniAi.Position Inclusive endpoint; absent for an empty region.
---@class Nvimtex.MiniAi.Options
---@field reference_region Nvimtex.MiniAi.Region
---@field n_times? integer

---@type table<Nvimtex.Textobject.Id,fun(ai_type:"a"|"i",id:string,opts:Nvimtex.MiniAi.Options):Nvimtex.MiniAi.Region?>
M.objects = {}

---MiniAi regions are one-based and end-inclusive. A missing `to` is a point;
---inclusive endpoints may address any byte of a UTF-8 character or a newline.
---A one-character Visual reference starts a cursor query, as in Pairwise.
---@param bufnr integer
---@param region Nvimtex.MiniAi.Region
---@return Range4
local function reference(bufnr, region)
	local from, to = region.from, region.to
	local row, col = from.line - 1, from.col - 1
	if not to or from.line == to.line and from.col == to.col then
		return { row, col, row, col }
	end
	local end_row = to.line - 1
	local line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or ""
	if to.col > #line then
		return { row, col, end_row + 1, 0 }
	end
	local end_col = vim.fn.byteidx(line, vim.fn.charidx(line, to.col - 1) + 1)
	return { row, col, end_row, end_col }
end

---@param bufnr integer
---@param range Range4
---@return Nvimtex.MiniAi.Region
local function region(bufnr, range)
	---@type Nvimtex.MiniAi.Region
	local result = { from = { line = range[1] + 1, col = range[2] + 1 } }
	if range[1] == range[3] and range[2] == range[4] then
		return result
	end
	local row, col = range[3], range[4]
	if col == 0 then
		row = row - 1
		col = #(vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "") + 1
	end
	result.to = { line = row + 1, col = col }
	return result
end

for _, id in ipairs(core.ids) do
	M.objects[id] = function(ai_type, _, opts)
		local bufnr = vim.api.nvim_get_current_buf()
		local range = core.find(id, {
			bufnr = bufnr,
			reference = reference(bufnr, opts.reference_region),
			inner = ai_type == "i",
			count = opts.n_times,
		})
		return range and region(bufnr, range) or nil
	end
end

---@param bufnr integer
---@return boolean installed
function M.setup_buf(bufnr)
	local ok = pcall(require, "mini.ai")
	if not ok then
		return false
	end
	-- Keep only buffer-local overrides; global MiniAi options remain live.
	local config = vim.deepcopy(vim.b[bufnr].miniai_config or {})
	config.custom_textobjects = vim.tbl_extend("force", config.custom_textobjects or {}, M.objects)
	vim.b[bufnr].miniai_config = config
	return true
end

return M
