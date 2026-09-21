---@class nvimtex.compile.JobStat
---@field command string
---@field cwd string
---@field args string[]
---@field code integer
---@field elapsed_ms number

local M = {}

---@return table
local function get_job()
	return require("plenary.job")
end

---Notify the raw output collected from a plenary.job instance.
---@param j table
function M.show_job_result(j)
	local out = table.concat(j:result(), "\n")
	if out ~= "" then
		vim.notify(out, vim.log.levels.INFO)
	end
end

---Run an async command and report timing metadata to the success callback.
---@param command string
---@param cwd string
---@param args string[]
---@param on_success fun(job: table, stat: nvimtex.compile.JobStat)
function M.run_job(command, cwd, args, on_success)
	local started = vim.uv.hrtime()
	local on_exit = function(j, return_val)
		local elapsed_ms = (vim.uv.hrtime() - started) / 1000000
		local stat = {
			command = command,
			cwd = cwd,
			args = args,
			code = return_val,
			elapsed_ms = elapsed_ms,
		}
		if return_val == 0 then
			vim.schedule(function()
				on_success(j, stat)
			end)
		else
			vim.schedule(function()
				M.showbelow(j:result())
			end)
		end
	end
	get_job():new({ command = command, cwd = cwd, args = args, on_exit = on_exit }):start()
end

---Open a filtered TeX log below the current window.
---@param path? string TeX source path. Defaults to the current buffer.
---@param opts? { build_root?: string }
function M.showlog(path, opts)
	opts = opts or {}
	path = path or vim.fn.expand("%:p")
	local jobname = vim.fn.fnamemodify(path, ":t:r")
	local cwd = vim.fn.fnamemodify(path, ":h")
	local build_root = opts.build_root or (vim.env.TMPDIR or "/tmp") .. "/nvimtex.nvim"
	local build_log = vim.fs.normalize(build_root .. "/" .. vim.fn.sha256(path) .. "/" .. jobname .. ".log")
	local log_path = vim.uv.fs_stat(build_log) and build_log or cwd .. "/" .. jobname .. ".log"
	local lines = vim.fn.systemlist({ "texlogsieve", log_path, "--color" })
	M.showbelow(lines)
end

---Show lines in a scratch split using baleia for ANSI color rendering.
---@param lines string[]
function M.showbelow(lines)
	local total = vim.o.lines
	local height = math.floor(total * 0.3)
	if height < 1 then
		height = 1
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		win = 0,
		split = "below",
		height = height,
	})

	require("baleia").setup({}).buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_set_option_value("filetype", "terminal", { scope = "local", buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { scope = "local", buf = buf })
	vim.api.nvim_set_option_value("concealcursor", "nvic", { scope = "local", win = win })

	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
end
return M
