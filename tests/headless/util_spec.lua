vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("nvimtex.util")

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local old_get_string_parser = vim.treesitter.get_string_parser
vim.treesitter.get_string_parser = function()
	error("no latex parser")
end

local packages = util.get_packages([[
\documentclass{article}
\usepackage[backend=bibtex,sortcites]{biblatex}
\usepackage{fontspec, luacode}
]])

vim.treesitter.get_string_parser = old_get_string_parser

eq(packages.biblatex.name, "biblatex", "fallback biblatex name")
eq(packages.biblatex.opts.backend, "bibtex", "fallback option value")
eq(packages.biblatex.opts.sortcites, true, "fallback bare option")
eq(packages.fontspec.name, "fontspec", "fallback first package")
eq(packages.luacode.name, "luacode", "fallback second package")
print("ok util get_packages text fallback")
print("")
