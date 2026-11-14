vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_set_option_value("filetype", "markdown", { scope = "local", buf = buf })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"first $x^2$",
	"second $\\frac{1}{2}$",
	"third $$a_i$$",
})

local roots = require("nvimtex.conceal").latex_roots(buf)
local viewport_top = require("nvimtex.conceal.util").viewport()
eq(viewport_top, 0, "viewport uses zero-based rows")
local texts = {}
for _, root in ipairs(roots) do
	texts[#texts + 1] = vim.treesitter.get_node_text(root, buf)
end

eq(texts, { "$x^2$", "$\\frac{1}{2}$", "$$a_i$$" }, "markdown latex roots")

local long_document = {}
for line = 1, 100 do
	long_document[line] = line == 1 and "visible $\\alpha$" or "ordinary text"
end
long_document[100] = "offscreen $y$"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, long_document)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_win_set_height(0, 10)
vim.cmd("redraw")

roots = require("nvimtex.conceal").latex_roots(buf)
texts = {}
for _, root in ipairs(roots) do
	texts[#texts + 1] = vim.treesitter.get_node_text(root, buf)
end
eq(texts, { "$\\alpha$" }, "markdown roots are limited to the visible range")
require("nvimtex.conceal").setup_buf(buf)
local conceal_namespace = vim.api.nvim_create_namespace("nvimtex")
local refreshed = vim.wait(500, function()
	return #vim.api.nvim_buf_get_extmarks(buf, conceal_namespace, 0, -1, {}) > 0
end, 10)
eq(refreshed, true, "markdown setup schedules conceal processing")
print("ok conceal markdown multiple latex roots")
