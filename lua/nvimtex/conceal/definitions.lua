local parser = require("nvimtex.parser")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local renderer = require("nvimtex.conceal.renderer")
local Program = require("nvimtex.conceal.command_program")

local M = {}

---@class Nvimtex.DocumentRenderSpec: Nvimtex.RenderSpec
---@field implementation Nvimtex.LNode
---@field default_node? Nvimtex.LNode
---@field program? Nvimtex.CommandProgram assigned after all signatures are collected

---Validate one definition and register its signature before compiling any body.
---@param node Nvimtex.LNode
---@param source integer buffer id
local function register_definition(node, source)
	local declaration = node:field("declaration")[1]
	local command = declaration and declaration:field("command")[1]
	local implementation = node:field("implementation")[1]
	if not command or not implementation then
		return
	end
	local argc_node = node:field("argc")[1]
	local argc = 0
	if argc_node then
		argc = tonumber(vim.treesitter.get_node_text(argc_node, source):sub(2, -2))
	end
	if not argc or argc % 1 ~= 0 or argc < 0 or argc > 9 then
		return
	end
	local default = node:field("default")[1]
	local required_count = argc - (default and 1 or 0)
	if required_count < 0 then
		return
	end
	local name = latex_nodes.command_name(source, command)
	parser.buffer_command_specs[source][name] = { narg = required_count, oarg = default ~= nil }
	---@type Nvimtex.DocumentRenderSpec
	local spec = {
		narg = required_count,
		optional = default ~= nil,
		atomic = true,
		reveal_on_failure = true,
		implementation = implementation,
		default_node = default,
	}
	spec.render = function(args, context)
		if not spec.program then
			return nil
		end
		local row, col = context.node:start()
		return spec.program:execute(args, {
			node = context.node,
			source = source,
			anchor_row = row,
			anchor_col = col,
			depth = context.depth,
		})
	end
	renderer.register_buffer_command(source, name, spec)
end

---Replace this buffer's definitions. Body edits do not require this scan.
---Signatures are collected first so bodies can call later definitions.
---@param root Nvimtex.LNode
---@param source integer buffer id
---@param document? Nvimtex.LNode
function M.scan(root, source, document)
	document = document or latex_nodes.find_document(root, source)
	parser.buffer_command_specs[source] = {}
	renderer.buffer_commands[source] = {}
	local document_row = document and document:start() or math.huge
	local enabled = false

	-- Definition bodies are opaque during collection: comments inside a macro
	-- must not change the directives controlling subsequent definitions.
	local function collect(node)
		local node_type = node:type()
		if node_type == "line_comment" then
			local text = vim.treesitter.get_node_text(node, source)
			local directive = text:match("^%%%s*nvimtex:%s*(%S*)%s*$")
			if directive then
				if directive:match("^enable_parser_command_definition") then
					enabled = true
				elseif directive:match("^disable_parser_command_definition") then
					enabled = false
				end
			end
		elseif node_type == "new_command_definition" then
			if enabled then
				register_definition(node, source)
			end
		else
			for child in parser.iter_children(node, source) do
				collect(child)
			end
		end
	end
	for node in parser.iter_children(root, source) do
		if node:start() >= document_row then
			break
		end
		collect(node)
	end

	local function resolve(name)
		return renderer.program_spec(name, source)
	end
	---@type table<string,Nvimtex.DocumentRenderSpec>
	local commands = renderer.buffer_commands[source]
	for _, spec in pairs(commands) do
		spec.program = Program.compile(spec.implementation, source, resolve)
		if spec.default_node then
			local default_program = Program.compile(spec.default_node, source, resolve)
			spec.default_optional = function(context)
				return default_program:execute({}, context)
			end
		end
	end
end

---@param buffer integer
function M.clear(buffer)
	parser.buffer_command_specs[buffer] = nil
	renderer.buffer_commands[buffer] = nil
end

return M
