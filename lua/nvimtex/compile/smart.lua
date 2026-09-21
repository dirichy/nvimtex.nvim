---@alias nvimtex.compile.CompilerName "pdflatex"|"xelatex"|"lualatex"
---@alias nvimtex.compile.BibBackend "bibtex"|"biber"
---@alias nvimtex.compile.BibBackendConfig "auto"|"bibtex"|"biber"

---@class nvimtex.compile.SmartBibConfig
---@field enabled boolean
---@field backend nvimtex.compile.BibBackendConfig
---@field commands table<nvimtex.compile.BibBackend, string>

---@class nvimtex.compile.SmartConfig
---@field favor nvimtex.compile.CompilerName[]
---@field compile_args string[]
---@field build_root string
---@field bib nvimtex.compile.SmartBibConfig
---@field rerun { skip: table<string, string[]> }
---@field detection nvimtex.compile.SmartDetectionConfig

---@class nvimtex.compile.SmartDetectionConfig
---@field documentclasses table<string, nvimtex.compile.CompilerSet>
---@field documentclass_prefixes { prefix: string, engines: nvimtex.compile.CompilerSet }[]
---@field compiler_magic_keys string[]
---@field packages { name: string, engines: nvimtex.compile.CompilerSet }[]
---@field bib_backend_aliases table<string, nvimtex.compile.BibBackend>
---@field bib_magic_keys string[]
---@field bib_packages { name: string, backend: nvimtex.compile.BibBackend }[]
---@field bib_commands table<string, { backend: nvimtex.compile.BibBackend, files?: "single"|"list" }>

---@class nvimtex.compile.CompilerSet
---@field pdflatex? boolean
---@field xelatex? boolean
---@field lualatex? boolean

---@class nvimtex.compile.BibliographyScan
---@field files string[]
---@field backend? nvimtex.compile.BibBackend

---@class nvimtex.compile.SmartContext
---@field source number|string
---@field bibliography nvimtex.compile.BibliographyScan
---@field path string
---@field jobname string
---@field cwd string
---@field build_dir string
---@field command nvimtex.compile.CompilerName|string
---@field compile_args string[]
---@field jobs nvimtex.compile.JobStat[]
---@field started_at integer

---@class nvimtex.compile.BibRunContext
---@field backend? nvimtex.compile.BibBackend
---@field aux string[]
---@field bcf string[]
---@field bib_files string[]
---@field old_control string[]
---@field bbl_path string
---@field control_extension string

---@class nvimtex.compile.JobSpec
---@field command string
---@field cwd string
---@field args string[]

local M = {
	---@type nvimtex.compile.SmartConfig
	config = {
		favor = { "pdflatex", "xelatex", "lualatex" },
		compile_args = { "-interaction=nonstopmode", "-file-line-error", "-synctex=1" },
		build_root = (vim.env.TMPDIR or "/tmp") .. "/nvimtex.nvim",
		bib = {
			enabled = true,
			backend = "auto",
			commands = {
				biber = "biber",
				bibtex = "bibtex",
			},
		},
		rerun = {
			skip = {
				aux = { "^%s*\\pgfsyspdfmark" },
			},
		},
		detection = {
			documentclasses = {
				ctexart = { xelatex = true, lualatex = true },
				ctexbook = { xelatex = true, lualatex = true },
				article = { pdflatex = true, xelatex = true, lualatex = true },
				book = { pdflatex = true, xelatex = true, lualatex = true },
				ctexbeamer = { xelatex = true, lualatex = true },
			},
			documentclass_prefixes = {
				{ prefix = "lua", engines = { lualatex = true } },
				{ prefix = "ctex", engines = { xelatex = true, lualatex = true } },
			},
			compiler_magic_keys = { "ts-program", "program" },
			packages = {
				{ name = "xeCJK", engines = { xelatex = true } },
				{ name = "luatexja", engines = { lualatex = true } },
				{ name = "luacode", engines = { lualatex = true } },
				{ name = "luadraw", engines = { lualatex = true } },
				{ name = "CJK", engines = { pdflatex = true } },
				{ name = "ctex", engines = { xelatex = true, lualatex = true } },
				{ name = "fontspec", engines = { xelatex = true, lualatex = true } },
				{ name = "unicode-math", engines = { xelatex = true, lualatex = true } },
			},
			bib_backend_aliases = {
				bibtex = "bibtex",
				bibtex8 = "bibtex",
				upbibtex = "bibtex",
				pbibtex = "bibtex",
				biber = "biber",
			},
			bib_magic_keys = { "bib-program", "bibtex-program", "bib-engine", "bibliography-program" },
			bib_packages = {
				{ name = "natbib", backend = "bibtex" },
				{ name = "cite", backend = "bibtex" },
				{ name = "chapterbib", backend = "bibtex" },
				{ name = "multibib", backend = "bibtex" },
			},
			bib_commands = {
				addbibresource = { backend = "biber", files = "single" },
				bibliography = { backend = "bibtex", files = "list" },
				printbibliography = { backend = "biber" },
			},
		},
	},
}
local util = require("nvimtex.util")
local compile_util = require("nvimtex.compile.util")

