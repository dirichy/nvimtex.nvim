vim.opt.runtimepath:prepend(vim.fn.getcwd())

local tmp_root = "/tmp/nvimtex.nvim-tests"
vim.fn.delete(tmp_root, "rf")
vim.fn.mkdir(tmp_root, "p")

local active_case
local commands
local notifications
local smart = require("nvimtex.compile.smart")

vim.notify = function(message)
	table.insert(notifications, message)
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

					if spec.command == "pdflatex" then
						local dir = output_dir(spec.args)
						vim.fn.mkdir(dir, "p")
						vim.fn.writefile(active_case.new_aux or {}, dir .. "/" .. active_case.jobname .. ".aux")
						vim.fn.writefile(active_case.new_bcf or {}, dir .. "/" .. active_case.jobname .. ".bcf")
						vim.fn.writefile({ "%PDF" }, dir .. "/" .. active_case.jobname .. ".pdf")
						vim.fn.writefile({ "SyncTeX" }, dir .. "/" .. active_case.jobname .. ".synctex.gz")
					elseif spec.command == "bibtex" or spec.command == "biber" or spec.command == "mybibtex" then
						vim.fn.writefile({ "\\entry{knuth}" }, spec.cwd .. "/" .. active_case.jobname .. ".bbl")
					else
						error("unexpected command: " .. spec.command)
					end

					spec.on_exit({
						result = function()
							return {}
						end,
					}, 0)
				end,
			}
		end,
	}
end

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function command_names()
	local result = {}
	for _, item in ipairs(commands) do
		table.insert(result, item.command)
	end
	return result
end

