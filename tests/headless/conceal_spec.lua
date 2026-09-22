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
local texts = {}
for _, root in ipairs(roots) do
	texts[#texts + 1] = vim.treesitter.get_node_text(root, buf)
end

eq(texts, { "$x^2$", "$\\frac{1}{2}$", "$$a_i$$" }, "markdown latex roots")
print("ok conceal markdown multiple latex roots")
