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
latexmk.setup({ args = { "-synctex=1" } })
local ctx = latexmk.compile_context({ path = path })
eq(ctx.engine, "xelatex", "opts.path determines engine even when another buffer is current")
eq(ctx.command, "latexmk", "default executable")
eq(ctx.cwd, root, "source working directory")
eq(ctx.args, { "-xelatex", "-synctex=1", path }, "arguments preserve spaces")

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

-- The adapter reports the exit status without assuming output paths or copying
-- artifacts: latexmk may use a custom jobname or output format in its rc file.
compile({ path = path })
assert(
	vim.wait(1000, function()
		return #notifications == 1
	end),
	"success callback"
)
eq(#calls, 1, "one latexmk invocation")
assert(notifications[1]:find("latexmk (lualatex)", 1, true), "summary identifies latexmk and engine")
exit_code = 12
compile.default({ path = path })
assert(
	vim.wait(1000, function()
		return #errors == 1
	end),
	"failure callback"
)
eq(#notifications, 1, "failed build has no success notification")
eq(errors[1], { "latexmk output" }, "failure shows latexmk output")

-- Automatic quickfix handles parsed failures and keeps raw output as a fallback.
local logfile = root .. "/renamed.log"
vim.fn.writefile({ "**a document.tex", "./a document.tex:2: Undefined control sequence.", "l.2 \\bad" }, logfile)
local qf_before = vim.fn.getqflist({ changedtick = 1 }).changedtick
compile.default({ path = path, log = "renamed.log" })
assert(
	vim.wait(1000, function()
		return vim.fn.getqflist({ changedtick = 1 }).changedtick ~= qf_before
	end),
	"automatic quickfix callback"
)
eq(#errors, 1, "parsed failure replaces raw output")
eq(vim.fn.getqflist()[1].lnum, 2, "automatic quickfix error line")
latexmk.setup({ quickfix = false })
compile.default({ path = path, log = logfile })
assert(
	vim.wait(1000, function()
		return #errors == 2
	end),
	"disabled quickfix callback"
)
eq(#errors, 2, "disabled quickfix keeps raw output")
latexmk.setup({ quickfix = { open = false, ignore = {} } })
vim.fn.writefile({ "Output written on renamed.pdf" }, logfile)
compile.default({ path = path, log = logfile })
assert(
	vim.wait(1000, function()
		return #errors == 3
	end),
	"unparsed failure callback"
)
eq(#errors, 3, "failure without parsed errors keeps raw output")
eq(vim.fn.getqflist(), {}, "rebuild clears previous parsed error")
vim.fn.delete(logfile)

-- arara uses the same completion path, including shared settings and log overrides.
vim.api.nvim_set_current_buf(buf)
vim.fn.writefile({ "./a document.tex:2: Undefined control sequence." }, logfile)
exit_code = 1
qf_before = vim.fn.getqflist({ changedtick = 1 }).changedtick
compile.arara({ log = "renamed.log" })
assert(
	vim.wait(1000, function()
		return vim.fn.getqflist({ changedtick = 1 }).changedtick ~= qf_before
	end),
	"arara quickfix callback"
)
eq(calls[#calls].command, "arara", "arara executable")
eq(calls[#calls].log, nil, "log option is not passed to plenary")
eq(vim.fn.getqflist()[1].lnum, 2, "arara shares error parsing")
eq(#errors, 3, "parsed arara failure replaces raw output")

exit_code = 0
vim.fn.writefile({ "Output written on renamed.pdf" }, logfile)
local notice_count = #notifications
compile.arara({ log = logfile })
assert(
	vim.wait(1000, function()
		return #notifications > notice_count
	end),
	"arara success callback"
)
eq(vim.fn.getqflist(), {}, "arara success clears stale errors")

exit_code = 1
latexmk.setup({ quickfix = false })
compile.arara({ log = logfile })
assert(
	vim.wait(1000, function()
		return #errors == 4
	end),
	"arara disabled quickfix callback"
)
latexmk.setup({ quickfix = { open = false, ignore = {} } })
vim.fn.delete(logfile)
exit_code = 2
compile.arara()
assert(
	vim.wait(1000, function()
		return #errors == 5
	end),
	"arara raw-output fallback without a log"
)

local custom_exit
compile.arara({
	on_exit = function(_, code)
		custom_exit = code
	end,
})
eq(custom_exit, 2, "arara preserves custom job callbacks")

local custom = latexmk.compile_context({ path = path, args = { "-outdir=build", "-auxdir=aux", "-jobname=custom" } })
eq(
	custom.args,
	{ "-lualatex", "-outdir=build", "-auxdir=aux", "-jobname=custom", path },
	"user output options are passed without overrides"
)

local shown
local systemlist = vim.fn.systemlist
vim.fn.systemlist = function(argv)
	shown = argv
	return { "filtered log" }
end
compile.showlog(path)
eq(shown, { "texlogsieve", root .. "/a document.log", "--color" }, "default sibling log")
compile.showlog(root .. "/custom output/renamed.log")
eq(shown, { "texlogsieve", root .. "/custom output/renamed.log", "--color" }, "custom log path")
vim.fn.systemlist = systemlist
compile_util.showlog = function(log_path)
	shown = log_path
end
compile.showlog(path)
eq(shown, path, "public log entry point")
compile.showlog(root .. "/custom output/custom.log")
eq(shown, root .. "/custom output/custom.log", "explicit log entry point")

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
compile.showlog()
eq(shown, main, "default log follows main document")

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
print("ok latexmk argument, source, output options and failure handling")
