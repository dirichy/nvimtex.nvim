vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.notify = function() end

local fixtures = vim.fn.getcwd() .. "/tests/fixtures/compile-real"
local tmp_root = "/tmp/nvimtex.nvim-real-tests"
vim.fn.delete(tmp_root, "rf")
vim.fn.mkdir(tmp_root, "p")
vim.env.TEXMFVAR = tmp_root .. "/texmf-var"
vim.env.TEXMFCACHE = tmp_root .. "/texmf-cache"
vim.fn.mkdir(vim.env.TEXMFVAR, "p")
vim.fn.mkdir(vim.env.TEXMFCACHE, "p")

local commands = {}

package.preload["plenary.job"] = function()
	return {
		new = function(_, spec)
			return {
				start = function()
					table.insert(commands, {
						command = spec.command,
						cwd = spec.cwd,
						args = vim.deepcopy(spec.args or {}),
					})
					local argv = { spec.command }
					vim.list_extend(argv, spec.args or {})
					local result = vim.system(argv, { cwd = spec.cwd, text = true }):wait()
					local output = {}
					vim.list_extend(output, vim.split(result.stdout or "", "\n", { plain = true, trimempty = true }))
					vim.list_extend(output, vim.split(result.stderr or "", "\n", { plain = true, trimempty = true }))
					if result.code ~= 0 then
						error(table.concat(output, "\n"))
					end
					spec.on_exit({
						result = function()
							return output
						end,
					}, result.code)
				end,
			}
		end,
	}
end

local function copy_fixture(name)
	local source = fixtures .. "/" .. name
	local target = tmp_root .. "/" .. name
	vim.fn.mkdir(target, "p")
	for _, path in ipairs(vim.fn.glob(source .. "/*", false, true)) do
		local basename = vim.fn.fnamemodify(path, ":t")
		if not basename:match("%.pdf$") and not basename:match("%.synctex%.gz$") then
			vim.fn.writefile(vim.fn.readfile(path, "b"), target .. "/" .. basename, "b")
		end
	end
	return target
end

local function output_dir(args)
	for _, arg in ipairs(args or {}) do
		local dir = arg:match("^%-output%-directory=(.*)$")
		if dir then
			return dir
		end
	end
	error("missing -output-directory")
end

local function command_names()
	local result = {}
	for _, item in ipairs(commands) do
		table.insert(result, item.command)
	end
	return result
end

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local usable = {}
local function can_compile_with(command)
	if usable[command] ~= nil then
		return usable[command]
	end
	local root = tmp_root .. "/probe-" .. command
	local build = root .. "/build"
	vim.fn.mkdir(build, "p")
	vim.fn.writefile({
		"\\documentclass{article}",
		"\\begin{document}",
		"probe",
		"\\end{document}",
	}, root .. "/main.tex")
	local result = vim.system({
		command,
		"-interaction=nonstopmode",
		"-file-line-error",
		"-synctex=1",
		"-output-directory=" .. build,
		"main",
	}, { cwd = root, text = true }):wait()
	usable[command] = result.code == 0
	return usable[command]
end

local function assert_outputs(root, build_dir, name)
	if not vim.uv.fs_stat(root .. "/main.pdf") then
		error(name .. ": pdf missing from source dir")
	end
	if not vim.uv.fs_stat(root .. "/main.synctex.gz") then
		error(name .. ": synctex missing from source dir")
	end
	if not vim.uv.fs_stat(build_dir .. "/main.aux") then
		error(name .. ": aux missing from build dir")
	end
	if not vim.uv.fs_stat(build_dir .. "/main.log") then
		error(name .. ": log missing from build dir")
	end
	for _, ext in ipairs({ "aux", "log", "bbl", "bcf", "blg" }) do
		if vim.uv.fs_stat(root .. "/main." .. ext) then
			error(name .. ": ." .. ext .. " leaked into source dir")
		end
	end
end

local function run_case(case)
	if vim.fn.executable(case.expected[1]) == 0 then
		print("skip " .. case.name .. ": missing " .. case.expected[1])
		return
	end
	if case.probe_engine and not can_compile_with(case.expected[1]) then
		print("skip " .. case.name .. ": " .. case.expected[1] .. " cannot compile cleanly")
		return
	end
	if case.needs and vim.fn.executable(case.needs) == 0 then
		print("skip " .. case.name .. ": missing " .. case.needs)
		return
	end

	commands = {}
	local root = copy_fixture(case.name)
	local build_root = root .. "/build"
	local tex_path = root .. "/main.tex"
	local source = table.concat(vim.fn.readfile(tex_path), "\n")

	local opts = {
		source = source,
		path = tex_path,
		build_root = build_root,
	}
	if case.command then
		opts.command = case.command
	end
	require("nvimtex.compile.smart").compile(opts)

	vim.wait(15000, function()
		return #commands >= #case.expected and vim.uv.fs_stat(root .. "/main.pdf") ~= nil
	end)

	eq(command_names(), case.expected, case.name .. " command sequence")
	local build_dir = output_dir(commands[1].args)
	assert_outputs(root, build_dir, case.name)
	if case.expected_bib then
		eq(commands[2].cwd, build_dir, case.name .. " bibliography cwd")
		eq(commands[2].args[1], "main", case.name .. " bibliography jobname")
		if not vim.uv.fs_stat(build_dir .. "/main.bbl") then
			error(case.name .. ": bbl missing from build dir")
		end
	end
	print("ok real " .. case.name)
end

local cases = {
	{
		name = "simple",
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "magic-xelatex",
		expected = { "xelatex", "xelatex" },
	},
	{
		name = "magic-lualatex",
		expected = { "lualatex", "lualatex" },
		probe_engine = true,
	},
	{
		name = "rerun-label",
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "bibtex",
		expected = { "pdflatex", "bibtex", "pdflatex", "pdflatex" },
		needs = "bibtex",
		expected_bib = true,
	},
	{
		name = "biber",
		expected = { "pdflatex", "biber", "pdflatex", "pdflatex" },
		needs = "biber",
		expected_bib = true,
	},
}

for _, case in ipairs(cases) do
	run_case(case)
end
