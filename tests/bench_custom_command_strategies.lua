vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.swapfile = false

local uv = vim.uv or vim.loop
local parser_module = require("nvimtex.parser")

local OP_CONST = 1
local OP_ARG = 2
local OP_CALL = 3
local OP_CONCAT = 4

local function letters(number)
	local result = {}
	repeat
		result[#result + 1] = string.char(97 + number % 26)
		number = math.floor(number / 26) - 1
	until number < 0
	local reversed = {}
	for index = #result, 1, -1 do
		reversed[#reversed + 1] = result[index]
	end
	return table.concat(reversed)
end

local lines = { "% nvimtex: enable_parser_command_definition" }
for index = 1, 1000 do
	lines[#lines + 1] = string.format("\\newcommand{\\bench%s}[2]{A\\frac{\\mathbb{#1}}{\\sqrt{#2}}B}", letters(index))
end
local source = table.concat(lines, "\n")

local parse_started = uv.hrtime()
local tree = vim.treesitter.get_string_parser(source, "latex"):parse()[1]
local parse_ms = (uv.hrtime() - parse_started) / 1e6

local definitions = {}
local function collect(node)
	if node:type() == "new_command_definition" then
		definitions[#definitions + 1] = node
		return
	end
	for child in node:iter_children() do
		collect(child)
	end
end
collect(tree:root())
assert(#definitions == 1000, string.format("expected 1000 definitions, got %d", #definitions))

local renderers = {
	frac = function(args)
		return "(" .. args[1] .. ")/(" .. args[2] .. ")"
	end,
	mathbb = function(args)
		return "bb(" .. args[1] .. ")"
	end,
	sqrt = function(args)
		return "sqrt(" .. args[1] .. ")"
	end,
}

local function node_text(node)
	return vim.treesitter.get_node_text(node, source)
end

local function command_name(node)
	local command = node:field("command")[1]
	return command and node_text(command):sub(2) or nil
end

local function content_nodes(node)
	local children = {}
	for child in parser_module.iter_children(node, source) do
		local node_type = child:type()
		if node_type ~= "{" and node_type ~= "}" and node_type ~= "[" and node_type ~= "]" then
			children[#children + 1] = child
		end
	end
	return children
end

local function concatenate(values)
	return table.concat(values)
end

local interpret_node
local function interpret_sequence(nodes, args)
	local values = {}
	for index, node in ipairs(nodes) do
		values[index] = interpret_node(node, args)
	end
	return concatenate(values)
end

function interpret_node(node, args)
	local node_type = node:type()
	if node_type == "placeholder" then
		return args[tonumber(node_text(node):match("%d+"))] or ""
	end
	if node_type == "generic_command" then
		local renderer = renderers[command_name(node)]
		if not renderer then
			return node_text(node)
		end
		local rendered_args = {}
		for index, arg in ipairs(node:field("arg")) do
			rendered_args[index] = interpret_sequence(content_nodes(arg), args)
		end
		return renderer(rendered_args)
	end
	if node:child_count() == 0 then
		return node_text(node)
	end
	return interpret_sequence(content_nodes(node), args)
end

local compile_closure_node
local function compile_closure_sequence(nodes)
	local children = {}
	for index, node in ipairs(nodes) do
		children[index] = compile_closure_node(node)
	end
	if #children == 1 then
		return children[1]
	end
	return function(args)
		local values = {}
		for index, child in ipairs(children) do
			values[index] = child(args)
		end
		return concatenate(values)
	end
end

function compile_closure_node(node)
	local node_type = node:type()
	if node_type == "placeholder" then
		local index = tonumber(node_text(node):match("%d+"))
		return function(args)
			return args[index] or ""
		end
	end
	if node_type == "generic_command" then
		local renderer = renderers[command_name(node)]
		if not renderer then
			local text = node_text(node)
			return function()
				return text
			end
		end
		local compiled_args = {}
		for index, arg in ipairs(node:field("arg")) do
			compiled_args[index] = compile_closure_sequence(content_nodes(arg))
		end
		return function(args)
			local values = {}
			for index, compiled_arg in ipairs(compiled_args) do
				values[index] = compiled_arg(args)
			end
			return renderer(values)
		end
	end
	if node:child_count() == 0 then
		local text = node_text(node)
		return function()
			return text
		end
	end
	return compile_closure_sequence(content_nodes(node))
end

local compile_ir_node
local function compile_ir_sequence(nodes)
	local children = {}
	for index, node in ipairs(nodes) do
		children[index] = compile_ir_node(node)
	end
	return { "sequence", children }
end

function compile_ir_node(node)
	local node_type = node:type()
	if node_type == "placeholder" then
		return { "argument", tonumber(node_text(node):match("%d+")) }
	end
	if node_type == "generic_command" then
		local renderer = renderers[command_name(node)]
		if not renderer then
			return { "constant", node_text(node) }
		end
		local compiled_args = {}
		for index, arg in ipairs(node:field("arg")) do
			compiled_args[index] = compile_ir_sequence(content_nodes(arg))
		end
		return { "call", renderer, compiled_args }
	end
	if node:child_count() == 0 then
		return { "constant", node_text(node) }
	end
	return compile_ir_sequence(content_nodes(node))
end

local function execute_ir(node, args)
	local operation = node[1]
	if operation == "argument" then
		return args[node[2]] or ""
	elseif operation == "constant" then
		return node[2]
	elseif operation == "sequence" then
		local values = {}
		for index, child in ipairs(node[2]) do
			values[index] = execute_ir(child, args)
		end
		return concatenate(values)
	elseif operation == "call" then
		local values = {}
		for index, child in ipairs(node[3]) do
			values[index] = execute_ir(child, args)
		end
		return node[2](values)
	end
end

local compile_flat_node
local function emit(program, ...)
	for index = 1, select("#", ...) do
		program[#program + 1] = select(index, ...)
	end
end

local function compile_flat_sequence(nodes, program)
	for _, node in ipairs(nodes) do
		compile_flat_node(node, program)
	end
	if #nodes > 1 then
		emit(program, OP_CONCAT, #nodes)
	end
end

function compile_flat_node(node, program)
	local node_type = node:type()
	if node_type == "placeholder" then
		emit(program, OP_ARG, tonumber(node_text(node):match("%d+")))
		return
	end
	if node_type == "generic_command" then
		local renderer = renderers[command_name(node)]
		if not renderer then
			emit(program, OP_CONST, node_text(node))
			return
		end
		local argc = 0
		for _, arg in ipairs(node:field("arg")) do
			compile_flat_sequence(content_nodes(arg), program)
			argc = argc + 1
		end
		emit(program, OP_CALL, renderer, argc)
		return
	end
	if node:child_count() == 0 then
		emit(program, OP_CONST, node_text(node))
		return
	end
	compile_flat_sequence(content_nodes(node), program)
end

local function execute_flat(program, args)
	local stack = {}
	local pc = 1
	while pc <= #program do
		local operation = program[pc]
		pc = pc + 1
		if operation == OP_CONST then
			stack[#stack + 1] = program[pc]
			pc = pc + 1
		elseif operation == OP_ARG then
			stack[#stack + 1] = args[program[pc]] or ""
			pc = pc + 1
		elseif operation == OP_CALL then
			local renderer = program[pc]
			local argc = program[pc + 1]
			pc = pc + 2
			local first = #stack - argc + 1
			local values = {}
			for index = 1, argc do
				values[index] = stack[first + index - 1]
			end
			for index = #stack, first, -1 do
				stack[index] = nil
			end
			stack[#stack + 1] = renderer(values)
		elseif operation == OP_CONCAT then
			local count = program[pc]
			pc = pc + 1
			local first = #stack - count + 1
			local values = {}
			for index = 1, count do
				values[index] = stack[first + index - 1]
			end
			for index = #stack, first, -1 do
				stack[index] = nil
			end
			stack[#stack + 1] = concatenate(values)
		end
	end
	return stack[1]
end

local implementations = {}
for index, definition in ipairs(definitions) do
	implementations[index] = definition:field("implementation")[1]
end

local function compile_current()
	local result = {}
	for index, implementation in ipairs(implementations) do
		result[index] = implementation
	end
	return result
end

local function compile_closures()
	local result = {}
	for index, implementation in ipairs(implementations) do
		result[index] = compile_closure_node(implementation)
	end
	return result
end

local function compile_ir()
	local result = {}
	for index, implementation in ipairs(implementations) do
		result[index] = compile_ir_node(implementation)
	end
	return result
end

local function compile_flat()
	local result = {}
	for index, implementation in ipairs(implementations) do
		local program = {}
		compile_flat_node(implementation, program)
		result[index] = program
	end
	return result
end

local function measure_compile(name, compile, rounds)
	local samples = {}
	local retained
	for round = 1, rounds do
		retained = nil
		collectgarbage("collect")
		local before_memory = collectgarbage("count")
		local started = uv.hrtime()
		retained = compile()
		local elapsed = (uv.hrtime() - started) / 1e6
		local after_memory = collectgarbage("count")
		samples[round] = { elapsed, after_memory - before_memory }
	end
	table.sort(samples, function(left, right)
		return left[1] < right[1]
	end)
	local middle = samples[math.ceil(#samples / 2)]
	print(string.format("compile %-12s median=%8.3f ms  retained≈%8.1f KiB", name, middle[1], middle[2]))
	return compile()
end

local function measure_execute(name, compiled, execute, rounds)
	local args = { "x", "y" }
	local expected = "A(bb(x))/(sqrt(y))B"
	local samples = {}
	local checksum = 0
	for round = 1, rounds do
		local started = uv.hrtime()
		for index = 1, #compiled do
			local value = execute(compiled[index], args)
			checksum = checksum + #value
			if round == 1 and value ~= expected then
				error(string.format("%s produced %q, expected %q", name, value, expected))
			end
		end
		samples[round] = (uv.hrtime() - started) / 1e6
	end
	table.sort(samples)
	print(
		string.format(
			"render  %-12s median=%8.3f ms / 1000 calls  checksum=%d",
			name,
			samples[math.ceil(#samples / 2)],
			checksum
		)
	)
end

print(string.format("Tree-sitter parse: %.3f ms; definitions: %d", parse_ms, #definitions))
local current = measure_compile("current", compile_current, 9)
local closures = measure_compile("closures", compile_closures, 9)
local ir = measure_compile("tree IR", compile_ir, 9)
local flat = measure_compile("flat VM", compile_flat, 9)

measure_execute("current", current, interpret_node, 30)
measure_execute("closures", closures, function(render, args)
	return render(args)
end, 30)
measure_execute("tree IR", ir, execute_ir, 30)
measure_execute("flat VM", flat, execute_flat, 30)
