vim.opt.runtimepath:prepend(vim.fn.getcwd())

local Parser = require("nvimtex.parser")
local LNode = require("nvimtex.parser.lnode")

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function parse(source)
	return vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
end

local function parsed_children(source)
	local children = {}
	for node, field in Parser.iter_children(parse(source), source) do
		table.insert(children, { node = node, field = field })
	end
	return children
end

local function child_texts(node, source, field)
	local result = {}
	for _, child in ipairs(node:field(field)) do
		table.insert(result, vim.treesitter.get_node_text(child, source))
	end
	return result
end

local source = "\\ifmmode a\\else b\\fi"
local root = parse(source)
local rendered = LNode:new(root):tostring()
if not rendered:match("source_file") then
	error("lnode tostring should render source_file")
end
print("ok parser lnode tostring")

local node = Parser.iter_children(root, source)()
eq(node:type(), "if_statement", "if statement type")
eq(node:field("if")[1]:type(), "if", "if node type")
eq(node:field("else")[1]:type(), "else", "else node type")
eq({ node:field("else")[1]:range() }, { 0, 10, 0, 15 }, "else node range")
eq(node:field("fi")[1]:type(), "fi", "fi node type")
eq({ node:field("fi")[1]:range() }, { 0, 17, 0, 20 }, "fi node range")
print("ok parser if statement")

local sqrt_source = "\\sqrt[3]{x}"
local sqrt = parsed_children(sqrt_source)[1].node
eq(sqrt:type(), "generic_command", "sqrt type")
eq(child_texts(sqrt, sqrt_source, "optional_arg"), { "[3]" }, "sqrt optional arg")
eq(child_texts(sqrt, sqrt_source, "arg"), { "{x}" }, "sqrt required arg")
print("ok parser optional argument")

