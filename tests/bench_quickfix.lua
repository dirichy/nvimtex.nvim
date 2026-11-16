-- Run backends in separate processes; see docs/quickfix.md for commands.
local repo = vim.fn.getcwd()
vim.opt.runtimepath:prepend(repo)
local backend = vim.env.QF_BACKEND or "nvimtex"
local reference = vim.env.VIMTEX_PATH or repo .. "/.dev/vimtex"
local root = vim.env.QF_BENCH_ROOT or "/tmp/nvimtex-quickfix-bench"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "\\documentclass{article}" }, root .. "/main.tex")
vim.fn.writefile({ "text" }, root .. "/child.tex")
local dense = { "**main.tex", "(./main.tex" }
for i = 1, 300 do
	dense[#dense + 1] = "(./child.tex"
	for _ = 1, 20 do
		dense[#dense + 1] = "ordinary TeX tracing output"
	end
	dense[#dense + 1] = "Overfull \\hbox (" .. i .. "pt too wide) at line 1"
	dense[#dense + 1] = ")"
end
vim.fn.writefile(dense, root .. "/main.log")
local large = { "**large.tex" }
vim.fn.writefile({ "text" }, root .. "/large.tex")
for i = 1, 20000 do
	large[#large + 1] = i % 250 == 0 and "./large.tex:1: Undefined control sequence." or "ordinary TeX tracing output"
end
vim.fn.writefile(large, root .. "/large.log")
local cases = {
	{ "messages", repo .. "/tests/fixtures/quickfix/vimtex/example-quickfix/main.tex" },
	{ "spaces", repo .. "/tests/fixtures/quickfix/vimtex/test-quickfix/file with errors.tex" },
	{ "boxes", root .. "/main.tex" },
	{ "large", root .. "/large.tex" },
}
local run
if backend == "vimtex" then
	vim.opt.runtimepath:append(reference)
	vim.g.vimtex_quickfix_ignore_filters = {}
	vim.g.vimtex_quickfix_blgparser = { disable = true }
	vim.cmd("let qf=vimtex#qf#latexlog#new() | call qf.init({})")
	vim.cmd("let b:vimtex={'qf': qf, 'packages': {}}")
	run = function(main)
		vim.fn["vimtex#qf#setqflist"](main)
	end
else
	run = function(main)
		require("nvimtex.compile.quickfix").show({ path = main, open = false })
	end
end
local report = { backend = backend, results = {} }
for _, case in ipairs(cases) do
	vim.cmd.cd(vim.fs.dirname(case[2]))
	for _ = 1, 20 do
		run(case[2])
	end
	local samples = {}
	for _ = 1, 9 do
		collectgarbage("collect")
		local started = vim.uv.hrtime()
		for _ = 1, 30 do
			run(case[2])
		end
		samples[#samples + 1] = (vim.uv.hrtime() - started) / 1e6 / 30
	end
	table.sort(samples)
	local items = {}
	for _, item in ipairs(vim.fn.getqflist()) do
		items[#items + 1] = {
			file = vim.api.nvim_buf_get_name(item.bufnr),
			lnum = item.lnum,
			type = item.type,
			text = item.text,
		}
	end
	report.results[#report.results + 1] = { case = case[1], median_ms = samples[5], max_ms = samples[9], items = items }
	print(string.format("%s %s: %.3f ms (%d items)", backend, case[1], samples[5], #items))
end
vim.fn.writefile({ vim.json.encode(report) }, root .. "/" .. backend .. ".json")
