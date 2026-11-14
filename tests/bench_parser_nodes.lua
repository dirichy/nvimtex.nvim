-- Run each revision in its own process. Point NVIMTEX_BENCH_ROOT at a checkout
-- to compare it with the same fixture and benchmark script.
vim.opt.runtimepath:prepend(vim.env.NVIMTEX_BENCH_ROOT or vim.fn.getcwd())
local parser = require("nvimtex.parser")
local renderer = require("nvimtex.conceal.renderer")
local sources = {
	[[$\frac{\alpha+x_i}{\sqrt{1+x^2}}$]],
	[[$\mathbb{R}+\frac12$]],
	[[$\norm{x}_2+\abs{x-y}+\binom{n}{k}$]],
}
local cases = {}
for _, source in ipairs(sources) do
	local root = vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { source })
	cases[#cases + 1] = { root = root, source = source, buf = buf }
end
local namespace = vim.api.nvim_create_namespace("nvimtex-nofield-bench")
local function walk(node, source)
	local count = 1
	for child in parser.iter_children(node, source) do
		count = count + walk(child, source)
	end
	return count
end
local function measure(name, rounds, fn)
	for _ = 1, 50 do
		for _, case in ipairs(cases) do
			fn(case)
		end
	end
	collectgarbage("collect")
	local started = vim.uv.hrtime()
	for _ = 1, rounds do
		for _, case in ipairs(cases) do
			fn(case)
		end
	end
	print(name, string.format("%.2f us/formula", (vim.uv.hrtime() - started) / 1000 / rounds / #cases))
end
local count = 0
for _, case in ipairs(cases) do
	count = count + walk(case.root, case.source)
end
print("node checksum", count)
local build_iterations = tonumber(vim.env.NVIMTEX_BENCH_N) or 3000
local emit_iterations = tonumber(vim.env.NVIMTEX_BENCH_EMIT_N) or 1000
measure("parser walk", build_iterations, function(case)
	return walk(case.root, case.source)
end)
measure("render build", build_iterations, function(case)
	return renderer.render_node(case.root, case.source)
end)
measure("build + emit", emit_iterations, function(case)
	vim.api.nvim_buf_clear_namespace(case.buf, namespace, 0, -1)
	renderer.render_node(case.root, case.source):emit_extmarks(case.buf, namespace)
end)
