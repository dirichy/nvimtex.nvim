local util = require("nvimtex.util")
local compile_util = require("nvimtex.compile.util")
local Job = require("plenary.job")

---@class nvimtex.compile.AraraJobSpec
---@field command string
---@field cwd string
---@field args string[]
---@field on_exit fun(job: table, return_val: integer)

---Build the plenary.job spec for arara.
---@param path? string TeX source path. Defaults to the current buffer.
---@param opts table
---@return nvimtex.compile.AraraJobSpec
local function default_args(path, opts)
	path = path or vim.fn.expand("%:p")
	local jobname = vim.fn.fnamemodify(path, ":t:r")
	local cwd = vim.fn.fnamemodify(path, ":h")
	local args = { jobname }
	local command = "arara"

	local on_exit = function(j, return_val)
		vim.schedule(function()
			local handled = require("nvimtex.compile.quickfix").update(
				path,
				return_val,
				require("nvimtex.compile.latexmk").config.quickfix,
				opts
			)
			if return_val == 0 then
				compile_util.show_job_result(j)
			elseif not handled then
				compile_util.showbelow(j:result())
			end
		end)
	end

	return { command = command, cwd = cwd, args = args, on_exit = on_exit }
end

---Run arara for the current TeX file.
---@param opts? table Job overrides and optional log/blg paths.
---@return nil
local function arara(opts)
	opts = opts or {}
	local path = util.main_file()
	local logs = { log = opts.log, blg = opts.blg }
	local job_opts = vim.tbl_extend("force", {}, opts)
	job_opts.log, job_opts.blg = nil, nil
	local args = vim.tbl_deep_extend("force", default_args(path, logs), job_opts)
	Job:new(args):start()
end

return arara
