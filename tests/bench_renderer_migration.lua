vim.opt.runtimepath:prepend(vim.fn.getcwd())

local State = require("nvimtex.conceal.state")
local old = require("nvimtex.conceal.concealer")
local new = require("nvimtex.conceal.renderer")
local parser = require("nvimtex.parser")
local Inline = require("nvimtex.conceal.inline")
local Render = require("nvimtex.conceal.render_tree")

local function parse(source)
	return vim.treesitter.get_string_parser(source, "latex"):parse()[1]:root()
end

local function find(node, source, node_type, command_name)
	if node:type() == node_type then
		if not command_name then
			return node
		end
		local command = node:field("command")[1]
		if command and vim.treesitter.get_node_text(command, source):sub(2) == command_name then
			return node
		end
	end
	for child in parser.iter_children(node, source) do
		local result = find(child, source, node_type, command_name)
		if result then
			return result
		end
	end
end

local function time(iterations, fn)
	collectgarbage("collect")
	local started = vim.uv.hrtime()
	for _ = 1, iterations do
		fn()
	end
	return (vim.uv.hrtime() - started) / 1e6
end

local function sample(label, iterations, old_fn, new_fn)
	-- Warm both Lua paths and tree-sitter node text caches.
	for _ = 1, 100 do
		old_fn()
		new_fn()
	end
	local old_ms = time(iterations, old_fn)
	local new_ms = time(iterations, new_fn)
	local ratio = new_ms / old_ms
	print(string.format("%-30s old %8.3f ms  new %8.3f ms  new/old %5.2fx", label, old_ms, new_ms, ratio))
end

local iterations = tonumber(vim.env.NVIMTEX_BENCH_N) or 1000

local concat_iterations = math.max(1, math.floor(iterations / 100))
local atom_count = 1000

local function compare_append_concat_many(label, count, count_iterations)
	sample(label, count_iterations, function()
		local result = Inline:new("")
		for _ = 1, count do
			result:append({ "x", "Normal" })
		end
		return result
	end, function()
		local values = {}
		for index = 1, count do
			values[index] = Render.text("x", 0, index)
		end
		return Render.concat_many(values)
	end)
end

compare_append_concat_many("append/concat_many 20", 20, iterations)
compare_append_concat_many("append/concat_many 1000", atom_count, concat_iterations)

sample("immutable + 1000 atoms", concat_iterations, function()
	local result = Inline:new("")
	for _ = 1, atom_count do
		result = result + Inline:new("x", false)
	end
	return result
end, function()
	local result = Render.empty()
	for index = 1, atom_count do
		result = result + Render.text("x", 0, index)
	end
	return result
end)

sample("mutable append / tree +", concat_iterations, function()
	local result = Inline:new("")
	for _ = 1, atom_count do
		result:append({ "x", "Normal" })
	end
	return result
end, function()
	local result = Render.empty()
	for index = 1, atom_count do
		result = result + Render.text("x", 0, index)
	end
	return result
end)

local concat_values = {}
for index = 1, atom_count do
	concat_values[index] = Render.text("x", 0, index)
end
local deep_tree = Render.empty()
for _, value in ipairs(concat_values) do
	deep_tree = deep_tree + value
end
local wide_tree = Render.concat_many(concat_values)
local deep_ms = time(iterations, function()
	deep_tree:to_virt_text()
end)
local wide_ms = time(iterations, function()
	wide_tree:to_virt_text()
end)
print(
	string.format(
		"%-30s deep %7.3f ms  wide %7.3f ms  wide/deep %5.2fx",
		"flatten 1000 atoms",
		deep_ms,
		wide_ms,
		wide_ms / deep_ms
	)
)

local frac_source = "\\frac{abcdefgh}{ijklmnop}"
local frac = assert(find(parse(frac_source), frac_source, "generic_command", "frac"))
sample("render frac", iterations, function()
	old.default_concealer(frac, frac_source, State:new())
end, function()
	new.render_node(frac, frac_source, State:new())
end)

local style_source = "\\mathbb{ABCDEFGHIJKLMNOPQRSTUVWXYZ}"
local style = assert(find(parse(style_source), style_source, "generic_command", "mathbb"))
sample("render mathbb", iterations, function()
	old.default_concealer(style, style_source, State:new())
end, function()
	new.render_node(style, style_source, State:new())
end)

local nested_source = "\\frac{\\frac{a}{b}+\\frac{c}{d}}{\\sqrt{x}+\\mathbb{R}}"
local nested = assert(find(parse(nested_source), nested_source, "generic_command", "frac"))
sample("render nested", iterations, function()
	old.default_concealer(nested, nested_source, State:new())
end, function()
	new.render_node(nested, nested_source, State:new())
end)

local function extmark_sample(label, source, node, old_render, new_render)
	local buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { source })
	local old_namespace = vim.api.nvim_create_namespace("nvimtex.bench.old." .. label)
	local new_namespace = vim.api.nvim_create_namespace("nvimtex.bench.new." .. label)
	local old_result = old_render()
	local new_result = new_render()
	local old_ms = time(iterations, function()
		old_result:conceal(buffer, node, old_namespace)
	end)
	local new_ms = time(iterations, function()
		new_result:emit_extmarks(buffer, new_namespace)
	end)
	local old_count = #vim.api.nvim_buf_get_extmarks(buffer, old_namespace, 0, -1, {})
	local new_count = #vim.api.nvim_buf_get_extmarks(buffer, new_namespace, 0, -1, {})
	print(
		string.format(
			"%-30s old %8.3f ms (%d marks) new %8.3f ms (%d marks) new/old %5.2fx",
			"extmarks " .. label,
			old_ms,
			old_count,
			new_ms,
			new_count,
			new_ms / old_ms
		)
	)
	vim.api.nvim_buf_delete(buffer, { force = true })
end

extmark_sample("frac", frac_source, frac, function()
	return old.default_concealer(frac, frac_source, State:new())
end, function()
	return new.render_node(frac, frac_source, State:new())
end)
