local surround = require("nvimtex.surround")
local filetypes = require("nvimtex.util").latex_filetypes
local M = {}

---@class Nvimtex.Surround.Options
---@field keyflow? boolean Enable transient math conversion; defaults to false.
---@field keymaps? {upgrade_math?:string|false, downgrade_math?:string|false}

---@param action fun():boolean
---@param count integer
---@return boolean
local function repeat_action(action, count)
	for _ = 1, count do
		if not action() then
			return false
		end
	end
	return true
end

---@param opts? Nvimtex.Surround.Options|false
function M.setup(opts)
	local group = vim.api.nvim_create_augroup("nvimtex.surround", { clear = true })
	if opts == false then
		return
	end
	opts = opts or {}
	local keys = vim.tbl_extend("force", {
		upgrade_math = "m<C-a>",
		downgrade_math = "m<C-x>",
	}, opts.keymaps or {})
	local actions = {
		upgrade_math = { key = "<C-a>", run = surround.upgrade_math, desc = "Upgrade math environment" },
		downgrade_math = { key = "<C-x>", run = surround.downgrade_math, desc = "Downgrade math environment" },
	}
	assert(
		keys.upgrade_math == false or keys.downgrade_math == false or keys.upgrade_math ~= keys.downgrade_math,
		"math upgrade and downgrade mappings must differ"
	)
	---@type Keyflow.Mode?
	local mode
	if opts.keyflow then
		local maps = {}
		for name, action in pairs(actions) do
			if keys[name] ~= false then
				maps[action.key] = {
					desc = action.desc,
					action = function(self, _, count)
						if not repeat_action(action.run, math.max(count, 1)) then
							self:exit()
						end
					end,
				}
			end
		end
		mode = require("keyflow").mode({
			name = "Math environments",
			vimmode = "n",
			count_mode = true,
			maps = maps,
		})
	end
	local function setup_buf(bufnr)
		if not vim.api.nvim_buf_is_loaded(bufnr) or not vim.tbl_contains(filetypes, vim.bo[bufnr].filetype) then
			return
		end
		for name, action in pairs(actions) do
			if keys[name] ~= false then
				vim.keymap.set("n", keys[name], function()
					if mode then
						mode:run({ action.key }, vim.v.count)
					else
						repeat_action(action.run, vim.v.count1)
					end
				end, { buffer = bufnr, silent = true, desc = action.desc })
			end
		end
	end
	vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
		group = group,
		callback = function(event)
			setup_buf(event.buf)
		end,
	})
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		setup_buf(bufnr)
	end
end

return M
