vim.opt.runtimepath:prepend(vim.fn.getcwd())
local core = require("nvimtex.textobject.core")
assert(
	not package.loaded["mini.ai"] and not package.loaded["pairwise.textobject"],
	"core has no integration dependency"
)

local function eq(actual, expected, label)
	assert(
		vim.deep_equal(actual, expected),
		label .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
	)
end

local function fixture(marked, filetype)
	local lines = vim.split(marked, "\n", { plain = true })
	local row, col
	for index, line in ipairs(lines) do
		local found = line:find("|", 1, true)
		if found then
			row, col = index - 1, found - 1
			lines[index] = line:sub(1, found - 1) .. line:sub(found + 1)
		end
	end
	assert(row, "fixture needs a cursor marker")
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = filetype or "tex"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	return { bufnr = bufnr, reference = { row, col, row, col }, inner = true }
end

local function text(ctx, range)
	if not range then
		return nil
	end
	return table.concat(vim.api.nvim_buf_get_text(ctx.bufnr, range[1], range[2], range[3], range[4], {}), "\n")
end

local ctx = fixture([[\frac{a+\sqrt{|x}}{b}]])
local current = vim.api.nvim_get_current_buf()
local cursor = vim.api.nvim_win_get_cursor(0)
local source_buf = ctx.bufnr
local content = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
eq(text(ctx, core.find("c", ctx)), "sqrt", "inside command selects its name without backslash")
ctx.inner = false
eq(text(ctx, core.find("c", ctx)), [[\sqrt{x}]], "around command includes arguments")
ctx.count = 2
eq(text(ctx, core.find("c", ctx)), [[\frac{a+\sqrt{x}}{b}]], "command count selects the outer command")
ctx.count = 3
eq(core.find("c", ctx), nil, "missing enclosing layer returns nil")
ctx.count, ctx.inner = 1, true
local inner = assert(core.find("a", ctx))
eq(text(ctx, inner), "x", "inside argument")
ctx.reference = inner
eq(text(ctx, core.find("a", ctx)), [[a+\sqrt{x}]], "reference selection expands to the outer argument")
ctx = fixture([[\frac{a+\sqrt{|x}}{b}]])
ctx.count = 2
eq(text(ctx, core.find("a", ctx)), [[a+\sqrt{x}]], "argument count selects the outer argument")
ctx.count, ctx.inner = 1, false
eq(text(ctx, core.find("a", ctx)), "{x}", "around argument includes its delimiters")

eq(vim.api.nvim_get_current_buf(), current, "core does not switch buffers")
eq(vim.api.nvim_win_get_cursor(0), cursor, "core does not move the cursor")

for _, case in ipairs({
	{ [[\sqrt[|3]{x}]], "a", true, "3" },
	{ [[\sqrt[|3]{x}]], "a", false, "[3]" },
	{ [[\frac{|中文}{β}]], "a", true, "中文" },
	{ [[\frac{|}{b}]], "a", true, "" },
	{ [[\frac|{a}{b}]], "a", false, "{a}" },
	{ [[\fr|ac{a}{b}]], "a", false, nil },
	{ [[$|x+α$]], "m", true, "x+α" },
	{ [[$|x+α$]], "m", false, "$x+α$" },
	{ [[\(|x\)]], "m", true, "x" },
	{ "\\[\n  |x+α\n\\]", "m", true, "\n  x+α\n" },
	{ "\\begin{equation}\n|x\n\\end{equation}", "e", true, "\nx\n" },
	{ "\\begin{equation}\n|x\n\\end{equation}", "e", false, "\\begin{equation}\nx\n\\end{equation}" },
	{ "plain |text", "m", true, nil },
}) do
	local query = fixture(case[1])
	query.inner = case[3]
	eq(text(query, core.find(case[2], query)), case[4], case[1])
end

