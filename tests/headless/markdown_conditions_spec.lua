vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_set_option_value("filetype", "markdown", { scope = "local", buf = buf })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"plain text",
	"`inline code`",
	"```",
	"code block",
	"```",
	"text $x^2$",
})

local md = require("nvimtex.conditions.markdown")

vim.api.nvim_win_set_cursor(0, { 1, 2 })
eq(md.in_text(), true, "plain markdown text")

vim.api.nvim_win_set_cursor(0, { 2, 2 })
eq(md.in_text(), false, "markdown inline code")

vim.api.nvim_win_set_cursor(0, { 4, 2 })
eq(md.in_text(), false, "markdown fenced code")

vim.api.nvim_win_set_cursor(0, { 6, 8 })
eq(md.in_text(), false, "markdown latex math")

vim.api.nvim_set_option_value("filetype", "tex", { scope = "local", buf = buf })
eq(md.in_text(), false, "tex filetype")

print("ok markdown conditions")
