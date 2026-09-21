vim.opt.runtimepath:prepend(vim.fn.getcwd())

local smart = require("nvimtex.compile.smart")

local tmp_root = "/tmp/nvimtex.nvim-smart-tests"
vim.fn.delete(tmp_root, "rf")
vim.fn.mkdir(tmp_root, "p")

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function context(source, name, opts)
	opts = opts or {}
	return smart.compile_context(vim.tbl_deep_extend("force", {
		source = source,
		path = tmp_root .. "/" .. name .. ".tex",
	}, opts))
end

local function compiler(source, expected, label)
	eq(context(source, label).command, expected, label)
	print("ok smart compiler " .. label)
end

local function with_config(config, fn)
	local old_config = vim.deepcopy(smart.config)
	smart.setup(config)
	local ok, err = pcall(fn)
	smart.config = old_config
	if not ok then
		error(err)
	end
end

smart.setup({
	favor = { "pdflatex", "xelatex", "lualatex" },
	build_root = tmp_root .. "/configured-build",
})

compiler("% !TeX TS-program = xelatex\n\\documentclass{article}", "xelatex", "magic_ts_program")
compiler("% !TeX program = lualatex\n\\documentclass{article}", "lualatex", "magic_program")
compiler(
	"% !TeX program = pdflatex\n\\documentclass{article}\n\\usepackage{fontspec}",
	"pdflatex",
	"magic_overrides_package"
)
compiler("\\documentclass{ctexart}", "xelatex", "ctex_documentclass")
compiler("\\documentclass{luapaper}", "lualatex", "lua_documentclass_prefix")
compiler("\\documentclass{article}\n\\usepackage{xeCJK}", "xelatex", "xecjk_package")
compiler("\\documentclass{article}\n\\usepackage{fontspec}", "xelatex", "fontspec_package")
compiler("\\documentclass{article}\n\\usepackage{unicode-math}", "xelatex", "unicode_math_package")
compiler("\\documentclass{article}\n\\usepackage{ctex}", "xelatex", "ctex_package")
compiler("\\documentclass{article}\n\\usepackage{luacode}", "lualatex", "luacode_package")
compiler("\\documentclass{article}\n\\usepackage{fontspec}\n\\usepackage{luacode}", "lualatex", "package_intersection")
compiler("\\documentclass{article}\n\\usepackage{luatexja}", "lualatex", "luatexja_package")
compiler("\\documentclass{article}\n\\usepackage{luadraw}", "lualatex", "luadraw_package")
compiler("\\documentclass{article}\n\\usepackage{CJK}", "pdflatex", "cjk_package")
compiler("\\documentclass{article}", "pdflatex", "default_favor")

smart.setup({ favor = { "lualatex", "xelatex", "pdflatex" } })
compiler("\\documentclass{article}", "lualatex", "favor_order")
smart.setup({ favor = { "pdflatex", "xelatex", "lualatex" } })