local function assert_summary(case)
	local summary = notifications[#notifications]
	if type(summary) ~= "string" then
		error(case.name .. ": missing summary notification")
	end
	if not summary:find("nvimtex compile succeeded", 1, true) then
		error(case.name .. ": summary missing status")
	end
	if not summary:find("chain: " .. table.concat(case.expected, " -> "), 1, true) then
		error(case.name .. ": summary missing command chain: " .. summary)
	end
	if not summary:find("total:", 1, true) then
		error(case.name .. ": summary missing total time")
	end
	for index, command in ipairs(case.expected) do
		if not summary:find(index .. ". " .. command, 1, true) then
			error(case.name .. ": summary missing step " .. index .. ": " .. summary)
		end
	end
end

local function run_case(case)
	active_case = case
	commands = {}
	notifications = {}

	local root = tmp_root .. "/" .. case.name
	local build_root = root .. "/build"
	local path = root .. "/" .. case.jobname .. ".tex"
	local build_dir = vim.fs.normalize(build_root .. "/" .. vim.fn.sha256(path))

	vim.fn.mkdir(root, "p")
	vim.fn.mkdir(build_dir, "p")
	vim.fn.writefile(vim.split(case.source, "\n", { plain = true }), path)
	for name, lines in pairs(case.files or {}) do
		vim.fn.writefile(lines, root .. "/" .. name)
	end
	if case.old_aux then
		vim.fn.writefile(case.old_aux, build_dir .. "/" .. case.jobname .. ".aux")
	end
	if case.old_bcf then
		vim.fn.writefile(case.old_bcf, build_dir .. "/" .. case.jobname .. ".bcf")
	end
	if case.old_bbl then
		vim.fn.writefile(case.old_bbl, build_dir .. "/" .. case.jobname .. ".bbl")
	end
	if case.old_bbl_mtime then
		vim.uv.fs_utime(build_dir .. "/" .. case.jobname .. ".bbl", case.old_bbl_mtime, case.old_bbl_mtime)
	end

	local old_config = vim.deepcopy(smart.config)
	if case.config then
		smart.setup(case.config)
	end

	smart.compile({
		source = case.source,
		path = path,
		command = "pdflatex",
		build_root = build_root,
		bib = case.bib,
	})

	vim.wait(1000, function()
		return #commands >= #case.expected
			and vim.uv.fs_stat(root .. "/" .. case.jobname .. ".pdf") ~= nil
			and vim.uv.fs_stat(root .. "/" .. case.jobname .. ".synctex.gz") ~= nil
			and #notifications > 0
	end)

	eq(command_names(), case.expected, case.name .. " command sequence")
	assert_summary(case)
	if case.expected_bib_cwd then
		eq(commands[2].cwd, build_dir, case.name .. " bib cwd")
		eq(commands[2].args[1], case.jobname, case.name .. " bib jobname")
	end
	if not vim.uv.fs_stat(root .. "/" .. case.jobname .. ".pdf") then
		error(case.name .. ": pdf was not copied to source dir")
	end
	if not vim.uv.fs_stat(root .. "/" .. case.jobname .. ".synctex.gz") then
		error(case.name .. ": synctex was not copied to source dir")
	end
	for _, ext in ipairs({ "aux", "log", "bbl", "bcf", "blg" }) do
		if vim.uv.fs_stat(root .. "/" .. case.jobname .. "." .. ext) then
			error(case.name .. ": ." .. ext .. " leaked into source dir")
		end
	end
	smart.config = old_config
end

local cases = {
	{
		name = "single_latex_when_aux_is_unchanged",
		jobname = "main",
		source = "\\documentclass{article}\n\\begin{document}hello\\end{document}",
		old_aux = { "\\relax" },
		new_aux = { "\\relax" },
		expected = { "pdflatex" },
	},
	{
		name = "second_latex_when_aux_changes_without_bib",
		jobname = "main",
		source = "\\documentclass{article}\n\\begin{document}\\ref{x}\\end{document}",
		old_aux = { "\\relax" },
		new_aux = { "\\relax", "\\newlabel{x}{{1}{1}}" },
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "pgfsyspdfmark_aux_noise_is_ignored",
		jobname = "main",
		source = "\\documentclass{article}\n\\begin{document}tikz\\end{document}",
		old_aux = { "\\relax", "\\pgfsyspdfmark {pgfid1}{1}{1}" },
		new_aux = { "\\relax", "\\pgfsyspdfmark {pgfid1}{2}{2}" },
		expected = { "pdflatex" },
	},
	{
		name = "pgfsyspdfmark_aux_insert_needs_rerun",
		jobname = "main",
		source = "\\documentclass{article}\n\\begin{document}tikz\\end{document}",
		old_aux = { "\\relax" },
		new_aux = { "\\relax", "\\pgfsyspdfmark {pgfid1}{2}{2}" },
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "custom_bcf_noise_is_ignored",
		jobname = "main",
		source = "\\documentclass{article}\n\\begin{document}noise\\end{document}",
		config = {
			rerun = {
				skip = {
					bcf = { "^<noise" },
				},
			},
		},
		old_aux = { "\\relax" },
		new_aux = { "\\relax" },
		old_bcf = { '<noise value="1" />' },
		new_bcf = { '<noise value="2" />' },
		bib = { enabled = false },
		expected = { "pdflatex" },
	},
	{
		name = "bibtex_runs_between_latex_passes",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}\n\\bibliographystyle{plain}\n\\bibliography{refs}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		expected = { "pdflatex", "bibtex", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
	{
		name = "biber_runs_for_biblatex",
		jobname = "paper",
		source = "\\documentclass{article}\n\\usepackage{biblatex}\n\\addbibresource{refs.bib}\n\\printbibliography",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		new_aux = { "\\relax" },
		new_bcf = { '<bcf:datasource type="file">refs.bib</bcf:datasource>' },
		expected = { "pdflatex", "biber", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
	{
		name = "explicit_bibtex_overrides_biber_hints",
		jobname = "paper",
		source = "% !TeX bib-program = biber\n\\documentclass{article}\n\\bibliography{refs}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		bib = { backend = "bibtex" },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		expected = { "pdflatex", "bibtex", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
	{
		name = "disabled_bib_skips_bibliography_backend",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}\n\\bibliography{refs}",
		bib = { enabled = false },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibdata{refs}" },
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "disabled_bib_bcf_change_runs_only_latex",
		jobname = "paper",
		source = "\\documentclass{article}\n\\usepackage{biblatex}\n\\addbibresource{refs.bib}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		bib = { enabled = false },
		old_aux = { "\\relax" },
		new_aux = { "\\relax" },
		old_bcf = {},
		new_bcf = { '<bcf:datasource type="file">refs.bib</bcf:datasource>' },
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "aux_artifact_falls_back_to_bibtex",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		expected = { "pdflatex", "bibtex", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
	{
		name = "aux_citation_without_bibdata_does_not_run_bibtex",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}",
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}" },
		expected = { "pdflatex", "pdflatex" },
	},
	{
		name = "bcf_artifact_falls_back_to_biber",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		new_aux = { "\\relax" },
		new_bcf = { '<bcf:datasource type="file">refs.bib</bcf:datasource>' },
		expected = { "pdflatex", "biber", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
	{
		name = "existing_bbl_and_unchanged_control_skip_bib",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}\n\\bibliographystyle{plain}\n\\bibliography{refs}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		old_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		old_bbl = { "\\entry{knuth}" },
		expected = { "pdflatex" },
	},
	{
		name = "newer_bib_file_reruns_bib",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}\n\\bibliographystyle{plain}\n\\bibliography{refs}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		old_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		old_bbl = { "\\entry{knuth}" },
		old_bbl_mtime = 1,
		expected = { "pdflatex", "bibtex", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
	{
		name = "custom_bibtex_command_is_used",
		jobname = "paper",
		source = "\\documentclass{article}\n\\cite{knuth}\n\\bibliographystyle{plain}\n\\bibliography{refs}",
		files = { ["refs.bib"] = { "@book{knuth,title={T}}" } },
		bib = { commands = { bibtex = "mybibtex" } },
		new_aux = { "\\relax", "\\citation{knuth}", "\\bibstyle{plain}", "\\bibdata{refs}" },
		expected = { "pdflatex", "mybibtex", "pdflatex", "pdflatex" },
		expected_bib_cwd = true,
	},
}

for _, case in ipairs(cases) do
	run_case(case)
	print("ok " .. case.name)
end
print("")
