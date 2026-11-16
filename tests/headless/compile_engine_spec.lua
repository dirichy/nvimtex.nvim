vim.opt.runtimepath:prepend(vim.fn.getcwd())

local latexmk = require("nvimtex.compile.latexmk")

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
	return latexmk.compile_context(vim.tbl_deep_extend("force", {
		source = source,
		path = tmp_root .. "/" .. name .. ".tex",
	}, opts))
end

local function compiler(source, expected, label)
	eq(context(source, label).engine, expected, label)
	print("ok engine " .. label)
end

local function with_config(config, fn)
	local old_config = vim.deepcopy(latexmk.config)
	latexmk.setup(config)
	local ok, err = pcall(fn)
	latexmk.config = old_config
	if not ok then
		error(err)
	end
end

latexmk.setup({
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

latexmk.setup({ favor = { "lualatex", "xelatex", "pdflatex" } })
compiler("\\documentclass{article}", "lualatex", "favor_order")
latexmk.setup({ favor = { "pdflatex", "xelatex", "lualatex" } })

with_config({
	detection = {
		documentclasses = {
			custompaper = { lualatex = true },
		},
	},
}, function()
	local custom_class = context("\\documentclass{custompaper}", "custom_class").engine
	eq(custom_class, "lualatex", "custom documentclass compiler")
	print("ok engine custom documentclass detection")
end)

with_config({
	detection = {
		packages = {
			{ name = "onlypdftex", engines = { pdflatex = true } },
		},
	},
}, function()
	local custom_package = context("\\documentclass{article}\n\\usepackage{onlypdftex}", "custom_package").engine
	eq(custom_package, "pdflatex", "custom package compiler")
	print("ok engine custom package detection")
end)
