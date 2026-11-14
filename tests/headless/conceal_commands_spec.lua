vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
	end
end

local conceal = require("nvimtex.conceal")
local renderer = require("nvimtex.conceal.renderer")
local parser = require("nvimtex.parser")
local ns = require("nvimtex.conceal.extmark").ns_id.conceal
conceal.config.debounce = 5

local function flush(buffer)
	conceal.refresh(buffer)
	local done = false
	vim.defer_fn(function()
		done = true
	end, 20)
	assert(
		vim.wait(1000, function()
			return done
		end, 1),
		"refresh completed"
	)
end

local function make_buffer(definitions, formula)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)
	vim.bo[buf].filetype = "tex"
	local lines = { "% nvimtex: enable_parser_command_definition" }
	vim.list_extend(lines, definitions)
	vim.list_extend(lines, { "\\begin{document}", "$" .. formula .. "$", "plain text", "\\end{document}" })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { #lines - 1, 0 })
	conceal.setup_buf(buf)
	flush(buf)
	return buf, #lines - 3
end

local function output(buf)
	local text = {}
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
		for _, chunk in ipairs(mark[4].virt_text or {}) do
			text[#text + 1] = chunk[1]
		end
	end
	return table.concat(text)
end

local first, row = make_buffer({
	[[\newcommand{\demo}[2]{\mathbb{#1}+#2+#1+\alpha}]],
}, [[\demo{A}{x}]])
eq(output(first), "𝔸+x+A+α", "production path expands nested calls, symbols, and repeated arguments")
eq(renderer.command_specs.demo, nil, "definition is buffer local")
eq(require("nvimtex.parser.command_specs").demo, nil, "signature is buffer local")

vim.api.nvim_win_set_cursor(0, { row + 1, 3 })
flush(first)
eq(output(first), "", "editing an atomic expansion reveals its invocation")
vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
flush(first)
eq(output(first), "𝔸+x+A+α", "leaving restores the expansion")

local second = make_buffer({ [[\newcommand{\demo}[1]{\mathfrak{#1}}]] }, [[\demo{A}]])
eq(output(second), "𝔄", "same name can have a different definition and arity in another buffer")
vim.api.nvim_set_current_buf(first)
flush(first)
eq(output(first), "𝔸+x+A+α", "switching buffers preserves the first definition")

vim.api.nvim_buf_set_lines(first, 1, 2, false, { [[\newcommand{\demo}[2]{#2+#1}]] })
flush(first)
eq(output(first), "x+A", "editing a definition invalidates its expansion")
vim.api.nvim_buf_set_lines(first, 1, 2, false, {})
flush(first)
eq(renderer.buffer_commands[first].demo, nil, "deleted definition is removed")
eq(parser.buffer_command_specs[first].demo, nil, "deleted signature is removed")
eq(output(first), "", "deleted command is no longer expanded")

local optional = make_buffer({
	[[\newcommand{\demo}[2][R]{\mathbb{#1}+#2}]],
}, [[\demo{x}+\demo[A]{y}]])
eq(output(optional), "ℝ+x𝔸+y", "optional default and explicit optional argument expand")

local forward = make_buffer({
	[[\newcommand{\outer}[1]{\inner{#1}}]],
	[[\newcommand{\inner}[1]{\frac{#1}{2}+\sqrt[3]{#1}+x_{#1}}]],
}, [[\outer{1}]])
eq(output(forward), "¹/₂+³√1̅+x₁", "forward calls support fraction, optional root, and scripts")

local recursive = make_buffer({ [[\newcommand{\loop}[1]{\loop{#1}}]] }, [[\loop{x}]])
eq(output(recursive), "", "recursive expansion reveals source instead of overflowing")
local recursive_default = make_buffer({ [[\newcommand{\loop}[1][\loop]{#1}]] }, [[\loop]])
eq(output(recursive_default), "", "recursive optional defaults reveal source instead of overflowing")
local unknown = make_buffer({ [[\newcommand{\demo}[1]{\unknown{#1}}]] }, [[\demo{x}]])
eq(output(unknown), "", "unsupported expansion reveals source instead of displaying placeholders")
local missing_argument = make_buffer({ [[\newcommand{\demo}[2]{#1+#2}]] }, [[\demo{x}]])
eq(output(missing_argument), "", "an incomplete invocation stays visible")
local implicit = make_buffer({ [[\newcommand{\demo}[1]{\frac#12}]] }, [[\demo1]])
eq(output(implicit), "¹/₂", "compiled commands retain implicit TeX arguments")
local literal_brackets = make_buffer({ [[\newcommand{\demo}[1]{[#1]}]] }, [[\demo{x}]])
eq(output(literal_brackets), "[x]", "literal brackets inside a definition remain visible")
local conditional = make_buffer({
	[[\newcommand{\demo}[1]{% comment]],
	[[\ifmmode\mathbb{#1}\else plain\fi}]],
}, [[\demo{R}]])
eq(output(conditional), "ℝ", "comments are omitted and ifmmode uses the math branch")

local disabled = make_buffer({
	"% nvimtex: disable_parser_command_definition",
	[[\newcommand{\demo}[1]{\mathbb{#1}}]],
}, [[\demo{A}]])
eq(renderer.buffer_commands[disabled].demo, nil, "disable directive prevents command compilation")

vim.api.nvim_buf_delete(second, { force = true })
eq(renderer.buffer_commands[second], nil, "deleting a buffer releases render definitions")
eq(parser.buffer_command_specs[second], nil, "deleting a buffer releases parser definitions")
eq(conceal.buffer_state[second], nil, "deleting a buffer releases refresh state")
print("ok production conceal document commands")
