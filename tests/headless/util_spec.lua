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

local Inline = require("nvimtex.conceal.inline")
local inline = Inline:new("a")
inline:append({ { "bc", "Normal" } })
eq(inline.width, 3, "inline raw data width")
eq(inline:atom(2), { "bc", "Normal" }, "inline raw data append")
print("ok inline append raw data")

local State = require("nvimtex.conceal.state")
local state = State:new({ false_value = false })
state:addUndoPoint()
state:set("false_value", true)
state:set("false_value", "changed again")
state:set("nil_value", true)
state:set("nil_value", "changed again")
state:undo()
eq(state:get("false_value"), false, "state restores false")
eq(state:get("nil_value"), nil, "state restores nil")
print("ok state restores false and nil")
print("")
