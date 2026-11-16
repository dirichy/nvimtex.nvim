vim.opt.runtimepath:prepend(vim.fn.getcwd())

local latexmk = require("nvimtex.compile.latexmk")
local compile = require("nvimtex.compile")
local compile_util = require("nvimtex.compile.util")
local fixtures = vim.fn.getcwd() .. "/tests/fixtures/compile-real"
local tmp_root = vim.fn.tempname() .. " real compile tests"
vim.fn.mkdir(tmp_root, "p")
-- Keep normal installed formats/font caches; isolate only source and outputs.
local commands, notices, errors = {}, {}, {}
vim.notify = function(message)
	notices[#notices + 1] = message
end
compile_util.showbelow = function(lines)
	errors[#errors + 1] = table.concat(lines, "\n")
end

package.preload["plenary.job"] = function()
	return {
		new = function(_, spec)
			return {
				start = function()
					local argv = { spec.command }
					vim.list_extend(argv, spec.args)
					local result = vim.system(argv, { cwd = spec.cwd, text = true }):wait(60000)
					local output = (result.stdout or "") .. (result.stderr or "")
					commands[#commands + 1] = { spec = spec, output = output, code = result.code }
					spec.on_exit({
						result = function()
							return vim.split(output, "\n", { plain = true })
						end,
					}, result.code)
				end,
			}
		end,
	}
end

local function copy_fixture(case)
	local target = tmp_root .. "/" .. case.name
	vim.fn.mkdir(target, "p")
	for _, path in ipairs(vim.fn.glob(fixtures .. "/" .. (case.fixture or case.name) .. "/*", false, true)) do
		local name = vim.fn.fnamemodify(path, ":t")
		vim.fn.writefile(vim.fn.readfile(path, "b"), target .. "/" .. name, "b")
	end
	return target
end

local function build(root, args, child, project_rc)
	commands, notices, errors = {}, {}, {}
	local configured = vim.deepcopy(latexmk.config.args)
	if not project_rc then
		configured[#configured + 1] = "-norc"
	end
	vim.list_extend(configured, args or {})
	local opts = { path = root .. "/main.tex", args = configured }
	if child then
		vim.cmd.edit(vim.fn.fnameescape(root .. "/chapter.tex"))
		opts.path = nil
	end
	compile.default(opts)
	assert(
		vim.wait(1000, function()
			return #notices + #errors > 0
		end),
		"compile callback did not finish"
	)
	assert(#commands == 1 and commands[1].spec.command == "latexmk", "frontend must invoke latexmk once")
	return latexmk.compile_context(opts), commands[1].output
end

local function run_case(case)
	for _, executable in ipairs({ "latexmk", case.engine or "pdflatex", case.needs }) do
		if vim.fn.executable(executable) == 0 then
			print("skip " .. case.name .. ": missing " .. executable)
			return
		end
	end
	local root = copy_fixture(case)
	if case.rc then
		vim.fn.writefile(case.rc, root .. "/.latexmkrc")
	end
	local ctx, output = build(root, case.args, case.child, case.rc)
	assert(ctx.path == root .. "/main.tex", "build did not select main file")
	if case.failure then
		assert(#notices == 0 and #errors == 1, "unstable PGF build must fail without a success notification")
		assert(output:find("too many passes", 1, true), output)
	else
		assert(#errors == 0, table.concat(errors, "\n"))
		local output_dir = case.output and root .. "/" .. case.output or root
		local stem = case.jobname or "main"
		assert(vim.uv.fs_stat(output_dir .. "/" .. stem .. ".pdf"), case.name .. ": missing PDF")
		assert(vim.uv.fs_stat(output_dir .. "/" .. stem .. ".synctex.gz"), case.name .. ": missing SyncTeX")
		local log = table.concat(vim.fn.readfile(output_dir .. "/" .. stem .. ".log"), "\n")
		assert(not log:find("There were undefined references", 1, true), log)
		if case.minimum_runs then
			local runs = 0
			for _ in output:gmatch("Run number %d+ of rule 'pdflatex'") do
				runs = runs + 1
			end
			assert(runs >= case.minimum_runs, "TOC fixture must exercise more than two LaTeX passes: " .. output)
			assert(not log:find("Label(s) may have changed", 1, true), "TOC did not converge")
		end
		assert(vim.uv.fs_stat(output_dir .. "/" .. stem .. ".aux"), "latexmk auxiliary files missing")
		if case.output then
			assert(not vim.uv.fs_stat(root .. "/main.pdf"), "adapter copied custom PDF to source directory")
			assert(not vim.uv.fs_stat(root .. "/" .. stem .. ".log"), "adapter overrode project output directory")
		end
		if case.needs then
			local bbl = output_dir .. "/main.bbl"
			assert(vim.uv.fs_stat(bbl), case.name .. ": bibliography was not built")
			local refs = table.concat(vim.fn.readfile(root .. "/refs.bib"), "\n")
			refs = refs:gsub("The TeXbook", "An Updated Reference Title")
			vim.fn.writefile(vim.split(refs, "\n", { plain = true }), root .. "/refs.bib")
			build(root)
			assert(#errors == 0, table.concat(errors, "\n"))
			assert(
				table.concat(vim.fn.readfile(bbl), "\n"):find("Updated", 1, true),
				"edited bibliography was not rebuilt"
			)
		end
		local _, unchanged = build(root, case.args, nil, case.rc)
		assert(#errors == 0, table.concat(errors, "\n"))
		assert(unchanged:find("Nothing to do", 1, true), "unchanged project was not reused: " .. unchanged)
	end
	print("ok real latexmk " .. case.name)
end

for _, case in ipairs({
	{ name = "simple" },
	{
		name = "custom-output",
		fixture = "simple",
		output = "custom build",
		jobname = "renamed",
		rc = { "$out_dir = 'custom build';", "$jobname = 'renamed';" },
	},
	{
		name = "args-output",
		fixture = "simple",
		output = "args build",
		jobname = "renamed",
		args = { "-outdir=args build", "-jobname=renamed" },
	},
	{ name = "magic-xelatex", engine = "xelatex" },
	{ name = "magic-lualatex", engine = "lualatex" },
	{ name = "rerun-label" },
	{ name = "subfiles", child = true },
	{ name = "toc", minimum_runs = 3 },
	{ name = "bibtex", needs = "bibtex" },
	{ name = "biber", needs = "biber" },
	{ name = "pgf-drift", engine = "xelatex", failure = true, args = { "-e", "$max_repeat=3;" } },
	{ name = "pgf-filter", fixture = "pgf-drift", engine = "xelatex", args = { "-r", "ignore-pgf.rc" } },
}) do
	run_case(case)
end
