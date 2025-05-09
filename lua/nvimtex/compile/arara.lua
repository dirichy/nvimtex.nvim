local util = require("nvimtex.util")
util.showlog = require("nvimtex.compile.util").showlog
util.showbelow = require("nvimtex.compile.util").showbelow
local Job = require("plenary.job")

--- 构造默认 arara 参数
local function default_args(path)
	path = path or vim.fn.expand("%:p")
	-- 提取文件名（去除路径和.tex扩展名）
	local jobname = vim.fn.fnamemodify(path, ":t:r") --(path, "([^/]*)%.tex$")
	-- 获取文件所在目录
	local cwd = vim.fn.fnamemodify(path, ":h") --(path, "(.*)/[^/]*%.tex$")
	local args = { jobname }
	local command = "arara"

	local on_exit = function(j, return_val)
		if return_val == 0 then
			-- 直接 notify，无需 schedule
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

--- arara 命令主入口，仅返回此函数
local function arara(opts)
	local path
	if util.get_magic_comment("root") then
		path = vim.fn.expand("%:p:h") .. "/" .. util.get_magic_comment("root")
		path = vim.fs.normalize(path)
	end
	local args = vim.tbl_deep_extend("force", default_args(path), opts or {})
	Job:new(args):start()
end

return arara
