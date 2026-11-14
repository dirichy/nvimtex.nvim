vim.opt.runtimepath:prepend(vim.fn.getcwd())

local renderer = require("nvimtex.conceal.renderer")
local parser = require("nvimtex.parser")
local symbols = require("nvimtex.conceal.command_name")

local sources = {
	"$a+b=c$",
	"$\\frac{\\alpha+x_i}{\\sqrt{1+x^2}}$",
	"\\[\\sum_{i=1}^n i^2=\\frac{n(n+1)(2n+1)}{6}\\]",
	"\\[\\int_0^\\infty e^{-x^2}\\,dx=\\frac{\\sqrt{\\pi}}{2}\\]",
	"$A=\\begin{pmatrix}a&b\\\\c&d\\end{pmatrix}$",
	"\\begin{align}f(x)&=x^2+2x+1\\\\g(x)&=\\frac{1}{1+x^2}\\end{align}",
	"$\\norm{x}_2+\\abs{x-y}\\leq\\sqrt{2}$",
	"$\\mathbb{R}^n\\to\\mathcal{F}(X),\\quad x\\mapsto f_x$",
}

local math_types = { inline_formula = true, displayed_equation = true, math_environment = true }

local function find_math(node, source)
	if math_types[node:type()] then
		return node
	end
	for child in parser.iter_children(node, source) do
		local found = find_math(child, source)
		if found then
			return found
		end
	end
end

local function command_name(node, source)
	local command = node:field("command")[1]
	return command and vim.treesitter.get_node_text(command, source):sub(2) or nil
end

-- Reproduce the old processor ownership rule: render a recognized command or
-- script and stop descending into that node; otherwise continue traversal.
local function old_targets(node, source, result)
	local node_type = node:type()
	if node_type == "generic_command" then
		local name = command_name(node, source)
		if renderer.command_specs[name] or symbols[name] then
			result[#result + 1] = node
			return
		end
	elseif
		node_type == "subscript"
		or node_type == "superscript"
		or node_type == "\\("
		or node_type == "\\)"
		or node_type == "\\["
		or node_type == "\\]"
	then
		result[#result + 1] = node
		return
	end
	for child in parser.iter_children(node, source) do
		old_targets(child, source, result)
	end
end

local cases = {}
for _, source in ipairs(sources) do
	local root = vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
	local math = assert(find_math(root, source), "benchmark source has no math root")
	local targets = {}
	old_targets(math, source, targets)
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(source, "\n", { plain = true }))
	cases[#cases + 1] = { source = source, math = math, targets = targets, buffer = buffer }
end

local function measure(iterations, callback)
	collectgarbage("collect")
	local start = vim.uv.hrtime()
	for _ = 1, iterations do
		for _, case in ipairs(cases) do
			callback(case)
		end
	end
	return (vim.uv.hrtime() - start) / 1e6
end

local build_iterations = tonumber(vim.env.NVIMTEX_BENCH_BUILD_ITERATIONS) or 5000
local old_build = measure(build_iterations, function(case)
	local targets = {}
	old_targets(case.math, case.source, targets)
	for _, node in ipairs(targets) do
		renderer.render_node(node, case.source)
	end
end)
local whole_build = measure(build_iterations, function(case)
	renderer.render_node(case.math, case.source)
end)

local namespace = vim.api.nvim_create_namespace("nvimtex_bench_math_scope")
local emit_iterations = tonumber(vim.env.NVIMTEX_BENCH_EMIT_ITERATIONS) or 500
local old_emit = measure(emit_iterations, function(case)
	vim.api.nvim_buf_clear_namespace(case.buffer, namespace, 0, -1)
	local targets = {}
	old_targets(case.math, case.source, targets)
	for _, node in ipairs(targets) do
		renderer.render_node(node, case.source):emit_extmarks(case.buffer, namespace)
	end
end)
local whole_emit = measure(emit_iterations, function(case)
	vim.api.nvim_buf_clear_namespace(case.buffer, namespace, 0, -1)
	renderer.render_node(case.math, case.source):emit_extmarks(case.buffer, namespace)
end)

local function report(name, old, whole, iterations)
	local samples = iterations * #cases
	print(
		string.format(
			"%-13s old=%8.2f ms (%6.2f us/formula)  whole=%8.2f ms (%6.2f us/formula)  whole/old=%.3fx",
			name,
			old,
			old * 1000 / samples,
			whole,
			whole * 1000 / samples,
			whole / old
		)
	)
end

print(string.format("math render scope benchmark: %d formulas", #cases))
report("build", old_build, whole_build, build_iterations)
report("build+emit", old_emit, whole_emit, emit_iterations)
