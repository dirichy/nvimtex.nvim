---@alias nvimtex.compile.CompilerName "pdflatex"|"xelatex"|"lualatex"

---@class nvimtex.compile.LatexmkConfig
---@field executable string
---@field args string[] Arguments passed to latexmk.
---@field engine? nvimtex.compile.CompilerName Override automatic engine selection.
---@field favor nvimtex.compile.CompilerName[]
---@field detection nvimtex.compile.EngineDetection
---@field quickfix false|nvimtex.compile.QuickfixConfig

---@class nvimtex.compile.QuickfixConfig
---@field open boolean Open a nonempty quickfix list without moving focus.
---@field ignore string[] Vim regular expressions matched against messages.

---@class nvimtex.compile.EngineDetection
---@field documentclasses table<string, nvimtex.compile.CompilerSet>
---@field documentclass_prefixes { prefix: string, engines: nvimtex.compile.CompilerSet }[]
---@field compiler_magic_keys string[]
---@field packages { name: string, engines: nvimtex.compile.CompilerSet }[]

---@class nvimtex.compile.CompilerSet
---@field pdflatex? boolean
---@field xelatex? boolean
---@field lualatex? boolean

---@class nvimtex.compile.Options
---@field path? string Exact TeX target; otherwise use the current file's main declaration.
---@field source? number|string Source used only for engine detection; compilation reads the saved file.
---@field engine? nvimtex.compile.CompilerName
---@field executable? string
---@field args? string[] Replaces the configured latexmk arguments.
---@field log? string Exact log path for custom output directories/jobnames.
---@field blg? string Exact bibliography log path; defaults to the log basename.

---@class nvimtex.compile.Context
---@field path string
---@field cwd string
---@field engine nvimtex.compile.CompilerName
---@field command string
---@field args string[]

local util = require("nvimtex.util")
local compile_util = require("nvimtex.compile.util")
local engine_flags = { pdflatex = "-pdf", xelatex = "-xelatex", lualatex = "-lualatex" }
local all_compiler_set = {}
for name in pairs(engine_flags) do
	all_compiler_set[name] = true
end

local M = {
	---@type nvimtex.compile.LatexmkConfig
	config = {
		executable = "latexmk",
		args = { "-interaction=nonstopmode", "-halt-on-error", "-file-line-error", "-synctex=1" },
		favor = { "pdflatex", "xelatex", "lualatex" },
		quickfix = { open = true, ignore = {} },
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
		},
	},
}

---@param left nvimtex.compile.CompilerSet
---@param right nvimtex.compile.CompilerSet
---@return nvimtex.compile.CompilerSet
local function intersect_compiler_sets(left, right)
	local result = {}
	for name in pairs(engine_flags) do
		result[name] = left[name] and right[name] or nil
	end
	return result
end

---Merge user options into the latexmk configuration.
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
---@param source number|string
---@return nvimtex.compile.CompilerName?
function M.get_compiler(source)
	local magic_comment = M.get_compiler_by_magic_comment(source)
	if magic_comment then
		return next(magic_comment)
	end
	local packages = M.get_compiler_by_packages(source)
	local documentclass = M.get_compiler_by_documentclass(source)
	local res = intersect_compiler_sets(packages, documentclass)
	for _, program in ipairs(M.config.favor) do
		if res[program] then
			return program
		end
	end
end

---Build a single latexmk invocation; latexmk owns all reruns and bibliography jobs.
---@param opts? nvimtex.compile.Options
---@return nvimtex.compile.Context
function M.compile_context(opts)
	opts = opts or {}
	local path = opts.path or util.main_file()
	if path == "" then
		error("Save the TeX buffer before compiling.")
	end
	path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
	local source = opts.source
	if source == nil then
		local buffer = vim.fn.bufnr(path)
		source = buffer ~= -1 and vim.api.nvim_buf_is_loaded(buffer) and buffer
			or table.concat(vim.fn.readfile(path), "\n")
	end
	local engine = opts.engine or M.config.engine or M.get_compiler(source)
	local flag = engine and engine_flags[engine]
	if not flag then
		error("Cannot select a LaTeX engine; set compile.engine to pdflatex, xelatex or lualatex.")
	end
	local args = { flag }
	vim.list_extend(args, opts.args or M.config.args)
	args[#args + 1] = path
	return {
		path = path,
		cwd = vim.fn.fnamemodify(path, ":h"),
		engine = engine,
		command = opts.executable or M.config.executable,
		args = args,
	}
end

---Compile with latexmk using its native output paths and project configuration.
---@param opts? nvimtex.compile.Options
function M.compile(opts)
	opts = opts or {}
	local ctx = M.compile_context(opts)
	compile_util.run_job(ctx.command, ctx.cwd, ctx.args, function(_, stat)
		vim.notify(
			string.format("nvimtex compile succeeded\n%s (%s): %.2fs", ctx.command, ctx.engine, stat.elapsed_ms / 1000),
			vim.log.levels.INFO
		)
	end, function(_, stat)
		return require("nvimtex.compile.quickfix").update(ctx.path, stat.code, M.config.quickfix, opts)
	end)
end

return M
