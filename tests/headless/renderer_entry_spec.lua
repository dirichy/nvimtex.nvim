vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buffer)
vim.api.nvim_set_option_value("filetype", "tex", { scope = "local", buf = buffer })
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
	"\\documentclass{article}",
	"\\begin{document}",
	"$\\frac{ a }{ b }$",
	"plain text",
	"\\end{document}",
})
vim.api.nvim_win_set_cursor(0, { 4, 0 })

local renderer = require("nvimtex.conceal.renderer")
local original_render_node = renderer.render_node
local render_count = 0
renderer.render_node = function(...)
	render_count = render_count + 1
	return original_render_node(...)
end

local conceal = require("nvimtex.conceal")
conceal.setup_buf(buffer)
local namespace = vim.api.nvim_create_namespace("nvimtex")
eq(
	vim.wait(1000, function()
		return #vim.api.nvim_buf_get_extmarks(buffer, namespace, { 2, 0 }, { 3, 0 }, {}) > 1
	end, 10),
	true,
	"production entry emits fine-grained RenderTree extmarks"
)
renderer.render_node = original_render_node
eq(render_count, 1, "production entry renders one complete math root")

local marks = vim.api.nvim_buf_get_extmarks(buffer, namespace, { 2, 0 }, { 3, 0 }, { details = true })
local function concealed(column)
	for _, mark in ipairs(marks) do
		local details = mark[4]
		if details.conceal ~= nil and mark[3] <= column and details.end_col > column then
			return true
		end
	end
	return false
end

eq(concealed(8), false, "ordinary numerator text remains unconcealed")
eq(concealed(13), false, "ordinary denominator text remains unconcealed")
for _, column in ipairs({ 6, 7, 9, 10, 11, 12, 14, 15 }) do
	eq(concealed(column), true, "command syntax and ignored spaces are concealed at column " .. column)
end

vim.api.nvim_win_set_cursor(0, { 3, 1 })
conceal.refresh(buffer)
eq(
	vim.wait(1000, function()
		marks = vim.api.nvim_buf_get_extmarks(buffer, namespace, { 2, 0 }, { 3, 0 }, { details = true })
		return not concealed(1) and not concealed(10) and not concealed(15)
	end, 10),
	true,
	"CursorMoved rendering reveals the complete fraction delimiter family"
)

vim.api.nvim_win_set_cursor(0, { 4, 0 })
conceal.refresh(buffer)
eq(
	vim.wait(1000, function()
		marks = vim.api.nvim_buf_get_extmarks(buffer, namespace, { 2, 0 }, { 3, 0 }, { details = true })
		return concealed(1) and concealed(10) and concealed(15)
	end, 10),
	true,
	"leaving a math tree restores its normal conceal"
)

print("ok new renderer production entry")
