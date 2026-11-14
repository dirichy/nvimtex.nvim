vim.opt.runtimepath:prepend(vim.fn.getcwd())

local Parser = require("nvimtex.parser")
local LNode = require("nvimtex.parser.lnode")
local nodes = require("nvimtex.parser.latex_nodes")
local renderer = require("nvimtex.conceal.renderer")
local definitions = require("nvimtex.conceal.definitions")

local function eq(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual))
end

local function parse(source)
	return vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
end

local function command(source)
	return assert(Parser.iter_children(parse(source), source)())
end

local function texts(children, source)
	local result = {}
	for _, child in ipairs(children) do
		result[#result + 1] = vim.treesitter.get_node_text(child, source)
	end
	return result
end

local source = "\\frac% comment\n{α}{β}"
local raw = assert(parse(source):child(0))
local copy = LNode:new(raw)
eq(rawget(getmetatable(copy), "field"), nil, "LNode has no field method")
eq(texts(nodes.arguments(raw), source), { "{α}", "{β}" }, "raw command skips comments")
eq(texts(nodes.arguments(copy), source), texts(nodes.arguments(raw), source), "raw and wrapped argument access agree")
eq(copy:named_child_count(), raw:named_child_count(), "named child count is retained")
for index = 0, raw:named_child_count() - 1 do
	eq(assert(copy:named_child(index)):type(), assert(raw:named_child(index)):type(), "named child order is retained")
end
local iter = copy:iter_children()
local first, label = iter()
assert(first)
eq(first:type(), "command_name", "copied child order is retained")
eq(label, nil, "LNode iteration returns no grammar field")

for _, sample in ipairs({ [[\frac12]], [[\sqrt[3]x]], [=[\bar[y]]=], [[\verb|x|]] }) do
	local node = command(sample)
	eq(node:child(0):type(), "command_name", "command token stays first")
	assert(#nodes.arguments(node) >= 1, "required argument is accessible")
end
local mixed = [[\frac{a}b]]
eq(texts(nodes.arguments(command(mixed)), mixed), { "{a}", "b" }, "grouped and implicit arguments share a layout")

-- Preparse before poisoning the native methods: these checks cover our node
-- access, not Neovim's own parser implementation or injection queries.
local formula = [[$\frac{\alpha}{\beta}+x_i+\sqrt[3]x$]]
local math = assert(parse(formula):child(0))
local definition_source = [[\newcommand\demo[2][R]{\mathbb{#1}+#2}]]
local definition_root = parse(definition_source)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(
	buf,
	0,
	-1,
	false,
	{ "% nvimtex: enable_parser_command_definition", definition_source, [[\begin{document}]], [[\end{document}]] }
)
local buffer_root = vim.treesitter.get_parser(buf, "latex"):parse()[1]:root()
local methods = getmetatable(math).__index
local original_field, original_iter = methods.field, methods.iter_children
methods.field = function()
	error("plugin called TSNode:field()")
end
methods.iter_children = function()
	error("plugin requested native field-aware iteration")
end
local ok, err = pcall(function()
	local function walk(node)
		for child, field in Parser.iter_children(node, formula) do
			eq(field, nil, "parser iteration returns only nodes")
			walk(child)
		end
	end
	walk(math)
	assert(#renderer.render_node(math, formula):to_virt_text("Normal", true) > 0, "renderer works without fields")
	local declaration, argc, default, body = nodes.definition_parts(assert(definition_root:child(0)))
	eq(nodes.command_name(definition_source, declaration), "demo", "ungrouped declaration is readable")
	assert(argc and default and body, "definition options and body are readable")
	definitions.scan(buffer_root, buf)
	assert(renderer.buffer_commands[buf].demo.adapter, "definition registers without fields")
	definitions.clear(buf)
end)
methods.field, methods.iter_children = original_field, original_iter
assert(ok, err)
vim.api.nvim_buf_delete(buf, { force = true })
print("ok TSNode-style nodes and semantic helpers without fields")
