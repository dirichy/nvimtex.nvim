vim.opt.runtimepath:prepend(vim.fn.getcwd())

local util = require("nvimtex.util")

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

for _, case in ipairs({
	{ "", "" },
	{ "plain text", "plain text" },
	{ "% comment", "" },
	{ [[text \% literal % comment]], [[text \% literal ]] },
	{ [[text \\% comment]], [[text \\]] },
	{ [[text \\\% literal % comment]], [[text \\\% literal ]] },
	{ [[text \\\\% comment]], [[text \\\\]] },
}) do
	eq(util.strip_comment(case[1]), case[2], "TeX comment escape parity")
end
eq(
	util.normalize_file("./chapters/../main", { cwd = "/tmp/project with spaces", extension = "tex" }),
	"/tmp/project with spaces/main.tex",
	"relative path normalization and extension"
)
eq(
	util.normalize_file("/tmp/./main.tex", { cwd = "/another/project" }),
	"/tmp/main.tex",
	"absolute path is not prefixed"
)
eq(
	util.normalize_file("C:/project/main.tex", { cwd = "/another/project" }),
	"C:/project/main.tex",
	"Windows drive path is not prefixed"
)

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

local header = [[% !TeX program = lualatex
% !TeX root = ../Main File.tex
% \documentclass{wrong}
\documentclass
  [../Main File.tex]
  {subfiles}
\usepackage % split command
  [backend=bibtex,sortcites]
  {biblatex, fontspec}
\RequirePackage{luacode}
\newcommand{\percent}{\%} \usepackage{amsmath} % \usepackage{wrong}
\begin{document}
\usepackage{ignored-body-package}
]]
local expected_class = { name = "subfiles", opts = { ["../Main File.tex"] = true } }
eq(util.get_documentclass(header), expected_class, "multiline class and path")
local text_packages = util.get_packages(header)
eq(text_packages.biblatex.opts.backend, "bibtex", "multiline package options")
eq(text_packages.biblatex.opts.sortcites, true, "multiline bare option")
eq(text_packages.luacode.name, "luacode", "RequirePackage")
eq(text_packages.amsmath.name, "amsmath", "escaped percent is not a comment")
eq(text_packages.wrong, nil, "commented package ignored")
eq(text_packages["ignored-body-package"], nil, "reader stops before document body")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
local lines = vim.split(header, "\n", { plain = true })
for _ = 1, 100000 do
	lines[#lines + 1] = "Ordinary body text."
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
local old_get_parser = vim.treesitter.get_parser
local old_lines = vim.api.nvim_buf_get_lines
local fetched = 0
vim.treesitter.get_parser = function()
	error("disabled Tree-sitter must not be started")
end
vim.treesitter.get_string_parser = function()
	error("text helpers must not create string parsers")
end
vim.api.nvim_buf_get_lines = function(buffer, first, last, strict)
	assert(last >= 0 and last - first <= 64, "header reader fetched the whole document")
	local result = old_lines(buffer, first, last, strict)
	fetched = fetched + #result
	return result
end
eq(util.get_magic_comment(buf).root, "../Main File.tex", "buffer magic comment without parser")
eq(util.get_documentclass(buf), expected_class, "buffer class without parser")
eq(util.get_packages(buf), text_packages, "buffer packages without parser")
assert(fetched <= 192, "large body must not be scanned")
vim.api.nvim_buf_get_lines = old_lines
vim.treesitter.get_parser = old_get_parser
vim.treesitter.get_string_parser = old_get_string_parser

-- Prefer a valid, active tree, but never synchronously reparse a stale one.
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"\\documentclass{article}",
	"\\usepackage{fontspec}",
	"\\begin{document}",
	"text",
	"\\end{document}",
})
vim.treesitter.start(buf, "latex")
vim.treesitter.get_parser(buf, "latex"):parse()
local original_text = vim.treesitter.get_node_text
local node_reads = 0
vim.treesitter.get_node_text = function(...)
	node_reads = node_reads + 1
	return original_text(...)
end
eq(util.get_documentclass(buf).name, "article", "active tree class")
eq(util.get_packages(buf).fontspec.name, "fontspec", "active tree packages")
assert(node_reads > 0, "valid active tree should be preferred")
vim.treesitter.get_node_text = original_text
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "\\documentclass{book}" })
eq(util.get_documentclass(buf).name, "book", "stale tree falls back to current text")
vim.treesitter.stop(buf)
eq(util.get_documentclass(buf).name, "book", "stopped highlighter falls back to text")
vim.api.nvim_buf_delete(buf, { force = true })
print("ok header helpers without Tree-sitter, bounded reads and active-tree reuse")

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
