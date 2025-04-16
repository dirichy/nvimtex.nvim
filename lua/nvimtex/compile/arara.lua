local util = require("nvimtex.util")
local default_args = function(path)
	path = path or vim.fn.expand("%:p")
	local jobname = string.match(path, "([^/]*)%.tex$")
	local cwd = string.match(path, "(.*)/[^/]*%.tex$")
	local args = { jobname }
	local command = "arara"
	local on_exit = function(j, return_val)
		local out = ""
		for _, line in ipairs(j:result()) do
			out = out .. line .. "\n"
		end
		if return_val == 0 then
			vim.notify(out, vim.log.levels.INFO)
		else
			vim.notify(out, vim.log.levels.WARN)
		end
	end
	return { command = command, cwd = cwd, args = args, on_exit = on_exit }
end
local Job = require("plenary.job")
local function arara(args)
	local path
	if util.get_magic_comment("root") then
		path = vim.fn.expand("%:p:h") .. "/" .. util.get_magic_comment("root")
		path = vim.fs.normalize(path)
	end
	local opts = vim.tbl_deep_extend("force", default_args(path), args or {})
	Job:new(opts):start()
end
return arara