local sqrt_without_optional_source = "\\sqrt{x}"
local sqrt_without_optional = parsed_children(sqrt_without_optional_source)[1].node
eq(#sqrt_without_optional:field("optional_arg"), 0, "sqrt without optional arg")
eq(
	child_texts(sqrt_without_optional, sqrt_without_optional_source, "arg"),
	{ "{x}" },
	"sqrt without optional required arg"
)
print("ok parser no optional argument")

local sqrt_implicit_source = "\\sqrt[3]x"
local sqrt_implicit = parsed_children(sqrt_implicit_source)[1].node
eq(child_texts(sqrt_implicit, sqrt_implicit_source, "optional_arg"), { "[3]" }, "sqrt implicit optional arg")
eq(child_texts(sqrt_implicit, sqrt_implicit_source, "arg"), { "x" }, "sqrt implicit required arg")
print("ok parser optional plus implicit argument")

local unprotected_bracket_source = "\\sqrt[a[b]c]x"
local unprotected_bracket_children = parsed_children(unprotected_bracket_source)
local unprotected_bracket = unprotected_bracket_children[1].node
eq(
	child_texts(unprotected_bracket, unprotected_bracket_source, "optional_arg"),
	{ "[a[b]" },
	"unprotected bracket optional arg"
)
eq(child_texts(unprotected_bracket, unprotected_bracket_source, "arg"), { "c" }, "unprotected bracket required arg")
eq(
	vim.treesitter.get_node_text(unprotected_bracket_children[2].node, unprotected_bracket_source),
	"]",
	"unprotected bracket residual"
)
eq(
	vim.treesitter.get_node_text(unprotected_bracket_children[3].node, unprotected_bracket_source),
	"x",
	"unprotected bracket residual word"
)
print("ok parser unprotected bracket optional argument")

local nested_optional_source = "\\sqrt[\\sqrt[3]x]y"
local nested_optional = parsed_children(nested_optional_source)[1].node
eq(child_texts(nested_optional, nested_optional_source, "optional_arg"), { "[\\sqrt[3]x]" }, "nested optional arg")
eq(child_texts(nested_optional, nested_optional_source, "arg"), { "y" }, "nested optional required arg")
local nested_optional_children = {}
for child in Parser.iter_children(nested_optional:field("optional_arg")[1], nested_optional_source) do
	table.insert(nested_optional_children, child)
end
local nested_optional_sqrt = nested_optional_children[2]
eq(
	child_texts(nested_optional_sqrt, nested_optional_source, "optional_arg"),
	{ "[3]" },
	"nested optional inner optional arg"
)
eq(child_texts(nested_optional_sqrt, nested_optional_source, "arg"), { "x" }, "nested optional inner required arg")
print("ok parser nested optional command")

local frac_source = "\\frac12x"
local frac_children = parsed_children(frac_source)
local frac = frac_children[1].node
eq(child_texts(frac, frac_source, "arg"), { "1", "2" }, "frac implicit args")
eq(frac_children[2].node:type(), "word", "frac residual type")
eq(vim.treesitter.get_node_text(frac_children[2].node, frac_source), "x", "frac residual text")
print("ok parser implicit arguments")

local nested_source = "\\frac{\\sqrt[3]x}{\\bar[y]}z"
local nested_children = parsed_children(nested_source)
local nested_frac = nested_children[1].node
eq(child_texts(nested_frac, nested_source, "arg"), { "{\\sqrt[3]x}", "{\\bar[y]}" }, "nested frac args")
eq(vim.treesitter.get_node_text(nested_children[2].node, nested_source), "z", "nested frac residual")
local numerator_children = {}
for child in Parser.iter_children(nested_frac:field("arg")[1], nested_source) do
	table.insert(numerator_children, child)
end
local nested_sqrt = numerator_children[2]
eq(child_texts(nested_sqrt, nested_source, "optional_arg"), { "[3]" }, "nested sqrt optional arg")
eq(child_texts(nested_sqrt, nested_source, "arg"), { "x" }, "nested sqrt arg")
local denominator_children = {}
for child in Parser.iter_children(nested_frac:field("arg")[2], nested_source) do
	table.insert(denominator_children, child)
end
local nested_bar = denominator_children[2]
eq(child_texts(nested_bar, nested_source, "arg"), { "[" }, "nested bar bracket arg")
eq(vim.treesitter.get_node_text(denominator_children[3], nested_source), "y", "nested bar residual")
eq(vim.treesitter.get_node_text(denominator_children[4], nested_source), "]", "nested bar closing residual")
print("ok parser nested nodes")

local script_source = "a_i^j"
local script = parsed_children(script_source)[1].node
eq(script:type(), "script", "script node type")
eq(child_texts(script, script_source, "base"), { "a" }, "script base")
eq(child_texts(script, script_source, "subscript"), { "_i" }, "script subscript")
eq(child_texts(script, script_source, "superscript"), { "^j" }, "script superscript")
local script_child_types = {}
for child in Parser.iter_children(script, script_source) do
	table.insert(script_child_types, child:type())
end
eq(script_child_types, { "word", "subscript", "superscript" }, "script children do not fold recursively")
print("ok parser script node")

local script_reversed_source = "a^i_j"
local script_reversed = parsed_children(script_reversed_source)[1].node
eq(child_texts(script_reversed, script_reversed_source, "base"), { "a" }, "script reversed base")
eq(child_texts(script_reversed, script_reversed_source, "superscript"), { "^i" }, "script reversed superscript")
eq(child_texts(script_reversed, script_reversed_source, "subscript"), { "_j" }, "script reversed subscript")
print("ok parser reversed script node")

local frac_script_source = "\\frac12_i"
local frac_script = parsed_children(frac_script_source)[1].node
eq(frac_script:type(), "script", "frac script type")
eq(frac_script:field("base")[1]:type(), "generic_command", "frac script base type")
eq(child_texts(frac_script, frac_script_source, "subscript"), { "_i" }, "frac script subscript")
eq(child_texts(frac_script:field("base")[1], frac_script_source, "arg"), { "1", "2" }, "frac script base args")
print("ok parser command script node")

local bar_script_source = "\\bar x_i"
local bar_script = parsed_children(bar_script_source)[1].node
eq(bar_script:type(), "script", "bar script type")
eq(bar_script:field("base")[1]:type(), "generic_command", "bar script base type")
eq(child_texts(bar_script:field("base")[1], bar_script_source, "arg"), { "x" }, "bar script base arg")
eq(child_texts(bar_script, bar_script_source, "subscript"), { "_i" }, "bar script subscript")
print("ok parser command with implicit arg script node")

local group_script_source = "{ab}_i"
local group_script = parsed_children(group_script_source)[1].node
eq(group_script:type(), "script", "group script type")
eq(child_texts(group_script, group_script_source, "base"), { "{ab}" }, "group script base")
eq(child_texts(group_script, group_script_source, "subscript"), { "_i" }, "group script subscript")
print("ok parser group script node")

local bare_script_source = "_i"
local bare_script = parsed_children(bare_script_source)[1].node
eq(bare_script:type(), "subscript", "bare script stays raw")
print("ok parser bare script")

local script_after_optional_source = "\\sqrt[a]_i"
local script_after_optional = parsed_children(script_after_optional_source)[1].node
eq(
	child_texts(script_after_optional, script_after_optional_source, "optional_arg"),
	{ "[a]" },
	"script after optional closes optional arg"
)
eq(
	child_texts(script_after_optional, script_after_optional_source, "arg"),
	{ "_i" },
	"script after optional is required arg"
)
print("ok parser script after optional argument")

local verb_source = "\\verb|a_b|x"
local verb_children = parsed_children(verb_source)
local verb = verb_children[1].node
eq(verb:type(), "generic_command", "verb command type")
eq(child_texts(verb, verb_source, "arg"), { "|a_b|" }, "verb arg text")
local verb_group = verb:field("arg")[1]
eq(verb_group:type(), "verb_group", "verb group type")
eq(child_texts(verb_group, verb_source, "open"), { "|" }, "verb open delimiter")
eq(child_texts(verb_group, verb_source, "content"), { "a_b" }, "verb content")
eq(child_texts(verb_group, verb_source, "close"), { "|" }, "verb close delimiter")
eq(vim.treesitter.get_node_text(verb_children[2].node, verb_source), "x", "verb residual")
print("ok parser verb command")

local verb_operator_source = "\\verb+a+b+z"
local verb_operator_children = parsed_children(verb_operator_source)
local verb_operator = verb_operator_children[1].node
eq(child_texts(verb_operator, verb_operator_source, "arg"), { "+a+" }, "verb operator arg")
eq(vim.treesitter.get_node_text(verb_operator_children[2].node, verb_operator_source), "b", "verb operator residual")
eq(
	vim.treesitter.get_node_text(verb_operator_children[3].node, verb_operator_source),
	"+",
	"verb operator residual delimiter"
)
eq(
	vim.treesitter.get_node_text(verb_operator_children[4].node, verb_operator_source),
	"z",
	"verb operator residual word"
)
print("ok parser verb operator delimiter")

local verb_star_source = "\\verb*|a b|x"
local verb_star_children = parsed_children(verb_star_source)
local verb_star = verb_star_children[1].node
eq(child_texts(verb_star, verb_star_source, "arg"), { "|a b|" }, "verb star arg")
eq(vim.treesitter.get_node_text(verb_star_children[2].node, verb_star_source), "x", "verb star residual")
print("ok parser verb star command")

local unfinished_verb_source = "\\verb|abc"
local unfinished_verb = parsed_children(unfinished_verb_source)[1].node
eq(child_texts(unfinished_verb, unfinished_verb_source, "arg"), { "|abc" }, "unfinished verb arg")
eq(
	child_texts(unfinished_verb:field("arg")[1], unfinished_verb_source, "content"),
	{ "abc" },
	"unfinished verb content"
)
eq(#unfinished_verb:field("arg")[1]:field("close"), 0, "unfinished verb has no close delimiter")
print("ok parser unfinished verb")

local bar_source = "\\bar[x]"
local bar_children = parsed_children(bar_source)
local bar = bar_children[1].node
eq(child_texts(bar, bar_source, "arg"), { "[" }, "bar bracket token arg")
eq(vim.treesitter.get_node_text(bar_children[2].node, bar_source), "x", "bar residual text")
eq(vim.treesitter.get_node_text(bar_children[3].node, bar_source), "]", "bar closing bracket residual")
print("ok parser ordinary bracket argument")

local empty_if_source = "\\ifmmode\\else b\\fi"
local empty_if = parsed_children(empty_if_source)[1].node
eq(empty_if:type(), "if_statement", "empty if statement type")
eq({ empty_if:field("if_block")[1]:range() }, { 0, 8, 0, 8 }, "empty if block range")
eq(vim.treesitter.get_node_text(empty_if:field("else_block")[1], empty_if_source), "b", "empty if else block")
print("ok parser empty if block")

local no_body_if_source = "\\ifmmode\\fi"
local no_body_if = parsed_children(no_body_if_source)[1].node
eq({ no_body_if:field("if_block")[1]:range() }, { 0, 8, 0, 8 }, "no body if block range")
eq(#no_body_if:field("else_block"), 0, "no body if has no else block")
print("ok parser no body if")

local unfinished_if_source = "\\ifmmode a"
local unfinished_if = parsed_children(unfinished_if_source)[1].node
eq(unfinished_if:type(), "if_statement", "unfinished if statement type")
eq(vim.treesitter.get_node_text(unfinished_if:field("if_block")[1], unfinished_if_source), "a", "unfinished if block")
eq(#unfinished_if:field("fi"), 0, "unfinished if has no fi")
print("ok parser unfinished if")
