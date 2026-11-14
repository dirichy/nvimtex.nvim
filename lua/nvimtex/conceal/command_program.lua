local Render = require("nvimtex.conceal.render_tree")
local parser = require("nvimtex.parser")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local Command = require("nvimtex.conceal.command")

local M = {}

-- Opcodes are numeric because programs are compact flat arrays on a hot path.
local OP_CONSTANT = 1
local OP_ARGUMENT = 2
local OP_CALL = 3
local OP_CONCAT = 4
local OP_ABSENT = 5
local OP_FAILURE = 6

---@class Nvimtex.CommandProgram
---@field operators any[] postfix instructions followed by their operands
local Program = {}
Program.__index = Program

---Append an opcode and its inline operands to the flat program.
---@param program any[]
---@param ... any
local function append(program, ...)
	for index = 1, select("#", ...) do
		program[#program + 1] = select(index, ...)
	end
end

---@alias Nvimtex.CommandResolver fun(name:string?):Nvimtex.RenderSpec|Nvimtex.Renderer|nil

---@type fun(node:Nvimtex.LNode,source:number|string,resolve:Nvimtex.CommandResolver,program:any[])
local compile_node

---Compile children first, then append one CONCAT for their stack results.
---@param nodes Nvimtex.LNode[]
---@param source number|string
---@param resolve Nvimtex.CommandResolver
---@param program any[]
local function compile_sequence(nodes, source, resolve, program)
	for _, node in ipairs(nodes) do
		compile_node(node, source, resolve, program)
	end
	if #nodes > 1 then
		append(program, OP_CONCAT, #nodes)
	elseif #nodes == 0 then
		append(program, OP_CONSTANT, "")
	end
end

---@param node Nvimtex.LNode
---@param source number|string
---@param resolve Nvimtex.CommandResolver
---@param program any[]
local function compile_argument(node, source, resolve, program)
	if latex_nodes.group_delimiters(node) then
		compile_sequence(parser.content_nodes(node, source), source, resolve, program)
	else
		compile_node(node, source, resolve, program)
	end
end

---Compile the shared argument layout, retaining empty optional slots on the stack.
---@param node Nvimtex.LNode
---@param source number|string
---@param spec Nvimtex.RenderSpec|Nvimtex.Renderer
---@param resolve Nvimtex.CommandResolver
---@param program any[]
local function compile_call(node, source, spec, resolve, program)
	if type(spec) == "function" then
		spec = { render = spec }
	end
	if spec.narg and #latex_nodes.arguments(node) ~= spec.narg then
		append(program, OP_FAILURE)
		return
	end
	local argument_nodes, count = parser.command_arguments(node, spec.optional)
	for index = 1, count do
		local argument = argument_nodes[index]
		if argument then
			compile_argument(argument, source, resolve, program)
		else
			append(program, OP_ABSENT)
		end
	end
	append(program, OP_CALL, { spec = spec, node = node, argument_nodes = argument_nodes }, count)
end

---Compile one syntax node into postfix instructions.
---@param node Nvimtex.LNode
---@param source number|string
---@param resolve Nvimtex.CommandResolver
---@param program any[]
function compile_node(node, source, resolve, program)
	local node_type = node:type()
	if node_type == "line_comment" then
		append(program, OP_CONSTANT, "")
		return
	end
	if node_type == "placeholder" then
		-- Runtime arguments replace `#1`, `#2`, ... without reparsing the body.
		local index = tonumber(vim.treesitter.get_node_text(node, source):match("%d+"))
		append(program, OP_ARGUMENT, index or 0)
		return
	end
	if node_type == "generic_command" then
		local spec = resolve(latex_nodes.command_name(source, node))
		if spec then
			compile_call(node, source, spec, resolve, program)
		else
			append(program, OP_FAILURE)
		end
		return
	end
	if Command.scripts[node_type] then
		local argument = latex_nodes.script_argument(node)
		if not argument then
			append(program, OP_FAILURE)
			return
		end
		compile_argument(argument, source, resolve, program)
		append(program, OP_CALL, {
			node = node,
			argument_nodes = { argument },
			spec = Command.scripts[node_type],
		}, 1)
		return
	end
	if node_type == "if_statement" then
		local block = latex_nodes.branch(node)
		compile_sequence(block and parser.content_nodes(block, source) or {}, source, resolve, program)
		return
	end
	if node:child_count() == 0 then
		-- Preserve literal words and operators as generated display text.
		append(program, OP_CONSTANT, vim.treesitter.get_node_text(node, source))
		return
	end
	local children = parser.content_nodes(node, source)
	if #children == 0 and not node_type:match("group") then
		append(program, OP_CONSTANT, vim.treesitter.get_node_text(node, source))
	else
		compile_sequence(children, source, resolve, program)
	end
end

---Compile a newcommand implementation into a compact postfix operator table.
---@param node Nvimtex.LNode
---@param source number|string
---@param resolve Nvimtex.CommandResolver
---@return Nvimtex.CommandProgram
function M.compile(node, source, resolve)
	local operators = {}
	compile_node(node, source, resolve, operators)
	return setmetatable({ operators = operators }, Program)
end

---@class Nvimtex.CommandProgram.Context
---@field node Nvimtex.LNode invocation or definition anchor node
---@field source number|string
---@field anchor_row? integer
---@field anchor_col? integer
---@field depth? integer nested program depth, including optional defaults

---Generated constants are zero-width inserts owned by the eventual atomic call.
---@param text string
---@param context Nvimtex.CommandProgram.Context
---@return Nvimtex.RenderTree
local function generated_text(text, context)
	local row, col = context.anchor_row, context.anchor_col
	if row == nil then
		row, col = context.node:start()
	end
	return Render.text(text, row, col, Render.mode.insert)
end

---Pop in source order. OP_ABSENT uses false so the stack stays dense; only
---the renderer's argument array converts that sentinel back into a nil slot.
---@param stack (Nvimtex.RenderTree|false)[]
---@param count integer
---@return table<integer,Nvimtex.RenderTree>
local function pop_arguments(stack, count)
	local first = #stack - count + 1
	local values = {}
	for index = count, 1, -1 do
		local stack_index = first + index - 1
		values[index] = stack[stack_index] or nil
		stack[stack_index] = nil
	end
	return values
end

---@class Nvimtex.CommandProgram.Call
---@field spec Nvimtex.RenderSpec
---@field node Nvimtex.LNode definition node providing generated syntax anchors
---@field argument_nodes table<integer,Nvimtex.LNode> sparse optional-first layout

---Execute the postfix VM. Returning nil propagates a nested renderer failure.
---@param arguments table<integer,Nvimtex.RenderTree> optional slot may be absent
---@param context Nvimtex.CommandProgram.Context
---@return Nvimtex.RenderTree?
function Program:execute(arguments, context)
	local depth = (context.depth or 0) + 1
	if depth > 32 then
		return nil
	end
	---@type (Nvimtex.RenderTree|false)[]
	local stack = {}
	local operators = self.operators
	local pc = 1
	while pc <= #operators do
		local operation = operators[pc]
		pc = pc + 1
		if operation == OP_CONSTANT then
			stack[#stack + 1] = generated_text(operators[pc], context)
			pc = pc + 1
		elseif operation == OP_ARGUMENT then
			local argument = arguments[operators[pc]]
			if not argument then
				return nil
			end
			stack[#stack + 1] = argument
			pc = pc + 1
		elseif operation == OP_ABSENT then
			stack[#stack + 1] = false
		elseif operation == OP_FAILURE then
			return nil
		elseif operation == OP_CALL then
			---@type Nvimtex.CommandProgram.Call
			local call = operators[pc]
			local count = operators[pc + 1]
			pc = pc + 2
			local values = pop_arguments(stack, count)
			local call_context = {
				node = call.node,
				source = context.source,
				argument_nodes = call.argument_nodes,
				argument_count = count,
				anchor_row = context.anchor_row,
				anchor_col = context.anchor_col,
				depth = depth,
			}
			if not Command.apply_default(values, call.spec, call_context) then
				return nil
			end
			local value = call.spec.render(values, call_context)
			if not value then
				return nil
			end
			stack[#stack + 1] = value
		elseif operation == OP_CONCAT then
			local count = operators[pc]
			pc = pc + 1
			local values = pop_arguments(stack, count)
			stack[#stack + 1] = Render.concat_many(values)
		end
	end
	assert(#stack == 1, "command program left an invalid stack")
	return stack[1]
end

M.Program = Program
return M
