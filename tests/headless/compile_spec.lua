vim.opt.runtimepath:prepend(vim.fn.getcwd())

local latexmk = require("nvimtex.compile.latexmk")
local compile = require("nvimtex.compile")
local compile_util = require("nvimtex.compile.util")
local root = vim.fn.tempname() .. " compile tests"
vim.fn.mkdir(root, "p")
local calls, notifications, errors = {}, {}, {}
local exit_code = 0
vim.notify = function(message)
	notifications[#notifications + 1] = message
end
compile_util.showbelow = function(lines)
	errors[#errors + 1] = lines
end

package.preload["plenary.job"] = function()
	return {
		new = function(_, spec)
			return {
				start = function()
					calls[#calls + 1] = spec
					spec.on_exit({
						result = function()
							return { "latexmk output" }
						end,
					}, exit_code)
				end,
			}
		end,
	}
end

local function eq(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end

local path = root .. "/a document.tex"
vim.fn.writefile({ "% !TeX program = xelatex", "\\documentclass{article}" }, path)
latexmk.setup({ build_root = root .. "/build", args = { "-synctex=1" } })
local ctx = latexmk.compile_context({ path = path })
eq(ctx.engine, "xelatex", "opts.path determines engine even when another buffer is current")
eq(ctx.command, "latexmk", "default executable")
eq(ctx.cwd, root, "source working directory")
eq(ctx.jobname, "a document", "source jobname")
eq(ctx.args, { "-xelatex", "-synctex=1", "-outdir=" .. ctx.build_dir, path }, "arguments preserve spaces")

-- A loaded target buffer is parsed without depending on a running highlighter.
local buf = vim.fn.bufadd(path)
vim.fn.bufload(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\\documentclass{article}", "\\usepackage{luacode}" })
eq(latexmk.compile_context({ path = path }).engine, "lualatex", "loaded target source")
local explicit = latexmk.compile_context({
	path = path,
	engine = "pdflatex",
	executable = "my-latexmk",
	args = { "-r", root .. "/custom rules.rc" },
})
eq(explicit.args[1], "-pdf", "explicit engine overrides source hints")
eq(explicit.command, "my-latexmk", "custom executable")
eq(explicit.args[2], "-r", "latexmk rc argument")
eq(explicit.args[3], root .. "/custom rules.rc", "rc path preserves spaces")
eq(latexmk.config.args, { "-synctex=1" }, "building arguments does not mutate config")

-- Only successful latexmk builds publish results. A failed build may leave
-- partial artifacts in its build directory, but must preserve the previous PDF.
vim.fn.writefile({ "new PDF" }, ctx.build_dir .. "/a document.pdf")
vim.fn.writefile({ "new SyncTeX" }, ctx.build_dir .. "/a document.synctex.gz")
compile({ path = path })
assert(
	vim.wait(1000, function()
		return #notifications == 1
	end),
	"success callback"
)
eq(#calls, 1, "one latexmk invocation")
eq(vim.fn.readfile(root .. "/a document.pdf"), { "new PDF" }, "published PDF")
eq(vim.fn.readfile(root .. "/a document.synctex.gz"), { "new SyncTeX" }, "published SyncTeX")
assert(notifications[1]:find("latexmk (lualatex)", 1, true), "summary identifies latexmk and engine")

exit_code = 12
vim.fn.writefile({ "partial PDF" }, ctx.build_dir .. "/a document.pdf")
compile.default({ path = path })
assert(
	vim.wait(1000, function()
		return #errors == 1
	end),
	"failure callback"
)
eq(#notifications, 1, "failed build has no success notification")
eq(vim.fn.readfile(root .. "/a document.pdf"), { "new PDF" }, "failed build preserves published PDF")
eq(errors[1], { "latexmk output" }, "failure shows latexmk output")

exit_code = 0
compile.default({ path = root .. "/missing-output.tex", source = "\\documentclass{article}" })
assert(
	vim.wait(1000, function()
		return #notifications == 2
	end),
	"missing PDF callback"
)
assert(notifications[2]:find("without the expected PDF", 1, true), "missing PDF must not report success")

-- The public log entry point uses the same build root and canonical file path.
local shown
compile_util.showlog = function(log_path, opts)
	shown = { log_path, opts.build_root }
end
compile.showlog(path)
eq(shown, { path, root .. "/build" }, "public log entry point")

local util = require("nvimtex.util")
local main = root .. "/main document.tex"
vim.fn.writefile({ "% !TeX program = xelatex", "\\documentclass{article}" }, main)
vim.fn.mkdir(root .. "/chapters", "p")
local chapter = root .. "/chapters/chapter.tex"
local chapter_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(chapter_buf, chapter)
vim.api.nvim_set_current_buf(chapter_buf)
local function source(text)
	vim.api.nvim_buf_set_lines(chapter_buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
end
source("% !TeX root = ../main document.tex\n\\documentclass[missing.tex]{subfiles}")
eq(util.main_file(), main, "root comment precedes subfiles")
local project = latexmk.compile_context()
eq(project.path, main, "default compile follows root declaration")
eq(project.engine, "xelatex", "engine comes from main document")
eq(project.build_dir, latexmk.compile_context({ path = main }).build_dir, "main and child share build directory")
compile.showlog()
eq(shown[1], main, "default log follows main document")

source("\\documentclass[../main document.tex]{subfiles}")
eq(util.main_file(), main, "subfiles relative main path")
source("% !TeX root = " .. main .. "\n\\documentclass{article}")
eq(util.main_file(), main, "absolute main path")
source("\\documentclass{article}\n\\begin{document}child\\end{document}")
eq(util.main_file(), chapter, "no declaration uses current file")

for _, text in ipairs({
	"% !TeX root = ../missing.tex\n\\documentclass{article}",
	"% !TeX root = \n\\documentclass{article}",
	"\\documentclass[../missing.tex]{subfiles}",
	"\\documentclass[]{subfiles}",
}) do
	source(text)
	local ok = pcall(util.main_file)
	eq(ok, false, "invalid declaration must fail")
	eq(latexmk.compile_context({ path = main }).path, main, "explicit path bypasses current declaration")
end

-- A declaration selects exactly one target; the target is not recursively
-- followed, so self declarations and links back to a child cannot loop.
vim.fn.writefile({ "% !TeX root = chapters/chapter.tex", "\\documentclass{article}" }, main)
source("% !TeX root = ../main document.tex")
eq(latexmk.compile_context().path, main, "declared target is not recursively redirected")
print("ok latexmk argument, source, publication and failure handling")