local compiler_names = { "pdflatex", "xelatex", "lualatex" }
local all_compiler_set = {}
for _, name in ipairs(compiler_names) do
	all_compiler_set[name] = true
end

---@type table<nvimtex.compile.BibBackend, nvimtex.compile.BibBackend>
local bib_backend = {
	bibtex = "bibtex",
	biber = "biber",
}

---@param left nvimtex.compile.CompilerSet
---@param right nvimtex.compile.CompilerSet
---@return nvimtex.compile.CompilerSet
local function intersect_compiler_sets(left, right)
	local result = {}
	for _, name in ipairs(compiler_names) do
		result[name] = left[name] and right[name] or nil
	end
	return result
end

---Merge user options into the smart compiler configuration.
---@param opts? table
---@return nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

---Infer allowed compilers from the document class.
---@param source number|string
---@return nvimtex.compile.CompilerSet
function M.get_compiler_by_documentclass(source)
	local class = util.get_documentclass(source)
	local detection = M.config.detection
	local result = detection.documentclasses[class.name]
	if not result then
		for _, rule in ipairs(detection.documentclass_prefixes) do
			if string.match(class.name, "^" .. rule.prefix) then
				result = rule.engines
				break
			end
		end
	end
	return result or all_compiler_set
end

---Infer allowed compilers from TeX magic comments.
---@param source number|string
---@return nvimtex.compile.CompilerSet?
function M.get_compiler_by_magic_comment(source)
	local magic_comment = util.get_magic_comment(source)
	for _, key in ipairs(M.config.detection.compiler_magic_keys) do
		local command = magic_comment[key]
		if command and all_compiler_set[command] then
			return { [command] = true }
		end
	end
end

---Infer allowed compilers from packages that imply an engine.
---@param source number|string
---@return nvimtex.compile.CompilerSet
function M.get_compiler_by_packages(source)
	local packages = util.get_packages(source)
	local result = all_compiler_set
	for _, rule in ipairs(M.config.detection.packages) do
		if packages[rule.name] then
			result = intersect_compiler_sets(result, rule.engines)
		end
	end
	return result
end

---Resolve the concrete compiler using detected constraints and configured preference order.
---@param buffer number
---@return nvimtex.compile.CompilerName?
function M.get_compiler(buffer)
	local magic_comment = M.get_compiler_by_magic_comment(buffer)
	local packages = M.get_compiler_by_packages(buffer)
	local documentclass = M.get_compiler_by_documentclass(buffer)
	local res = magic_comment or intersect_compiler_sets(packages, documentclass)
	for _, program in ipairs(M.config.favor) do
		if res[program] then
			return program
		end
	end
end