for _, case in ipairs({
	{ [[{a{|中文}b}]], "a", "中文", "{中文}" },
	{ [[\sqrt[|3]{x}]], "a", "3", "[3]" },
	{ [[{|}]], "a", "", "{}" },
	{ [[$x_{|ij}^2$]], "u", "ij", "_{ij}" },
	{ [[$x_i^{|jk}$]], "u", "jk", "^{jk}" },
	{ [[$x_|i$]], "u", "i", "_i" },
	{ [[$x_\al|pha$]], "u", [[\alpha]], [[_\alpha]] },
	{ [[$|x_i$]], "u", nil, nil },
	{ [[\begin{al|ign*}x\end{align*}]], "a", "align*", "{align*}" },
	{ [[\begin{align*}x\end{al|ign*}]], "a", "align*", "{align*}" },
}) do
	local query = fixture(case[1])
	eq(text(query, core.find(case[2], query)), case[3], "new inside: " .. case[1])
	query.inner = false
	eq(text(query, core.find(case[2], query)), case[4], "new around: " .. case[1])
end
for _, sample in ipairs({
	{ [[$x_{|ij}$]], "ij", "{ij}" },
	{ [[$x^{|2}$]], "2", "{2}" },
	{ [[$x_|i$]], nil, nil },
	{ [[$x^|2$]], nil, nil },
	{ [[$x_{|}$]], "", "{}" },
	{ [[\section{Ti|tle}]], "Title", "{Title}" },
	{ [[\label{ke|y}]], "key", "{key}" },
	{ [[$x_\al|pha$]], nil, nil },
	{ [[\sqrt |x]], nil, nil },
	{ [[\begin{align*}|x\end{align*}]], nil, nil },
	{ [[$|x_i$]], nil, nil },
	{ [[{\sqrt |x}]], [[\sqrt x]], [[{\sqrt x}]] },
	{ [[$x_{y^|2}$]], "y^2", "{y^2}" },
	{ [[{|x]], nil, nil },
}) do
	local query = fixture(sample[1])
	eq(text(query, core.find("a", query)), sample[2], "general inside argument: " .. sample[1])
	query.inner = false
	eq(text(query, core.find("a", query)), sample[3], "general around argument: " .. sample[1])
end
local nested_argument = fixture([[$x_{i_{|j}}$]])
nested_argument.count = 2
eq(text(nested_argument, core.find("a", nested_argument)), "i_{j}", "script argument layers are counted once")

local grouped = fixture([[{a{|x}b}]])
grouped.count = 2
eq(text(grouped, core.find("a", grouped)), "a{x}b", "group nesting")
for _, sample in ipairs({
	{ "g", [[{|x}]], "x" },
	{ "m", [[$|x$]], "x" },
	{ "e", [[\begin{align}|x\end{align}]], "x" },
}) do
	local query = fixture(sample[2])
	local pair = assert(core.find_pair(sample[1], query))
	eq(
		text(query, { pair.inner_start[1], pair.inner_start[2], pair.inner_end[1], pair.inner_end[2] }),
		sample[3],
		"surround contents"
	)
end
local unfinished = fixture([[{|x]])
eq(core.find_pair("g", unfinished), nil, "unfinished group has no removable pair")

local scripts = fixture([[$x_{i_{|j}}$]])
scripts.count = 2
eq(text(scripts, core.find("u", scripts)), "i_{j}", "script nesting")
local mismatched = fixture([[\begin{align}|x\end{equation}]])
eq(core.find_pair("e", mismatched), nil, "mismatched environment names are not removable")

for _, case in ipairs({
	{ [[$\left( |x \right)$]], " x ", [[\left( x \right)]] },
	{ [=[$\bigl[|x\bigr]$]=], "x", [=[\bigl[x\bigr]]=] },
	{ [[$\left. |x \right|$]], " x ", [[\left. x \right|]] },
	{ [[$\langle |x\rangle$]], " x", [[\langle x\rangle]] },
	{ [[$\{|x\}$]], "x", [[\{x\}]] },
	{ [[$(|x)$]], "x", "(x)" },
	{ [[$\left( |x$]], nil, nil },
	{ [[$\left( |x\right$]], nil, nil },
}) do
	local query = fixture(case[1])
	eq(text(query, core.find("d", query)), case[2], "inside delimiters: " .. case[1])
	query.inner = false
	eq(text(query, core.find("d", query)), case[3], "around delimiters: " .. case[1])
end
local nested_delimiters = fixture([[$(\langle |x\rangle)$]])
nested_delimiters.count = 2
eq(text(nested_delimiters, core.find("d", nested_delimiters)), [[\langle x\rangle]], "delimiter count")
local section = fixture(
	"\\begin{document}\n\\section{A}\n|first\n\n\\subsection{B}\nsecond\n\n\\section{C}\nthird\n\\end{document}"
)
eq(text(section, core.find("S", section)), "first\n\n\\subsection{B}\nsecond", "section includes subsections")
section.inner = false
eq(
	text(section, core.find("S", section)),
	"\\section{A}\nfirst\n\n\\subsection{B}\nsecond\n\n",
	"section around stops at sibling"
)
local subsection = fixture("\\section{A}\none\n\\subsection[short]{B}\n|two\n\n\\section*{C}\nthree")
eq(text(subsection, core.find("S", subsection)), "two", "subsection body excludes heading/options")
subsection.count = 2
eq(text(subsection, core.find("S", subsection)), "one\n\\subsection[short]{B}\ntwo", "section count")
local separator = fixture("\\section{A}\none\n|\n\\section{B}\ntwo")
eq(text(separator, core.find("S", separator)), "one", "section includes trailing separator in lookup")
local item = fixture("\\begin{itemize}\n  \\item[label] |first\n\n  \\item second\n\\end{itemize}")
eq(text(item, core.find("i", item)), "first", "item body excludes label")
item.inner = false
eq(text(item, core.find("i", item)), "  \\item[label] first\n\n", "around item includes indentation and separator")
local nested_item = fixture(
	"\\begin{itemize}\n\\item outer\n\\begin{enumerate}\n\\item |inner\n\\end{enumerate}\n\\item next\n\\end{itemize}"
)
eq(text(nested_item, core.find("i", nested_item)), "inner", "nested item body")
nested_item.count = 2
eq(
	text(nested_item, core.find("i", nested_item)),
	"outer\n\\begin{enumerate}\n\\item inner\n\\end{enumerate}",
	"nested item count"
)

for _, case in ipairs({
	{ [[\textbf{|hello}]], "textbf", [[\textbf{hello}]], true, "hello" },
	{ [[\sqrt[3]{|x}]], "sqrt", [[\sqrt[3]{x}]], true, "x" },
	{ [[\frac{|a}{b}]], "frac", [[\frac{a}{b}]], false },
	{ [[\frac{|a}]], "frac", [[\frac{a}]], false },
	{ [[\al|pha]], "alpha", [[\alpha]], false },
	{ [[\sqrt |x]], "sqrt", [[\sqrt x]], false },
	{ [[\sqrt{|}]], "sqrt", [[\sqrt{}]], true, "" },
	{ [[\sqrt{|x]], nil, nil, false },
}) do
	local query = fixture(case[1])
	eq(text(query, core.find("c", query)), case[2], "command inside: " .. case[1])
	query.inner = false
	eq(text(query, core.find("c", query)), case[3], "command around: " .. case[1])
	local pair = core.find_pair("c", query)
	eq(pair ~= nil, case[4], "command surround capability: " .. case[1])
	if pair then
		eq(
			text(query, { pair.inner_start[1], pair.inner_start[2], pair.inner_end[1], pair.inner_end[2] }),
			case[5],
			"surround retains argument contents independently of the command name"
		)
	end
end
local wrappers = fixture([[\mathrm{\sqrt{|x}}]])
wrappers.count = 2
local layers = {}
local outer_pair = assert(core.find_pair("c", wrappers, function(pair)
	layers[#layers + 1] = pair
end))
eq(#layers, 2, "pair finder reports intermediate layers for groups")
eq(outer_pair, layers[2], "pair count returns outer wrapper")

local markdown = fixture([[text $\frac{|a}{b}$ tail]], "markdown")
eq(text(markdown, core.find("a", markdown)), "a", "core finds LaTeX injections in hidden Markdown buffers")
markdown.inner = false
eq(text(markdown, core.find("m", markdown)), [[$\frac{a}{b}$]], "Markdown around math")

local nested = fixture([[\begin{equation}\begin{aligned}|x\end{aligned}\end{equation}]])
nested.count, nested.inner = 2, false
eq(
	text(nested, core.find("e", nested)),
	[[\begin{equation}\begin{aligned}x\end{aligned}\end{equation}]],
	"environment count"
)

eq(vim.api.nvim_buf_get_lines(current, 0, -1, false), { "" }, "current buffer remains untouched")
eq(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false), content, "source buffer remains untouched")
print("ok textobject core ranges, nesting, counts, references, and Markdown")
