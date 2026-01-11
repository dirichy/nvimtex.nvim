local util = require("nvimtex.util")
--lsof -c sioyek | grep $file$
-- local sioyek_window_opened = false
local default_args = function(path)
	path = path or vim.fn.expand("%:p")
	local jobname = string.match(path, "([^/]*)%.tex$")
	local cwd = string.match(path, "(.*)/[^/]*%.tex$")
	local cursor = vim.api.nvim_win_get_cursor(0)[1]
	local servername = vim.v.servername

	local args = {
		"--inverse-search",
		"nvim --server " .. servername .. ' --remote-send "<cmd>edit %1 | call cursor(%2,%3)<cr>"',
		"--forward-search-file",
		path,
		"--forward-search-line",
		tostring(cursor),
		cwd .. "/" .. jobname .. ".pdf",
	}
	local command = "sioyek"
	vim.print(cwd, args)
	return { command = command, cwd = cwd, args = args }
end
local Job = require("plenary.job")
local function sioyek(args)
	if not vim.fn.executable("sioyek") then
		error("sioyek is not executable, make sure to install it and add it into PATH")
	end
	local path
	if util.get_magic_comment("root") then
		path = vim.fn.expand("%:p:h") .. "/" .. util.get_magic_comment("root")
		path = vim.fs.normalize(path)
	end
	path = path or vim.fn.expand("%:p")
	local opts = vim.tbl_deep_extend("force", default_args(path), args or {})
	-- local sioyek_is_loaded = vim.fn.system('ps aux| grep "[s]ioyek"')
	-- sioyek_is_loaded = sioyek_is_loaded:gsub("%s", "")
	-- sioyek_is_loaded = #sioyek_is_loaded ~= 0
	-- if not sioyek_is_loaded then
	Job:new(opts):start()
	-- sioyek_window_opened = true
	-- return
	-- end
	--flag: boolean, shows if there is no window for current file, i.e., need to open new window
	-- if not sioyek_window_opened then
	-- 	vim.fn.system("sioyek --execute-command new_window")
	-- 	sioyek_window_opened = true
	-- end
	-- Job:new(opts):start()
end
return sioyek