---Return true when a generated control file changed, ignoring configured same-line noise.
---@param old string[]
---@param new string[]
---@param extension string
---@return boolean
local function control_changed(old, new, extension)
	local patterns = M.config.rerun.skip[extension] or {}
	if #old ~= #new then
		return true
	end
	for i = 1, #old do
		local same_line_noise = false
		for _, pattern in ipairs(patterns) do
			if old[i]:match(pattern) and new[i]:match(pattern) then
				same_line_noise = true
				break
			end
		end
		if not same_line_noise and old[i] ~= new[i] then
			return true
		end
	end
	return false
end

---Normalize common BibTeX-family command names to the backend class.
---@param value? string
---@return nvimtex.compile.BibBackend?
local function normalize_bib_backend(value)
	if not value then
		return nil
	end
	value = string.lower(value)
	return M.config.detection.bib_backend_aliases[value]
end

---@param files string[]
---@param cwd string
---@param csv string
local function add_bib_files(files, cwd, csv)
	for raw_path in csv:gmatch("[^,]+") do
		local path = vim.trim(raw_path)
		if path ~= "" then
			table.insert(files, util.normalize_file(path, { cwd = cwd, extension = "bib" }))
		end
	end
end

---@param ctx nvimtex.compile.SmartContext
---@param scope "build"|"output"
---@param extension string
---@return string
local function artifact_path(ctx, scope, extension)
	local dir = scope == "build" and ctx.build_dir or ctx.cwd
	return util.file_path(dir, ctx.jobname, extension)
end

---@param result nvimtex.compile.BibliographyScan
---@param cwd string
---@param command string
---@param value? string
local function apply_bib_command(result, cwd, command, value)
	local rule = M.config.detection.bib_commands[command]
	if not rule then
		return
	end
	if not result.backend then
		result.backend = rule.backend
	end
	if value and rule.files == "single" then
		table.insert(result.files, util.normalize_file(value, { cwd = cwd, extension = "bib" }))
	elseif value and rule.files == "list" then
		add_bib_files(result.files, cwd, value)
	end
end

---Scan source-level bibliography hints that are independent of build artifacts.
---@param source number|string
---@param cwd string
---@return nvimtex.compile.BibliographyScan
local function scan_bibliography(source, cwd)
	local result = { files = {} }
	local magic_comment = util.get_magic_comment(source)

	for _, key in ipairs(M.config.detection.bib_magic_keys) do
		result.backend = normalize_bib_backend(magic_comment[key])
		if result.backend then
			break
		end
	end

	local packages = not result.backend and util.get_packages(source)
	if packages then
		if packages.biblatex then
			result.backend = normalize_bib_backend(packages.biblatex.opts.backend) or bib_backend.biber
		else
			for _, rule in ipairs(M.config.detection.bib_packages) do
				if packages[rule.name] then
					result.backend = rule.backend
					break
				end
			end
		end
	end

	local ok = pcall(function()
		local root
		if type(source) == "number" then
			root = vim.treesitter.get_parser(source, "latex"):trees()[1]:root()
		else
			root = vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
		end
		local query = vim.treesitter.query.parse(
			"latex",
			[[
					(biblatex_include) @biblatex
					(bibtex_include) @bibtex
					(generic_command) @generic
				]]
		)

		for capture, node in query:iter_captures(root, source, 0, -1) do
			local name = query.captures[capture]
			if name == "biblatex" then
				local glob = node:field("glob")[1]
				local value = glob and vim.treesitter.get_node_text(glob, source):match("^%s*{(.-)}%s*$")
				apply_bib_command(result, cwd, "addbibresource", value)
			elseif name == "bibtex" then
				local paths = node:field("paths")[1]
				local value = paths and vim.treesitter.get_node_text(paths, source):match("^%s*{(.-)}%s*$")
				apply_bib_command(result, cwd, "bibliography", value)
			elseif name == "generic" then
				local command_node = node:field("command")[1]
				local command = command_node and vim.treesitter.get_node_text(command_node, source):sub(2)
				if M.config.detection.bib_commands[command] then
					local arg_node = node:field("arg")[1]
					local value = arg_node and vim.treesitter.get_node_text(arg_node, source):match("^%s*{(.-)}%s*$")
					apply_bib_command(result, cwd, command, value)
				end
			end
		end
	end)
	if ok then
		return result
	end

	for _, line in ipairs(util.source_lines(source)) do
		line = line:gsub("%%.*$", "")
		for start, command in line:gmatch("()\\([%a@]+)") do
			local rule = M.config.detection.bib_commands[command]
			if rule then
				local index = start + #command + 1
				while line:sub(index, index):match("%s") do
					index = index + 1
				end
				if line:sub(index, index) == "[" then
					local _, close = line:find("%b[]", index)
					if close then
						index = close + 1
					end
				end
				while line:sub(index, index):match("%s") do
					index = index + 1
				end
				local value
				if line:sub(index, index) == "{" then
					local open, close = line:find("%b{}", index)
					if open and close then
						value = line:sub(open + 1, close - 1)
					end
				end
				apply_bib_command(result, cwd, command, value)
			end
		end
	end
	return result
