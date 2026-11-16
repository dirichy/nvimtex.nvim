local log = require("nvimtex.compile.log")
local util = require("nvimtex.util")
local M = {}

---@class nvimtex.compile.ErrorOptions
---@field path? string Main TeX file; defaults to the current document's declared main.
---@field log? string Exact .log path, relative to the main file's directory or absolute.
---@field blg? string Exact .blg path; defaults to the .log basename.
---@field ignore? string[] Vim regular expressions matched against messages.
---@field open? boolean Open a nonempty list without moving focus. Defaults to true.

---@param opts? nvimtex.compile.ErrorOptions
---@return nvimtex.compile.LogEntry[]
---@return string main
function M.read(opts)
	opts = opts or {}
	local main = vim.fs.normalize(vim.fn.fnamemodify(opts.path or util.main_file(), ":p"))
	local root = vim.fs.dirname(main)
	local logfile = util.normalize_file(opts.log or vim.fn.fnamemodify(main, ":r") .. ".log", { cwd = root })
	local items = log.latex(main, logfile)
	vim.list_extend(
		items,
		require("nvimtex.compile.bibliography").read(
			main,
			util.normalize_file(opts.blg or vim.fn.fnamemodify(logfile, ":r") .. ".blg", { cwd = root })
		)
	)
	local patterns = {}
	for _, pattern in ipairs(opts.ignore or {}) do
		patterns[#patterns + 1] = vim.regex(pattern)
	end
	local errors, warnings = {}, {}
	for _, item in ipairs(items) do
		local ignored = false
		for _, pattern in ipairs(patterns) do
			if pattern:match_str(item.text) then
				ignored = true
				break
			end
		end
		if not ignored then
			local target = item.type == "E" and errors or warnings
			target[#target + 1] = item
		end
	end
	return vim.list_extend(errors, warnings), main
end

---Read saved logs and replace this project's current nvimtex quickfix list.
---@param opts? nvimtex.compile.ErrorOptions
---@return nvimtex.compile.LogEntry[]
function M.show(opts)
	opts = opts or {}
	local items, main = M.read(opts)
	local current = vim.fn.getqflist({ context = 1 })
	local owned = type(current.context) == "table" and current.context.nvimtex == main
	if not owned and #items == 0 then
		return items
	end
	vim.fn.setqflist({}, owned and "r" or " ", {
		title = "nvimtex: " .. vim.fs.basename(main),
		context = { nvimtex = main },
		items = items,
	})
	if opts.open ~= false and #items > 0 then
		local win = vim.api.nvim_get_current_win()
		vim.cmd("botright copen")
		vim.api.nvim_set_current_win(win)
	elseif owned and #items == 0 then
		vim.cmd.cclose()
	end
	return items
end

return M
