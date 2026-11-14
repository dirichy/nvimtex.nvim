vim.opt.runtimepath:prepend(vim.fn.getcwd())
local latex_nodes = require("nvimtex.parser.latex_nodes")

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local Render = require("nvimtex.conceal.render_tree")
local Command = require("nvimtex.conceal.command")
local Program = require("nvimtex.conceal.command_program")
local mathstyle = require("nvimtex.latex.mathstyle")

local source = [[\newcommand{\demo}[2]{\mathbb{#1}+#2+#1}]]
local root = vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
local definition
local function find(node)
	if node:type() == "new_command_definition" then
		definition = node
		return
	end
	for child in node:iter_children() do
		find(child)
	end
end
find(root)
local implementation = assert(latex_nodes.definition_body(assert(definition, "newcommand definition parsed")))

local specs = {
	mathbb = Command.transform(mathstyle.mathbb, "Special"),
}
local program = Program.compile(implementation, source, function(name)
	return specs[name]
end)
local operator_count = #program.operators

local function execute_tree(first, second)
	local context = { node = definition, source = source, anchor_row = 0, anchor_col = 0 }
	return assert(program:execute({
		Render.text(first, 0, 0),
		Render.text(second, 0, 0),
	}, context))
end

local function execute(first, second)
	local result = execute_tree(first, second)
	local chunks = result:to_virt_text("Normal", true)
	local text = {}
	for _, chunk in ipairs(chunks) do
		text[#text + 1] = chunk[1]
	end
	return table.concat(text)
end

eq(execute("A", "x"), "𝔸+x+A", "operator program supports nested calls and repeated arguments")
eq(execute("R", "y"), "ℝ+y+R", "compiled operator program is reusable")
eq(#program.operators, operator_count, "executing a program does not mutate its operators")

local invocation = [[\demo{A}{x}]]
local atomic = Render.concat_many({ Render.atomic(execute_tree("A", "x"), 0, 0), Render.boundary(0, #invocation) })
local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { invocation })
local namespace = vim.api.nvim_create_namespace("nvimtex.command_program_test")
atomic:emit_extmarks(buffer, namespace)
local marks = vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })
eq(#marks, 1, "an expanded custom command can own one atomic source range")
local displayed = {}
for _, chunk in ipairs(marks[1][4].virt_text) do
	displayed[#displayed + 1] = chunk[1]
end
eq(table.concat(displayed), "𝔸+x+A", "atomic expansion retains repeated argument output")

local strict = Command.transform({ A = "X" }, "Identifier")
eq(strict.render({ Render.text("?", 0, 0) }, {}), nil, "transform rejects a partially convertible command")

print("ok command templates and operator program")