end

---Fallback bibliography detection from LaTeX-generated control files.
---@param aux string[]
---@param bcf string[]
---@param cwd string
---@return nvimtex.compile.BibliographyScan
local function artifact_bibliography(aux, bcf, cwd)
	local result = { files = {} }
	if #bcf > 0 then
		result.backend = bib_backend.biber
		for _, line in ipairs(bcf) do
			local path = line:match("<bcf:datasource[^>]*>(.-)</bcf:datasource>")
			if path and path:match("%.bib$") then
				table.insert(result.files, util.normalize_file(path, { cwd = cwd, extension = "bib" }))
			end
		end
		return result
	end

	for _, line in ipairs(aux) do
		local bibdata = line:match("^\\bibdata{(.-)}")
		if bibdata then
			result.backend = bib_backend.bibtex
			add_bib_files(result.files, cwd, bibdata)
		end
	end
	return result
end

---@param ctx nvimtex.compile.BibRunContext
---@return boolean
local function bib_need_run(ctx)
	if ctx.backend == nil then
		return false
	end
	local control = ctx.backend == bib_backend.biber and ctx.bcf or ctx.aux
	if #control == 0 then
		return false
	end
	if not vim.uv.fs_stat(ctx.bbl_path) then
		return true
	end
	for _, path in ipairs(ctx.bib_files or {}) do
		if util.file_newer_than(path, ctx.bbl_path) then
			return true
		end
	end
	return control_changed(ctx.old_control, control, ctx.control_extension)
end

---@param ctx nvimtex.compile.SmartContext
---@param files string[]
local function copy_bib_files(ctx, files)
	for _, path in ipairs(files or {}) do
		if vim.uv.fs_stat(path) then
			local target = ctx.build_dir .. "/" .. util.relative_path(ctx.cwd, path)
			local parent = vim.fs.dirname(target)
			if parent then
				util.ensure_dir(parent)
			end
			util.copy_file(path, target)
		end
	end
end

---@param ctx nvimtex.compile.SmartContext
local function copy_outputs(ctx)
	util.copy_file(artifact_path(ctx, "build", "pdf"), artifact_path(ctx, "output", "pdf"))
	util.copy_file(artifact_path(ctx, "build", "synctex.gz"), artifact_path(ctx, "output", "synctex.gz"))
end

---@param ms number
---@return string
local function format_elapsed(ms)
	if ms >= 1000 then
		return string.format("%.2fs", ms / 1000)
	end
	return string.format("%.0fms", ms)
end

---@param ctx nvimtex.compile.SmartContext
local function summarize(ctx)
	local names = {}
	local lines = { "nvimtex compile succeeded" }
	for i, job in ipairs(ctx.jobs) do
		table.insert(names, job.command)
		table.insert(lines, string.format("%d. %s %s", i, job.command, format_elapsed(job.elapsed_ms)))
	end
	table.insert(lines, 2, "chain: " .. table.concat(names, " -> "))
	table.insert(lines, 3, "total: " .. format_elapsed((vim.uv.hrtime() - ctx.started_at) / 1000000))
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param ctx nvimtex.compile.SmartContext
---@param jobs nvimtex.compile.JobSpec[]
---@param on_success fun()
local function run_jobs(ctx, jobs, on_success)
	local index = 1
	local function next_job()
		local spec = jobs[index]
		if not spec then
			on_success()
			return
		end
		index = index + 1
		compile_util.run_job(spec.command, spec.cwd, spec.args, function(_, stat)
			table.insert(ctx.jobs, stat)
			next_job()
		end)
	end
	next_job()
