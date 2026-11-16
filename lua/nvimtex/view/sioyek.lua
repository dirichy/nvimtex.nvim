local util = require("nvimtex.util")
--lsof -c sioyek | grep $file$
-- local sioyek_window_opened = false
local default_args = function(path)
	path = path or vim.fn.expand("%:p")
	local jobname = string.match(path, "([^/]*)%.tex$")
	local cwd = string.match(path, "(.*)/[^/]*%.tex$")
	local cursor = vim.api.nvim_win_get_cursor(0)[1]
	local source = vim.api.nvim_buf_get_name(0)
	local servername = vim.v.servername
	--HACK: sioyek version is same, but some version support new_instance. use --help is very dirty
	local sioyek_support_new_instance = vim.system({ "sioyek", "--help" }):wait()
	sioyek_support_new_instance = string.find(sioyek_support_new_instance.stdout, "--instance-name", nil, true)

	local args
	if sioyek_support_new_instance then
		args = {
			"--instance-name",
			vim.fn.sha256(servername),
			"--inverse-search",
			"nvim --server " .. servername .. ' --remote-send "<cmd>edit %1 | call cursor(%2,%3)<cr>"',
			"--forward-search-file",
			source,
			"--forward-search-line",
			tostring(cursor),
			cwd .. "/" .. jobname .. ".pdf",
		}
	else
		args = {
			"--inverse-search",
			"nvim --server " .. servername .. ' --remote-send "<cmd>edit %1 | call cursor(%2,%3)<cr>"',
			"--forward-search-file",
			source,
			"--forward-search-line",
			tostring(cursor),
			cwd .. "/" .. jobname .. ".pdf",
		}
	end
	local command = "sioyek"
	return { command = command, cwd = cwd, args = args }
end
local handle = nil
local function sioyek(args)
	if vim.fn.executable("sioyek") == 0 then
		error("sioyek is not executable, make sure to install it and add it into PATH")
	end
	local path = util.main_file()
	local opts = vim.tbl_deep_extend("force", default_args(path), args or {})
	handle = vim.uv.spawn(opts.command, opts)
	assert(handle, "can't open sioyek")
	return handle
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
