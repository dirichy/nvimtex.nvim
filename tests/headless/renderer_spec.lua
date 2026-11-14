vim.opt.runtimepath:prepend(vim.fn.getcwd())
local latex_nodes = require("nvimtex.parser.latex_nodes")

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local Render = require("nvimtex.conceal.render_tree")
local renderer = require("nvimtex.conceal.renderer")
local command_specs = require("nvimtex.parser.command_specs")
local parser_module = require("nvimtex.parser")

local function parse(source)
	return vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
end

local function find_command(root, source, wanted)
	local found
	local function visit(node)
		if found then
			return
		end
		if node:type() == "generic_command" then
			local name = latex_nodes.command_name(source, node)
			if name == wanted then
				found = node
				return
			end
		end
		for child in parser_module.iter_children(node, source) do
			visit(child)
		end
	end
	visit(root)
	return found
end

local function find_type(root, source, wanted)
	local found
	local function visit(node)
		if found then
			return
		end
		if node:type() == wanted then
			found = node
			return
		end
		for child in parser_module.iter_children(node, source) do
			visit(child)
		end
	end
	visit(root)
	return found
end

local frac_source = "\\frac{a}{b}"
local frac = assert(find_command(parse(frac_source), frac_source, "frac"))
local frac_tree = renderer.render_node(frac, frac_source)
local frac_text = {}
for _, chunk in ipairs(frac_tree:to_virt_text("Normal")) do
	frac_text[#frac_text + 1] = chunk[1]
end
eq(table.concat(frac_text), "()/()", "frac leaves ordinary argument text in the source")

local symbol_frac_source = "\\frac{\\alpha}{\\beta}"
local symbol_frac = assert(find_command(parse(symbol_frac_source), symbol_frac_source, "frac"))
local symbol_frac_tree = renderer.render_node(symbol_frac, symbol_frac_source)
local symbol_frac_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(symbol_frac_buf, 0, -1, false, { symbol_frac_source })
local symbol_frac_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_symbol_frac_test")
symbol_frac_tree:emit_extmarks(symbol_frac_buf, symbol_frac_namespace)
local symbol_frac_marks =
	vim.api.nvim_buf_get_extmarks(symbol_frac_buf, symbol_frac_namespace, 0, -1, { details = true })
local next_column = 0
for _, mark in ipairs(symbol_frac_marks) do
	eq(mark[3], next_column, "symbol fraction extmarks have no uncovered source gap")
	next_column = mark[4].end_col
end
eq(next_column, #symbol_frac_source, "symbol fraction covers both closing braces")

local style_source = "\\mathbb{x}"
local style = assert(find_command(parse(style_source), style_source, "mathbb"))
local style_tree = renderer.render_node(style, style_source)
local style_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(style_buf, 0, -1, false, { style_source })
local style_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_style_test")
style_tree:emit_extmarks(style_buf, style_namespace)
local style_marks = vim.api.nvim_buf_get_extmarks(style_buf, style_namespace, 0, -1, { details = true })
eq(#style_marks, 3, "adapter emits separate prefix, argument, and suffix extmarks")
eq({ style_marks[1][2], style_marks[1][3] }, { 0, 0 }, "adapter starts at the command prefix")
eq(
	{ style_marks[#style_marks][4].end_row, style_marks[#style_marks][4].end_col },
	{ 0, #style_source },
	"adapter covers the closing delimiter"
)

local styled_script_source = "\\mathbb{A_2}"
local styled_script = assert(find_command(parse(styled_script_source), styled_script_source, "mathbb"))
local styled_script_tree = renderer.render_node(styled_script, styled_script_source)
local styled_script_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(styled_script_buf, 0, -1, false, { styled_script_source })
local styled_script_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_styled_script_test")
styled_script_tree:emit_extmarks(styled_script_buf, styled_script_namespace)
eq(
	#vim.api.nvim_buf_get_extmarks(styled_script_buf, styled_script_namespace, 0, -1, {}),
	0,
	"font transform with a script fails atomically and keeps its complete source"
)

local expression_style_source = "\\mathbb{R+R}"
local expression_style = assert(find_command(parse(expression_style_source), expression_style_source, "mathbb"))
local expression_style_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(expression_style_buf, 0, -1, false, { expression_style_source })
local expression_style_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_expression_style_test")
renderer
	.render_node(expression_style, expression_style_source)
	:emit_extmarks(expression_style_buf, expression_style_namespace)
eq(
	#vim.api.nvim_buf_get_extmarks(expression_style_buf, expression_style_namespace, 0, -1, {}),
	0,
	"font transform with an unmappable operator keeps its complete source"
)

local unknown_style_source = "\\mathbb{\\unknown}"
local unknown_style = assert(find_command(parse(unknown_style_source), unknown_style_source, "mathbb"))
local unknown_style_tree = renderer.render_node(unknown_style, unknown_style_source)
local unknown_style_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(unknown_style_buf, 0, -1, false, { unknown_style_source })
local unknown_style_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_unknown_style_test")
unknown_style_tree:emit_extmarks(unknown_style_buf, unknown_style_namespace)
local unknown_style_marks =
	vim.api.nvim_buf_get_extmarks(unknown_style_buf, unknown_style_namespace, 0, -1, { details = true })
local function unknown_style_concealed(column)
	for _, mark in ipairs(unknown_style_marks) do
		local details = mark[4]
		if details.conceal ~= nil and mark[3] <= column and details.end_col > column then
			return true
		end
	end
	return false
end
eq(unknown_style_concealed(8), false, "unknown inner command remains revealed")
eq(unknown_style_concealed(0), false, "failed transform keeps its command prefix visible")
eq(unknown_style_concealed(#unknown_style_source - 1), false, "failed transform keeps its closing brace visible")

local script_source = "x_{2}"
local script = assert(find_type(parse(script_source), script_source, "subscript"))
local script_tree = renderer.render_node(script, script_source)
local script_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(script_buf, 0, -1, false, { script_source })
local script_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_script_test")
script_tree:emit_extmarks(script_buf, script_namespace)
local script_marks = vim.api.nvim_buf_get_extmarks(script_buf, script_namespace, 0, -1, { details = true })
local concealed = {}
for _, mark in ipairs(script_marks) do
	local details = mark[4]
	if details.conceal ~= nil then
		for column = mark[3], details.end_col - 1 do
			concealed[column] = true
		end
	end
end
eq(concealed[1], true, "script conceals the marker")
eq(concealed[2], true, "script conceals the opening brace")
eq(concealed[4], true, "script conceals the closing brace")
eq(script_marks[2][4].virt_text[1][2], "Identifier", "converted script uses the script highlight")

local command_script_source = "p_{\\partial}"
local command_script = assert(find_type(parse(command_script_source), command_script_source, "subscript"))
local command_script_tree = renderer.render_node(command_script, command_script_source)
local command_script_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(command_script_buf, 0, -1, false, { command_script_source })
local command_script_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_command_script_test")
command_script_tree:emit_extmarks(command_script_buf, command_script_namespace)
local command_script_marks =
	vim.api.nvim_buf_get_extmarks(command_script_buf, command_script_namespace, 0, -1, { details = true })
local closing_column = #command_script_source - 1
local closing_concealed = false
for _, mark in ipairs(command_script_marks) do
	local details = mark[4]
	if details.conceal ~= nil and mark[3] <= closing_column and details.end_col > closing_column then
		closing_concealed = true
	end
end
eq(closing_concealed, true, "fallback script consumes the source closing brace")
local command_script_chunks = command_script_tree:to_virt_text()
eq(command_script_chunks[1][2], "Function", "fallback script opens at the first delimiter depth")
eq(command_script_chunks[#command_script_chunks][2], "Function", "fallback script closes at the same delimiter depth")

local number_source = "12"
local number_word = assert(find_type(parse(number_source), number_source, "word"))
local number_tree = renderer.render_node(number_word, number_source)
local number_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(number_buf, 0, -1, false, { number_source })
local number_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_number_test")
number_tree:emit_extmarks(number_buf, number_namespace)
local number_marks = vim.api.nvim_buf_get_extmarks(number_buf, number_namespace, 0, -1, { details = true })
eq(number_marks[1][4].hl_group, "Constant", "numeric words retain the Constant highlight")

local sqrt_source = "\\sqrt{x}"
local sqrt = assert(find_command(parse(sqrt_source), sqrt_source, "sqrt"))
local sqrt_chunks = renderer.render_node(sqrt, sqrt_source):to_virt_text()
eq(
	sqrt_chunks,
	{ { "√", "MathZone" }, { "x̅", "MathZone" } },
	"narrow square root uses the argument colour for the radical and overline"
)

local overline_source = "\\overline{x}"
local overline = assert(find_command(parse(overline_source), overline_source, "overline"))
eq(
	renderer.render_node(overline, overline_source):to_virt_text(),
	{ { "x̅", "MathZone" } },
	"overline falls back to the inner word's normal math highlight"
)

local overline_number_source = "\\overline{2}"
local overline_number = assert(find_command(parse(overline_number_source), overline_number_source, "overline"))
eq(
	renderer.render_node(overline_number, overline_number_source):to_virt_text(),
	{ { "2̅", "Constant" } },
	"overline preserves an explicit inner highlight"
)

local failed_not_source = [[\not\unknown]]
local failed_not = assert(find_command(parse(failed_not_source), failed_not_source, "not"))
local failed_not_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(failed_not_buf, 0, -1, false, { failed_not_source })
local failed_not_namespace = vim.api.nvim_create_namespace("nvimtex.renderer_failed_not_test")
renderer.render_node(failed_not, failed_not_source):emit_extmarks(failed_not_buf, failed_not_namespace)
eq(
	#vim.api.nvim_buf_get_extmarks(failed_not_buf, failed_not_namespace, 0, -1, {}),
	0,
	"failed not transform reveals the complete command instead of changing its meaning"
)

local function render_marks(source, node, cursor, namespace_name)
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { source })
	local namespace = vim.api.nvim_create_namespace(namespace_name)
	renderer.render_node(node, source, { cursor = { 0, cursor } }):emit_extmarks(buffer, namespace)
	return vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })
end

local function concealed_at(marks, column)
	for _, mark in ipairs(marks) do
		local details = mark[4]
		if details.conceal ~= nil and mark[3] <= column and details.end_col > column then
			return true
		end
	end
	return false
end

local cursor_frac_source = [[\frac{\alpha}{\beta}]]
local cursor_frac = assert(find_command(parse(cursor_frac_source), cursor_frac_source, "frac"))
local argument_marks = render_marks(cursor_frac_source, cursor_frac, 7, "nvimtex.renderer_cursor_argument")
eq(concealed_at(argument_marks, 0), true, "cursor in an argument leaves the outer command concealed")
eq(concealed_at(argument_marks, 6), false, "cursor reveals its argument leaf")
eq(concealed_at(argument_marks, 12), true, "cursor in an argument leaves middle delimiters concealed")
eq(concealed_at(argument_marks, 14), true, "cursor leaves sibling argument leaves concealed")

local delimiter_marks = render_marks(cursor_frac_source, cursor_frac, 0, "nvimtex.renderer_cursor_delimiter")
eq(concealed_at(delimiter_marks, 0), false, "cursor on a delimiter reveals the command prefix")
eq(concealed_at(delimiter_marks, 12), false, "cursor on a delimiter reveals the middle delimiter")
eq(concealed_at(delimiter_marks, 19), false, "cursor on a delimiter reveals the closing delimiter")
eq(concealed_at(delimiter_marks, 6), true, "delimiter reveal keeps argument commands concealed")
local highlighted_delimiters = 0
for _, mark in ipairs(delimiter_marks) do
	local details = mark[4]
	if details.conceal == nil and details.hl_group then
		highlighted_delimiters = highlighted_delimiters + 1
	end
end
eq(highlighted_delimiters >= 3, true, "revealed delimiter source keeps rainbow highlights")

local cursor_style_source = [[\mathbb{AB}]]
local cursor_style = assert(find_command(parse(cursor_style_source), cursor_style_source, "mathbb"))
local style_shell_marks = render_marks(cursor_style_source, cursor_style, 0, "nvimtex.renderer_cursor_style_shell")
eq(concealed_at(style_shell_marks, 0), false, "style template reveals its command prefix")
eq(concealed_at(style_shell_marks, 8), true, "style shell reveal keeps the argument transformed")
eq(concealed_at(style_shell_marks, 10), false, "style template reveals its closing brace")
local style_argument_marks = render_marks(cursor_style_source, cursor_style, 8, "nvimtex.renderer_cursor_style_arg")
eq(concealed_at(style_argument_marks, 0), false, "strict transform reveals its prefix while editing an argument")
eq(concealed_at(style_argument_marks, 8), false, "strict transform preserves the editable source leaf")
eq(concealed_at(style_argument_marks, 10), false, "strict transform reveals its closing delimiter")

command_specs.renderpair = { narg = 2 }
local pair_source = "\\renderpair{left}{right}"
local pair = assert(find_command(parse(pair_source), pair_source, "renderpair"))
local observed_args
local shared_renderer = function(args, context)
	observed_args = args
	local middle_row, middle_col = context.argument_nodes[1]:end_()
	return args[1]
		+ Render.text(":", middle_row, middle_col, Render.mode.insert)
		+ args[2]
		+ Render.boundary(context.node:end_())
end
local spec = renderer.register_command("renderpair", {
	narg = 2,
	render = shared_renderer,
})
eq(renderer.command_adapters.renderpair ~= nil, true, "registration compiles and caches the command adapter")

local adapter = renderer.adapt_command(spec)
local pair_tree = adapter(pair, pair_source)
eq(#observed_args, 2, "adapter extracts command arguments")
eq(
	renderer.render_node(pair, pair_source, { cursor = { 0, 13 } }):to_virt_text(),
	{},
	"a low-level renderer without a cursor policy reveals its complete command"
)
local pair_text = {}
for _, chunk in ipairs(pair_tree:to_virt_text("Normal")) do
	pair_text[#pair_text + 1] = chunk[1]
end
eq(table.concat(pair_text), ":", "adapter leaves ordinary argument text in the source")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { pair_source })
local namespace = vim.api.nvim_create_namespace("nvimtex.renderer_test")
local ids = pair_tree:emit_extmarks(buf, namespace)
eq(#ids > 1, true, "renderer preserves fine-grained extmarks")

command_specs.renderpair = nil
renderer.unregister_command("renderpair")

command_specs.renderoptional = { narg = 1, oarg = true }
local optional_source = [[\renderoptional{x}]]
local optional_node = assert(find_command(parse(optional_source), optional_source, "renderoptional"))
renderer.register_command(
	"renderoptional",
	renderer.command.optional(1, function(context)
		local row, col = context.node:start()
		return Render.text("default", row, col, Render.mode.insert)
	end, function(args)
		return args[1] + args[2]
	end)
)
local optional_chunks = renderer.render_node(optional_node, optional_source):to_virt_text("Normal", true)
local optional_text = {}
for _, chunk in ipairs(optional_chunks) do
	optional_text[#optional_text + 1] = chunk[1]
end
eq(table.concat(optional_text), "defaultx", "optional template supplies its lazy default RenderTree")
command_specs.renderoptional = nil
renderer.unregister_command("renderoptional")

print("ok render tree command adapter")