end

---Build all derived paths and compile arguments for a smart compile run.
---@param opts? table
---@return nvimtex.compile.SmartContext
function M.compile_context(opts)
	opts = opts or {}
	--TODO: maybe source is not current buffer
	local source = opts.source or vim.api.nvim_win_get_buf(0)
	local path = opts.path or vim.fn.expand("%:p")
	local jobname = vim.fn.fnamemodify(path, ":t:r")
	local cwd = vim.fn.fnamemodify(path, ":h")
	local build_root = opts.build_root or M.config.build_root
	local build_dir = util.ensure_dir(vim.fs.normalize(build_root .. "/" .. vim.fn.sha256(path)))
	local command = opts.command or M.get_compiler(source)
	if not command then
		error("Can't guess which compiler to use, please set compiler mamually")
	end
	local compile_args = vim.deepcopy(opts.compile_args or M.config.compile_args)
	table.insert(compile_args, "-output-directory=" .. build_dir)
	table.insert(compile_args, jobname)
	return {
		source = source,
		bibliography = scan_bibliography(source, cwd),
		path = path,
		jobname = jobname,
		cwd = cwd,
		build_dir = build_dir,
		command = command,
		compile_args = compile_args,
		jobs = {},
		started_at = vim.uv.hrtime(),
	}
end

---Run the built-in smart compile pipeline.
---@param opts? table
---@return nil
function M.compile(opts)
	opts = opts or {}
	local ctx = M.compile_context(opts)
	local old_aux = util.readfile(artifact_path(ctx, "build", "aux"))
	local old_bcf = util.readfile(artifact_path(ctx, "build", "bcf"))

	run_jobs(ctx, {
		{ command = ctx.command, cwd = ctx.cwd, args = ctx.compile_args },
	}, function()
		local new_aux = util.readfile(artifact_path(ctx, "build", "aux"))
		local new_bcf = util.readfile(artifact_path(ctx, "build", "bcf"))
		local artifact_bib = artifact_bibliography(new_aux, new_bcf, ctx.cwd)
		local bib_config = vim.tbl_deep_extend("force", M.config.bib, opts.bib or {})
		local backend
		if bib_config.enabled ~= false then
			backend = normalize_bib_backend(bib_config.backend) or ctx.bibliography.backend or artifact_bib.backend
		end
		local bib_ctx = {
			backend = backend,
			aux = new_aux,
			bcf = new_bcf,
			bib_files = #ctx.bibliography.files > 0 and ctx.bibliography.files or artifact_bib.files,
			old_control = backend == bib_backend.biber and old_bcf or old_aux,
			bbl_path = artifact_path(ctx, "build", "bbl"),
			control_extension = backend == bib_backend.biber and "bcf" or "aux",
		}
		if bib_need_run(bib_ctx) then
			local command = bib_config.commands[backend] or backend
			copy_bib_files(ctx, bib_ctx.bib_files)
			run_jobs(ctx, {
				{ command = command, cwd = ctx.build_dir, args = { ctx.jobname } },
				{ command = ctx.command, cwd = ctx.cwd, args = ctx.compile_args },
				{ command = ctx.command, cwd = ctx.cwd, args = ctx.compile_args },
			}, function()
				copy_outputs(ctx)
				summarize(ctx)
			end)
			return
		end

		if control_changed(old_aux, new_aux, "aux") or control_changed(old_bcf, new_bcf, "bcf") then
			run_jobs(ctx, {
				{ command = ctx.command, cwd = ctx.cwd, args = ctx.compile_args },
			}, function()
				copy_outputs(ctx)
				summarize(ctx)
			end)
			return
		end

		copy_outputs(ctx)
		summarize(ctx)
	end)
end
return M
