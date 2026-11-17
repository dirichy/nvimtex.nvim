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
eq(vim.wo.concealcursor, "nvic", "LaTeX applies configured cursor conceal")
eq(output(first), "α", "initial formula")
local initial = marks(first)
flush(first)
eq(marks(first), initial, "cursor-only refresh reuses inactive extmarks")
vim.wo.concealcursor = "i"
vim.wo.conceallevel = 1
conceal.setup_buf(first)
conceal.forceRefresh(first)
flush(first)
eq(vim.wo.concealcursor, "i", "repeated setup and refresh preserve user cursor conceal")
eq(vim.wo.conceallevel, 1, "repeated setup and refresh preserve user conceal level")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
flush(first)
eq(output(first), "", "native cursor-line reveal suppresses virtual replacement outside the formula")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
flush(first)
eq(output(first), "α", "leaving the revealed line restores conceal")
vim.wo.conceallevel = 0
flush(first)
eq(#marks(first), 0, "conceallevel zero removes virtual replacements")
conceal.toggle()
conceal.toggle()
flush(first)
eq(#marks(first), 0, "toggling conceal preserves the user's disabled conceal level")
eq(vim.wo.conceallevel, 0, "refresh leaves conceal disabled")
vim.wo.conceallevel = 2
vim.wo.concealcursor = "nvic"
flush(first)
eq(output(first), "α", "raising conceallevel restores rendering")
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

vim.wo.concealcursor = ""
local md = buffer("markdown", { "text $\\alpha$", "plain text" })
eq(vim.wo.concealcursor, "", "Markdown preserves native cursor-line reveal")
assert(#marks(md) > 0, "markdown has conceal marks")
for _, value in ipairs({ "n", "nvic", "" }) do
	vim.wo.concealcursor = value
	flush(md)
	eq(vim.wo.concealcursor, value, "Markdown refresh preserves user cursor conceal")
end
vim.api.nvim_buf_set_lines(md, 0, 1, false, { "text $\\alpha$ and $\\beta$" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
flush(md)
eq(output(md), "", "Markdown reveals every formula on the cursor line")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
flush(md)
eq(output(md), "αβ", "leaving Markdown line restores all formulas")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
flush(md)
eq(output(md), "", "returning to a cached Markdown line reveals all formulas")
vim.api.nvim_buf_set_lines(md, 0, 1, false, { "plain text" })
flush(md)
eq(#marks(md), 0, "removed Markdown injection clears its marks")
vim.api.nvim_buf_delete(md, { force = true })
eq(conceal.have_setup[md], nil, "Markdown detach releases setup state")
eq(conceal.buffer_state[md], nil, "Markdown detach releases buffer state")
eq(renderer.buffer_commands[md], nil, "Markdown detach leaves no definitions")

-- A separate event loop exercises real mode/option events without manual refresh.
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, {
	rpc = true,
	env = { NVIM_LOG_FILE = vim.fn.tempname() },
})
assert(child > 0)
local function lua(code, ...)
	return vim.rpcrequest(child, "nvim_exec_lua", code, { ... })
end
local function expect_rows(expected, label)
	assert(
		vim.wait(1000, function()
			return vim.deep_equal(
				lua([[
            local rows = {}
            for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('nvimtex'), 0, -1, {})) do
                rows[mark[2] + 1] = true
            end
            return { rows[1] or false, rows[2] or false }
        ]]),
				expected
			)
		end, 10),
		label
	)
end
local ok, err = xpcall(function()
	lua(
		[[
        vim.opt.rtp:prepend(...)
        vim.bo.filetype = 'tex'
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'text $\\alpha$', 'text $\\beta$', 'plain' })
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        require('nvimtex.conceal').config.debounce = 5
        require('nvimtex.conceal').setup_buf()
        vim.wo.concealcursor = 'n'
    ]],
		vim.fn.getcwd()
	)
	expect_rows({ true, true }, "initial event-loop rendering")
	vim.rpcrequest(child, "nvim_input", "ggi")
	expect_rows({ false, true }, "Insert mode reveals cursor line without moving")
	vim.rpcrequest(child, "nvim_input", "<Esc>")
	expect_rows({ true, true }, "leaving Insert mode restores cursor-line conceal")
	for _, visual in ipairs({ "v", "V", "<C-v>" }) do
		vim.rpcrequest(child, "nvim_input", "gg" .. visual .. "j")
		expect_rows({ false, false }, "Visual selection reveals every selected line: " .. visual)
		vim.rpcrequest(child, "nvim_input", "<Esc>")
		expect_rows({ true, true }, "leaving Visual mode restores every selected line")
	end
	vim.rpcrequest(child, "nvim_input", ":")
	expect_rows({ true, false }, "Command-line mode respects concealcursor")
	vim.rpcrequest(child, "nvim_input", "<Esc>")
	expect_rows({ true, true }, "leaving Command-line mode restores conceal")
	lua("vim.wo.conceallevel = 0")
	expect_rows({ false, false }, "OptionSet disables rendering without cursor movement")
	lua("require('nvimtex.conceal').setup_buf()")
	eq(lua("return vim.wo.conceallevel"), 0, "re-entering the buffer preserves user options")
	lua("vim.wo.conceallevel = 2")
	expect_rows({ true, true }, "OptionSet re-enables rendering")
	lua("vim.wo.concealcursor = ''")
	expect_rows({ true, false }, "OptionSet reveals the cursor line without movement")
end, debug.traceback)
vim.fn.jobstop(child)
assert(ok, err)
print("ok conceal edit, window, toggle, scroll, and detach lifecycle")