local build_ctx = context("\\documentclass{article}", "build_path")
eq(
	build_ctx.build_dir,
	vim.fs.normalize((tmp_root .. "/configured-build") .. "/" .. vim.fn.sha256(build_ctx.path)),
	"configured build_root"
)
eq(
	build_ctx.compile_args[#build_ctx.compile_args - 1],
	"-output-directory=" .. build_ctx.build_dir,
	"output directory arg"
)
eq(build_ctx.compile_args[#build_ctx.compile_args], "build_path", "jobname arg")
print("ok smart compile_context paths")

local custom_args = context("\\documentclass{article}", "custom_args", {
	command = "xelatex",
	compile_args = { "-halt-on-error" },
})
eq(custom_args.command, "xelatex", "explicit command")
eq(custom_args.compile_args[1], "-halt-on-error", "custom compile arg")
eq(custom_args.compile_args[2], "-output-directory=" .. custom_args.build_dir, "custom output directory arg")
eq(custom_args.compile_args[3], "custom_args", "custom jobname arg")
print("ok smart compile_context overrides")

local function bibliography(source, name)
	return context(source, name, { command = "pdflatex" }).bibliography
end

local bib_magic = bibliography("% !TeX bib-program = biber\n\\documentclass{article}", "bib_magic")
eq(bib_magic.backend, "biber", "bib-program magic")
print("ok smart bib magic")

local bib_magic_alias =
	bibliography("% !TeX bibliography-program = bibtex8\n\\documentclass{article}", "bib_magic_alias")
eq(bib_magic_alias.backend, "bibtex", "bibliography-program magic alias")
print("ok smart bib magic alias")

local bibtex_program_alias =
	bibliography("% !TeX bibtex-program = upbibtex\n\\documentclass{article}", "bibtex_program_alias")
eq(bibtex_program_alias.backend, "bibtex", "bibtex-program magic alias")
print("ok smart bibtex-program magic alias")

local bib_engine_alias = bibliography("% !TeX bib-engine = pbibtex\n\\documentclass{article}", "bib_engine_alias")
eq(bib_engine_alias.backend, "bibtex", "bib-engine magic alias")
print("ok smart bib-engine magic alias")

local magic_with_files =
	bibliography("% !TeX bib-program = biber\n\\documentclass{article}\n\\bibliography{refs}", "magic_with_files")
eq(magic_with_files.backend, "biber", "magic keeps backend")
eq(magic_with_files.files[1], tmp_root .. "/refs.bib", "magic still scans bibliography files")
print("ok smart bib magic with files")

local biblatex_default = bibliography("\\documentclass{article}\n\\usepackage{biblatex}", "biblatex_default")
eq(biblatex_default.backend, "biber", "biblatex default")
print("ok smart biblatex default")

local biblatex_bibtex =
	bibliography("\\documentclass{article}\n\\usepackage[backend=bibtex]{biblatex}", "biblatex_bibtex")
eq(biblatex_bibtex.backend, "bibtex", "biblatex backend option")
print("ok smart biblatex backend option")

for _, package in ipairs({ "natbib", "cite", "chapterbib", "multibib" }) do
	local bib = bibliography("\\documentclass{article}\n\\usepackage{" .. package .. "}", "package_" .. package)
	eq(bib.backend, "bibtex", package .. " package")
	print("ok smart bib package " .. package)
end

local addbib = bibliography("\\documentclass{article}\n\\addbibresource[location=local]{refs}", "addbib")
eq(addbib.backend, "biber", "addbibresource command")
eq(addbib.files[1], tmp_root .. "/refs.bib", "addbibresource file")
print("ok smart addbibresource")

local bibcmd = bibliography("\\documentclass{article}\n\\bibliographystyle{plain}\n\\bibliography{refs,more}", "bibcmd")
eq(bibcmd.backend, "bibtex", "bibliography command")
eq(bibcmd.files[1], tmp_root .. "/refs.bib", "bibliography first file")
eq(bibcmd.files[2], tmp_root .. "/more.bib", "bibliography second file")
print("ok smart bibliography command")

local bibstyle = bibliography("\\documentclass{article}\n\\bibliographystyle{plain}", "bibstyle")
eq(bibstyle.backend, nil, "bibliographystyle alone")
print("ok smart bibliographystyle alone is not decisive")

local old_get_string_parser = vim.treesitter.get_string_parser
vim.treesitter.get_string_parser = function()
	error("no latex parser")
end
local fallback_bibcmd = bibliography("\\documentclass{article}\n\\bibliography{refs}", "fallback_bibcmd")
vim.treesitter.get_string_parser = old_get_string_parser
eq(fallback_bibcmd.backend, "bibtex", "bibliography text fallback")
eq(fallback_bibcmd.files[1], tmp_root .. "/refs.bib", "bibliography fallback file")
print("ok smart bibliography command text fallback")

local printbib = bibliography("\\documentclass{article}\n\\printbibliography", "printbib")
eq(printbib.backend, "biber", "printbibliography command")
print("ok smart printbibliography")

with_config({
	detection = {
		documentclasses = {
			custompaper = { lualatex = true },
		},
	},
}, function()
	local custom_class = context("\\documentclass{custompaper}", "custom_class").command
	eq(custom_class, "lualatex", "custom documentclass compiler")
	print("ok smart custom documentclass detection")
end)

with_config({
	detection = {
		packages = {
			{ name = "onlypdftex", engines = { pdflatex = true } },
		},
	},
}, function()
	local custom_package = context("\\documentclass{article}\n\\usepackage{onlypdftex}", "custom_package").command
	eq(custom_package, "pdflatex", "custom package compiler")
	print("ok smart custom package detection")
end)

with_config({
	detection = {
		bib_magic_keys = { "bibliography-backend" },
	},
}, function()
	local custom_bib_magic =
		bibliography("% !TeX bibliography-backend = biber\n\\documentclass{article}", "custom_bib_magic")
	eq(custom_bib_magic.backend, "biber", "custom bib magic key")
	print("ok smart custom bib magic detection")
end)

with_config({
	detection = {
		bib_commands = {
			usesbib = { backend = "bibtex", files = "single" },
		},
	},
}, function()
	local custom_bib_command = bibliography("\\documentclass{article}\n\\usesbib{refs}", "custom_bib_command")
	eq(custom_bib_command.backend, "bibtex", "custom bib command")
	eq(custom_bib_command.files[1], tmp_root .. "/refs.bib", "custom bib command file")
	print("ok smart custom bib command detection")
end)
print("")
