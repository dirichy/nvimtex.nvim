vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function eq(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local Render = require("nvimtex.conceal.render_tree")
local mode = Render.mode

local alpha = Render.highlight(Render.text("α", 0, 0), "Alpha")
local space = Render.text(" ", 0, 6, mode.reveal)
local plus = Render.text("+", 0, 7, mode.reveal)
local beta = Render.highlight(Render.text("β", 0, 9), "Beta")
local tree = alpha + space + plus + beta + Render.boundary(0, 14)

local batched = Render.concat_many({ alpha, space, plus, beta, Render.boundary(0, 14) })
eq(#batched.children, 5, "concat_many creates one multi-child concat node")
eq(batched.width, tree.width, "multi-child concat caches aggregate width")

eq(tree.width, 4, "concat caches display width")
eq(tree:to_virt_text("Default"), { { "α", "Alpha" }, { "β", "Beta" } }, "virt text omits revealed leaves")

local overridden = Render.highlight(tree, "Override")
eq(overridden.width, tree.width, "highlight preserves width")
eq(
	overridden:to_virt_text(),
	{ { "α", "Override" }, { "β", "Override" } },
	"outer highlight overrides inner highlights"
)

local styled = tree:try_transform({ ["α"] = "A", [" "] = " ", ["+"] = "+", ["β"] = "B" }, "Styled")
eq(styled ~= nil, true, "valid style succeeds")
eq(styled:to_virt_text(), { { "A", "Styled" }, { "B", "Styled" } }, "style transforms concealed leaves")
eq(tree:try_transform({ ["α"] = "A" }), nil, "invalid transform fails without changing source")
eq(tree:to_virt_text("Default"), { { "α", "Alpha" }, { "β", "Beta" } }, "failed style leaves source immutable")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\\alpha + \\beta" })
local namespace = vim.api.nvim_create_namespace("nvimtex.render_tree_test")
local ids = tree:emit_extmarks(buf, namespace, { default_highlight = "Normal" })
eq(#ids, 2, "revealed leaves emit no extmarks")

local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
eq(
	{ marks[1][2], marks[1][3], marks[1][4].end_row, marks[1][4].end_col },
	{ 0, 0, 0, 6 },
	"next leaf start defines alpha range"
)
eq(
	{ marks[2][2], marks[2][3], marks[2][4].end_row, marks[2][4].end_col },
	{ 0, 9, 0, 14 },
	"boundary defines final beta range"
)

vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
ids = tree:emit_extmarks(buf, namespace, {
	reveal = function(start)
		return start[2] == 9
	end,
})
eq(#ids, 1, "dynamic reveal suppresses a concealed leaf")

local atomic_child = Render.highlight(Render.text("B", 4, 0), "Atomic")
	+ Render.highlight(Render.text("A", 1, 0), "Atomic")
local atomic = Render.atomic(atomic_child, 0, 0) + Render.boundary(0, 14)
eq(atomic:to_virt_text(), { { "B", "Atomic" }, { "A", "Atomic" } }, "atomic render preserves child chunks")
eq(#atomic:emit_extmarks(buf, namespace), 1, "atomic render tolerates reordered child positions")

local delimiters = Render.concat_many({
	Render.delim_open("(", 0, 0),
	Render.delim_open("[", 0, 1),
	Render.delim_close("]", 0, 2),
	Render.delim_close(")", 0, 3),
	Render.boundary(0, 4),
})
eq(
	delimiters:to_virt_text(),
	{ { "(", "Function" }, { "[", "Identifier" }, { "]", "Identifier" }, { ")", "Function" } },
	"delimiter colours are resolved from nesting depth while flattening"
)

local multiline_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(multiline_buf, 0, -1, false, { "\\frac{", "  \\alpha", "  \\beta}" })
local multiline_namespace = vim.api.nvim_create_namespace("nvimtex.render_tree_multiline_test")
local multiline = Render.text("X", 0, 0) + Render.boundary(2, 8)
multiline:emit_extmarks(multiline_buf, multiline_namespace)
local multiline_marks = vim.api.nvim_buf_get_extmarks(multiline_buf, multiline_namespace, 0, -1, { details = true })
eq(#multiline_marks, 3, "a cross-line leaf emits one extmark per affected line")
eq(
	{ multiline_marks[1][2], multiline_marks[1][3], multiline_marks[1][4].end_row, multiline_marks[1][4].end_col },
	{ 0, 0, 0, 6 },
	"cross-line replacement text stays on its first line"
)
eq(
	{ multiline_marks[2][2], multiline_marks[2][3], multiline_marks[2][4].end_row, multiline_marks[2][4].end_col },
	{ 1, 2, 1, 8 },
	"continuation conceal preserves indentation"
)
eq(
	{ multiline_marks[3][2], multiline_marks[3][3], multiline_marks[3][4].end_row, multiline_marks[3][4].end_col },
	{ 2, 2, 2, 8 },
	"final continuation line preserves indentation"
)
eq(multiline_marks[2][4].virt_text, nil, "continuation lines conceal surplus source without repeated output")

print("ok immutable render tree")
