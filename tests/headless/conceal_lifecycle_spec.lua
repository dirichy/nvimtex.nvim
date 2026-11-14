vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
	end
end

local conceal = require("nvimtex.conceal")
local renderer = require("nvimtex.conceal.renderer")
local ns = require("nvimtex.conceal.extmark").ns_id.conceal
conceal.config.debounce = 5

local function flush(...)
	for _, buf in ipairs({ ... }) do
		conceal.refresh(buf)
	end
	local done = false
	vim.defer_fn(function()
		done = true
	end, 30)
	assert(
		vim.wait(1000, function()
			return done
		end, 1),
		"refresh completed"
	)
end

local function buffer(ft, lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = ft
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { #lines, 0 })
	conceal.setup_buf(buf)
	flush(buf)
	return buf
end

local function marks(buf)
	return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

local function output(buf)
	local text = {}
	for _, mark in ipairs(marks(buf)) do
		for _, chunk in ipairs(mark[4].virt_text or {}) do
			text[#text + 1] = chunk[1]
		end
	end
	return table.concat(text)
end

local first = buffer("tex", { [[\begin{document}]], [[$\alpha$]], "plain text", [[\end{document}]] })
eq(output(first), "α", "initial formula")
local initial = marks(first)
flush(first)
eq(marks(first), initial, "cursor-only refresh reuses inactive extmarks")
vim.api.nvim_buf_set_lines(first, 1, 2, false, { [[$\beta$]] })
flush(first)
eq(output(first), "β", "editing a formula off the cursor invalidates generated text")
vim.api.nvim_buf_set_lines(first, 1, 2, false, { "plain text" })
flush(first)
eq(#marks(first), 0, "removing a formula removes stale extmarks")
vim.api.nvim_buf_set_lines(first, 1, 2, false, { [[\(\alpha\)\(\beta\)]] })
flush(first)
eq(output(first), "$α$$β$", "adjacent math roots both render")
vim.api.nvim_win_set_cursor(0, { 2, 2 })
flush(first)
eq(output(first), "$$$β$", "revealing one adjacent formula leaves the next formula intact")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
flush(first)
eq(output(first), "$α$$β$", "leaving adjacent formulas restores both")

-- Each visible buffer gets its own refresh timer and cursor context.
local first_win = vim.api.nvim_get_current_win()
vim.cmd("vsplit")
local second = buffer("tex", { [[\begin{document}]], [[$\gamma$]], "plain text", [[\end{document}]] })
local second_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(first, 1, 2, false, { [[$\delta$]] })
vim.api.nvim_buf_set_lines(second, 1, 2, false, { [[$\epsilon$]] })
flush(first, second)
eq(output(first), "δ", "refresh of another buffer is not cancelled")
eq(output(second), "ϵ", "second buffer refresh runs")
eq(vim.api.nvim_get_current_win(), second_win, "refresh preserves the active window")
vim.api.nvim_win_set_cursor(first_win, { 2, 2 })
flush(first, second)
eq(output(first), "", "non-current visible buffer uses its own window cursor")
eq(output(second), "ϵ", "non-current refresh does not reveal the active buffer")

conceal.toggle()
eq(#marks(first), 0, "toggle off clears first buffer")
eq(#marks(second), 0, "toggle off clears second buffer")
flush(first, second)
eq(#marks(first) + #marks(second), 0, "pending refresh cannot re-enable conceal")
vim.api.nvim_win_set_cursor(first_win, { 3, 0 })
conceal.toggle()
flush(first, second)
eq(output(first), "δ", "toggle on restores first buffer")
eq(output(second), "ϵ", "toggle on restores second buffer")

vim.api.nvim_win_close(first_win, true)
vim.api.nvim_buf_set_lines(first, 1, 2, false, { [[$\zeta$]] })
flush(first)
vim.api.nvim_set_current_buf(first)
conceal.setup_buf(first)
flush(first)
eq(output(first), "ζ", "hidden edits render when the buffer is shown again")

-- Scrolling by a window event, without changing text, renders the new viewport.
local lines = { [[\begin{document}]] }
for index = 1, 100 do
	lines[#lines + 1] = index == 80 and [[$\alpha$]] or "plain text"
end
lines[#lines + 1] = [[\end{document}]]
vim.api.nvim_buf_set_lines(first, 0, -1, false, lines)
vim.api.nvim_win_set_height(0, 10)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! zt")
vim.cmd("redraw")
flush(first)
eq(output(first), "", "offscreen formula is skipped")
vim.api.nvim_win_set_cursor(0, { 81, 0 })
vim.cmd("normal! zt")
vim.cmd("redraw")
vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(second_win) })
local done = false
vim.defer_fn(function()
	done = true
end, 30)
assert(vim.wait(1000, function()
	return done
end, 1))
eq(output(first), "α", "scroll event renders newly visible formulas")

local md = buffer("markdown", { "text $\\alpha$", "plain text" })
assert(#marks(md) > 0, "markdown has conceal marks")
vim.api.nvim_buf_set_lines(md, 0, 1, false, { "plain text" })
flush(md)
eq(#marks(md), 0, "removed Markdown injection clears its marks")
vim.api.nvim_buf_delete(md, { force = true })
eq(conceal.have_setup[md], nil, "Markdown detach releases setup state")
eq(conceal.buffer_state[md], nil, "Markdown detach releases buffer state")
eq(renderer.buffer_commands[md], nil, "Markdown detach leaves no definitions")
print("ok conceal edit, window, toggle, scroll, and detach lifecycle")
