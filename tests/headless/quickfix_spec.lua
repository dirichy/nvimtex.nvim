vim.opt.runtimepath:prepend(vim.fn.getcwd())
local repo = vim.fn.getcwd()
local quickfix = require("nvimtex.compile.quickfix")
local root = repo .. "/tests/fixtures/quickfix/vimtex"
local function eq(actual, expected, label)
	assert(
		vim.deep_equal(actual, expected),
		label .. "\n" .. vim.inspect(actual) .. "\nexpected\n" .. vim.inspect(expected)
	)
end

-- Frozen VimTeX outputs include filenames in addition to the upstream assertions.
local before_cwd, before_efm = vim.fn.getcwd(), vim.bo.errorformat
vim.fn.setqflist({}, " ", { title = "unrelated", items = { { text = "keep me" } } })
local before_qf = vim.fn.getqflist({ all = 1 })
for _, case in ipairs({
	{ "example-quickfix", "main" },
	{ "test-quickfix", "file with errors" },
	{ "test-quickfix-fix-path", "test-beamer" },
	{ "test-quickfix-fix-path", "test-hbox" },
}) do
	local base = root .. "/" .. case[1] .. "/" .. case[2]
	local items = quickfix.read({ path = base .. ".tex" })
	local actual = {}
	for _, item in ipairs(items) do
		local file = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
		actual[#actual + 1] = {
			file = vim.fs.relpath(root, vim.fn.fnamemodify(file, ":p")),
			lnum = item.lnum,
			type = item.type,
			text = item.text,
		}
	end
	local expected = vim.json.decode(table.concat(vim.fn.readfile(base .. ".json"), "\n"))
	eq(actual, expected, case[2] .. " matches VimTeX")
end
eq(vim.fn.getcwd(), before_cwd, "parsing preserves cwd")
eq(vim.bo.errorformat, before_efm, "parsing preserves errorformat")
eq(vim.fn.getqflist({ all = 1 }), before_qf, "parsing preserves quickfix")

-- Logs produced by real BibTeX/Biber, including Biber's decoded temporary file.
for _, backend in ipairs({ "bibtex", "biber" }) do
	local dir = repo .. "/tests/fixtures/quickfix/" .. backend .. "-error"
	local parsed = quickfix.read({ path = dir .. "/main.tex" })
	eq(parsed[1].type, "E", backend .. " real syntax error")
	eq(parsed[1].lnum, 3, backend .. " real syntax line")
	local file = parsed[1].filename or vim.api.nvim_buf_get_name(parsed[1].bufnr)
	eq(file, dir .. "/refs.bib", backend .. " real bibliography file")
end

