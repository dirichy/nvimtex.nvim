vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_set_option_value("filetype", "tex", { scope = "local", buf = buf })

local lines = {
	"\\documentclass{article}",
	"% nvimtex: enable_parser_command_definition",
	"\\newcommand{\\myvector}[1]{\\mathbb{#1}}",
	"\\begin{document}",
}
for index = 1, 80 do
	lines[#lines + 1] = index % 10 == 0 and "Formula $\\myvector{x}_i + \\alpha$." or "ordinary text"
end
lines[#lines + 1] = "\\end{document}"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_win_set_height(0, 10)
vim.api.nvim_win_set_cursor(0, { 44, 0 })
vim.cmd("normal! zz")
vim.cmd("redraw")

local conceal = require("nvimtex.conceal")
conceal.setup_buf(buf)
eq(
	vim.wait(1000, function()
		local state = conceal.buffer_state[buf]
		return state and not state.preamble_dirty
	end, 10),
	true,
	"initial preamble scan completed"
)

eq(conceal.buffer_state[buf].preamble_end, 3, "document boundary is cached")
eq(type(require("nvimtex.conceal.renderer").buffer_commands[buf].myvector.program), "table", "custom command compiled")
eq(require("nvimtex.conceal.renderer").command_specs.myvector, nil, "document command does not enter global registry")

vim.api.nvim_buf_set_lines(buf, 43, 44, false, { "changed body text" })
eq(conceal.buffer_state[buf].preamble_dirty, false, "body edit keeps preamble clean")

vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "\\newcommand{\\myvector}[1]{\\mathfrak{#1}}" })
eq(conceal.buffer_state[buf].preamble_dirty, true, "preamble edit marks cache dirty")
conceal.refresh(buf)
eq(
	vim.wait(1000, function()
		return not conceal.buffer_state[buf].preamble_dirty
	end, 10),
	true,
	"dirty preamble is rescanned"
)

local root = vim.treesitter.get_parser(buf, "latex"):parse()[1]:root()
local document = require("nvimtex.conceal.processor").find_document(root, buf)
local iterator = require("nvimtex.parser").iter_children(document, buf, {
	start_row = 43,
	end_row = 50,
	binary_threshold = 1,
	lookbehind = 0,
})
local first = iterator()
local _, _, first_end = first:range()
eq(first_end >= 43, true, "range iterator skips children before viewport")

print("ok conceal incremental preamble and ranged traversal")
