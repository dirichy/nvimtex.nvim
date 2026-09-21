local util = require("nvimtex.util")
util.showlog = require("nvimtex.compile.util").showlog
util.showbelow = require("nvimtex.compile.util").showbelow
local Job = require("plenary.job")

---@class nvimtex.compile.AraraJobSpec
---@field command string
---@field cwd string
---@field args string[]
---@field on_exit fun(job: table, return_val: integer)

---Build the plenary.job spec for arara.
---@param path? string TeX source path. Defaults to the current buffer.
---@return nvimtex.compile.AraraJobSpec
local function default_args(path)
	path = path or vim.fn.expand("%:p")
	local jobname = vim.fn.fnamemodify(path, ":t:r")
	local cwd = vim.fn.fnamemodify(path, ":h")
	local args = { jobname }
	local command = "arara"

	local on_exit = function(j, return_val)
		if return_val == 0 then
			local out = table.concat(j:result(), "\n")
			vim.notify(out, vim.log.levels.INFO)
		elseif return_val == 1 then
			local out = table.concat(j:result(), "\n")
			vim.notify(out, vim.log.levels.INFO)
			vim.schedule(function()
				util.showlog(path)
			end)
		elseif return_val == 2 then
			vim.schedule(function()
				util.showbelow(j:result())
			end)
		end
	end

	return { command = command, cwd = cwd, args = args, on_exit = on_exit }
end

---Run arara for the current TeX file.
---@param opts? table Overrides passed to plenary.job.
---@return nil
local function arara(opts)
	local path
	local magic_comment = util.get_magic_comment()
	if magic_comment.root then
		path = vim.fn.expand("%:p:h") .. "/" .. magic_comment.root
		path = vim.fs.normalize(path)
	end
	local args = vim.tbl_deep_extend("force", default_args(path), opts or {})
	Job:new(args):start()
end

return arara