local path = root .. "/test-quickfix/file with errors.tex"
local opts = { path = path, open = false }
local items = quickfix.show(opts)
local list = vim.fn.getqflist({ id = 0, nr = "$" })
quickfix.show(opts)
eq(vim.fn.getqflist({ id = 0, nr = "$" }), list, "refresh reuses owned list")
eq(vim.fn.getqflist({ nr = list.nr - 1, title = 1 }).title, "unrelated", "keeps unrelated list in history")
opts.ignore = { [[\\test]] }
eq(#quickfix.show(opts), #items - 1, "Vim regex ignore filter")
opts.ignore = nil
local window = vim.api.nvim_get_current_win()
opts.open = true
quickfix.show(opts)
eq(vim.api.nvim_get_current_win(), window, "opening quickfix preserves focus")

local temp = vim.fn.tempname() .. " quickfix"
vim.fn.mkdir(temp .. "/output", "p")
local main = temp .. "/main.tex"
local log = temp .. "/output/result.log"
local blg = temp .. "/output/result.blg"
local bib = temp .. "/refs.bib"
vim.fn.writefile({ "\\documentclass{article}", "\\addbibresource{refs.bib}", "\\bibliography{refs}" }, main)
vim.fn.writefile({ "@article{first,", " title={One}", "}", "@article{second,", " title={Two}", "}" }, bib)
vim.fn.writefile({ "**main.tex", "./main.tex:3: Undefined control sequence.", "l.3 \\bad" }, log)
vim.fn.writefile({
	"Database file #1: refs.bib",
	"Warning--empty author in second",
	'Warning--entry type for "first" isn\'t style-file defined',
}, blg)
local parsed = quickfix.read({ path = main, log = "output/result.log" })
eq(#parsed, 3, "custom log basename locates bibliography log")
eq(parsed[2].text, 'Missing "author" in "second"', "BibTeX warning text")
eq(parsed[2].filename, bib, "BibTeX entry file")
eq(parsed[2].lnum, 4, "BibTeX entry line")
eq(parsed[3].lnum, 1, "BibTeX unknown entry type")
vim.fn.writefile({
	"[0] INFO - This is Biber 2.21",
	"[1] INFO - Found BibTeX data source 'refs.bib'",
	"[2] WARN - Duplicate entry key: 'second' in file 'refs.bib', skipping ...",
	"[3] WARN - The entry 'first' has characters which cannot be encoded in ascii",
}, blg)
parsed = quickfix.read({ path = main, log = log })
eq(#parsed, 3, "Biber warnings")
eq(parsed[2].text, 'biblatex: Duplicate entry key "second"', "Biber duplicate text")
eq(parsed[2].lnum, 4, "Biber duplicate line")
eq(parsed[3].lnum, 1, "Biber encoding line")
vim.fn.writefile({
	"[0] INFO - This is Biber 2.21",
	"[1] ERROR - BibTeX subsystem: refs.bib, line 2, syntax error: expected end of entry (skipping)",
}, blg)
parsed = quickfix.read({ path = main, log = log })
eq(parsed[2].filename, bib, "Biber failure before source announcement")
eq(parsed[2].lnum, 2, "Biber syntax line")
eq(parsed[2].text, 'biblatex: Error parsing entry with key "first"', "Biber syntax entry")

-- Resource/style lookup shares the header reader's escaped-percent handling.
vim.fn.writefile({
	"\\documentclass{article}",
	"% \\addbibresource{ignored.bib}",
	"\\newcommand{\\percent}{\\%} \\addbibresource{refs.bib} % \\addbibresource{ignored.bib}",
}, main)
vim.fn.writefile({
	"[0] INFO - This is Biber 2.21",
	"[1] WARN - The entry 'first' has characters which cannot be encoded in ascii",
}, blg)
parsed = quickfix.read({ path = main, log = log })
eq(parsed[2].filename, bib, "resource declaration after escaped percent")
eq(parsed[2].lnum, 1, "resource fallback locates bibliography entry")
vim.fn.writefile({
	"\\documentclass{article}",
	"% \\bibliography{ignored}",
	"\\newcommand{\\percent}{\\%} \\bibliography{refs} % trailing comment",
}, main)
vim.fn.writefile({ "I found no \\bibstyle command---while reading file main.aux" }, blg)
parsed = quickfix.read({ path = main, log = log })
eq(parsed[2].filename, main, "missing bibliography style belongs to main file")
eq(parsed[2].lnum, 3, "bibliography declaration after escaped percent")

-- Each box occurrence is located independently, including logs beyond VimTeX's cutoff.
local child = temp .. "/child.tex"
vim.fn.writefile({ "text" }, child)
local long = { "**main.tex", "(./main.tex" }
for _ = 1, 11000 do
	long[#long + 1] = "ordinary log text"
end
vim.list_extend(long, {
	"(./child.tex",
	"Overfull \\hbox (1pt too wide) at line 1",
	")",
	"(./main.tex",
	"Overfull \\hbox (1pt too wide) at line 1",
})
vim.fn.writefile(long, log)
vim.fn.delete(blg)
parsed = quickfix.read({ path = main, log = log })
eq(#parsed, 2, "long log box count")
eq(vim.fn.fnamemodify(parsed[1].filename, ":p"), child, "long log box child")
eq(vim.fn.fnamemodify(parsed[2].filename, ":p"), main, "identical messages in different files")

-- Message-state boundaries: first location wins, package-specific end markers
-- close messages, and unrelated tracing never becomes a source excerpt.
vim.fn.writefile({
	"./main.tex:3: First error",
	"l.4 \\different",
	"./main.tex:5: Second error",
	"<inserted text>",
	"l.6 \\unrelated",
	"LaTeX Font Warning: Font on input line 7.",
	"(Font) More on input line 8.",
	"Package babel Warning: First line",
	"(babel) final on input line 9.",
	"(babel) unrelated",
	"Package other Warning: First line",
	"(other) final on input line 10.",
	"(other) unrelated",
	"Class memoir Warning: First line on input line 11.",
	"(memoir) second line",
	"LaTeX Warning: Last message",
	"(not a continuation",
	"Class Notes.tex:12: Filename starting with a warning prefix",
}, log)
parsed = quickfix.read({ path = main, log = log })
eq(#parsed, 8, "state-boundary message count")
eq(parsed[1].lnum, 3, "explicit error location wins over source excerpt")
eq(parsed[1].text, "First error\n\\different", "adjacent source excerpt")
eq(parsed[2].text, "Second error", "unrelated source excerpt excluded")
eq(parsed[3].lnum, 12, "capitalized filename is still an error")
eq(parsed[4].lnum, 7, "initial warning location wins")
eq(parsed[5].text, "Package babel Warning: First line", "babel terminator is not message text")
eq(parsed[5].lnum, 9, "babel terminator supplies location")
eq(parsed[6].text, "Package other Warning: First line\nfinal", "generic package terminator closes message")
eq(parsed[7].text, "Class memoir Warning: First line on input line 11.\nsecond line", "class continuation")
eq(parsed[8].text, "LaTeX Warning: Last message", "unmatched parenthesis closes message safely")

vim.fn.writefile({
	"Name 1 has a comma at the end for entry first",
	"while executing---line 14 of file refs.bib",
}, blg)
vim.fn.writefile({ "Output written on main.pdf" }, log)
parsed = quickfix.read({ path = main, log = log })
eq(#parsed, 1, "BibTeX continuation supplies a location instead of a second error")
eq(parsed[1].lnum, 14, "BibTeX continuation location")
eq(parsed[1].filename, bib, "BibTeX continuation file")
vim.fn.delete(blg)
vim.fn.writefile({ "./main.tex:1: Previous error" }, log)

quickfix.show({ path = main, log = log })
vim.fn.writefile({ "Output written on main.pdf" }, log)
eq(#quickfix.show({ path = main, log = log }), 0, "successful rebuild clears errors")
eq(vim.fn.getqflist(), {}, "empty list replaces stale errors")
eq(vim.fn.getqflist({ winid = 1 }).winid, 0, "empty owned list closes quickfix")
local ok = pcall(quickfix.read, { path = main, log = "missing.log" })
eq(ok, false, "missing manual log reports an error")
vim.fn.delete(temp, "rf")
print("quickfix_spec: ok")
