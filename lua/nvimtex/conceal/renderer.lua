local Render = require("nvimtex.conceal.render_tree")
local Command = require("nvimtex.conceal.command")
local parser = require("nvimtex.parser")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local mathstyle = require("nvimtex.latex.mathstyle")
local hl = require("nvimtex.highlight")

local M = {}
local previous_parser_specs = {}

---@alias Nvimtex.Renderer fun(args:table<integer,Nvimtex.RenderTree>,context:Nvimtex.RenderContext):Nvimtex.RenderTree?
---@alias Nvimtex.NodeRenderer fun(node:Nvimtex.LNode,source:number|string,session?:Nvimtex.RenderSession):Nvimtex.RenderTree

---@class Nvimtex.RenderSession
---@field cursor? integer[] zero-based row and byte column

---@class Nvimtex.RenderSpec
---@field narg? integer
---@field optional? boolean
---@field default_optional? Nvimtex.RenderTree|fun(context:Nvimtex.RenderContext):Nvimtex.RenderTree?
---@field atomic? boolean owns the complete command source range
---@field reveal_on_failure? boolean reveal the complete command when render returns nil
---@field cursor_aware? boolean renderer implements its own cursor reveal policy
---@field render Nvimtex.Renderer
---@field adapter? Nvimtex.NodeRenderer cached buffer-local adapter

---@class Nvimtex.RenderContext
---@field node Nvimtex.LNode
---@field source number|string
---@field argument_nodes table<integer,Nvimtex.LNode> sparse when optional argument is absent
---@field argument_count integer
---@field cursor? integer[] zero-based row and byte column
---@field anchor_row? integer generated command anchor
---@field anchor_col? integer generated command anchor, byte column
---@field depth? integer nested compiled program depth

---@type table<string,Nvimtex.RenderSpec>
M.command_specs = {}
---@type table<string,Nvimtex.NodeRenderer>
M.command_adapters = {}
---@type table<integer,table<string,Nvimtex.RenderSpec>>
M.buffer_commands = {}

---@param name string
---@param source number|string
---@return Nvimtex.RenderSpec?
function M.command_spec(name, source)
	local commands = type(source) == "number" and M.buffer_commands[source]
	return commands and commands[name] or M.command_specs[name]
end

---@param buffer integer
---@param name string
---@param spec Nvimtex.RenderSpec
function M.register_buffer_command(buffer, name, spec)
	M.buffer_commands[buffer] = M.buffer_commands[buffer] or {}
	spec.adapter = M.adapt_command(spec)
	M.buffer_commands[buffer][name] = spec
end
---Expose high-level spec constructors alongside the low-level registration API.
M.command = Command

---Create a text leaf and optionally decorate it with a highlight wrapper.
---@param text string
---@param row integer
---@param col integer
---@param mode Nvimtex.RenderTree.Mode
---@param highlight? string|string[]
---@return Nvimtex.RenderTree
local function text_tree(text, row, col, mode, highlight)
	local result = Render.text(text, row, col, mode)
	return highlight and Render.highlight(result, highlight) or result
end

---Represent one source node as a single leaf. Revealed nodes add an explicit
---end anchor so preserved source cannot leak into a following closing token.
---@param node Nvimtex.LNode
---@param source number|string
---@param mode Nvimtex.RenderTree.Mode
---@param highlight? string|string[]
---@return Nvimtex.RenderTree
local function node_tree(node, source, mode, highlight)
	local start_row, start_col = node:start()
	local result = text_tree(vim.treesitter.get_node_text(node, source), start_row, start_col, mode, highlight)
	if mode == Render.mode.reveal or mode == Render.mode.plain then
		local end_row, end_col = node:end_()
		result = Render.concat_many({ result, Render.text("", end_row, end_col) })
	end
	return result
end

---Use a subtree's first source anchor, falling back for empty arguments.
---@param tree Nvimtex.RenderTree
---@param fallback_row integer
---@param fallback_col integer
---@return integer, integer
local function first_start(tree, fallback_row, fallback_col)
	local row, col = tree:source_start()
	return row or fallback_row, col or fallback_col
end

---@type fun(node:Nvimtex.LNode,source:number|string,session?:Nvimtex.RenderSession):Nvimtex.RenderTree
local render_node

---@param nodes Nvimtex.LNode[]
---@param source number|string
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
local function render_sequence(nodes, source, session)
	local values = {}
	for _, node in ipairs(nodes) do
		values[#values + 1] = render_node(node, source, session)
	end
	return Render.concat_many(values)
end

---Render argument contents while letting the command renderer own group tokens.
---@param node Nvimtex.LNode
---@param source number|string
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
local function render_argument(node, source, session)
	if not latex_nodes.group_delimiters(node) then
		return render_node(node, source, session)
	end
	return render_sequence(parser.content_nodes(node, source), source, session)
end

---Prepare the shared argument layout before any cursor or rendering policy.
---@param node Nvimtex.LNode
---@param source number|string
---@param spec Nvimtex.RenderSpec
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderContext?
local function command_context(node, source, spec, session)
	if spec.narg and #node:field("arg") ~= spec.narg then
		return nil
	end
	local nodes, count = parser.command_arguments(node, spec.optional)
	return {
		node = node,
		source = source,
		argument_nodes = nodes,
		argument_count = count,
		cursor = session and session.cursor,
	}
end

---@param spec Nvimtex.RenderSpec
---@return Nvimtex.NodeRenderer
function M.adapt_command(spec)
	return function(node, source, session)
		local context = command_context(node, source, spec, session)
		if not context then
			return M.render_fallback(node, source, session)
		end
		-- A raw renderer has no structural reveal policy; showing the complete
		-- invocation is the safe editing fallback.
		if context.cursor and Command.cursor_in_node(context, node) and not spec.cursor_aware then
			return node_tree(node, source, Render.mode.reveal)
		end
		local args = {}
		for index = 1, context.argument_count do
			local argument = context.argument_nodes[index]
			if argument then
				args[index] = render_argument(argument, source, session)
			end
		end
		if not Command.apply_default(args, spec, context) then
			return node_tree(node, source, Render.mode.reveal)
		end

		local rendered = spec.render(args, context)
		if not rendered then
			if spec.reveal_on_failure then
				return node_tree(node, source, Render.mode.reveal)
			end
			return M.render_fallback(node, source, session)
		end
		if spec.atomic then
			-- Reordered or duplicated output must own one monotonic source range.
			local start_row, start_col = node:start()
			return Render.atomic(rendered, start_row, start_col)
		end
		local start_row, start_col = node:start()
		-- The zero-width prefix makes the adapter own and conceal the command name.
		return Render.concat_many({
			Render.text("", start_row, start_col),
			rendered,
		})
	end
end

---Register a spec and compile its argument adapter once, outside the hot path.
---@param name string
---@param spec Nvimtex.RenderSpec
---@return Nvimtex.RenderSpec
function M.register_command(name, spec)
	M.command_specs[name] = spec
	M.command_adapters[name] = M.adapt_command(spec)
	if spec.narg ~= nil then
		local specs = require("nvimtex.parser.command_specs")
		if previous_parser_specs[name] == nil then
			previous_parser_specs[name] = specs[name] or false
		end
		specs[name] = { narg = spec.narg, oarg = spec.optional }
	end
	return spec
end

---@param name string
function M.unregister_command(name)
	M.command_specs[name] = nil
	M.command_adapters[name] = nil
	if previous_parser_specs[name] ~= nil then
		require("nvimtex.parser.command_specs")[name] = previous_parser_specs[name] or nil
		previous_parser_specs[name] = nil
	end
end

---Fractions prefer compact super/subscript output and fall back to `(a)/(b)`.
---@type Nvimtex.RenderSpec
local frac_spec = {
	narg = 2,
	cursor_aware = true,
	render = function(args, context)
		local numerator = args[1]
		local denominator = args[2]
		local super = numerator:try_transform(mathstyle.superscript)
		local sub = denominator:try_transform(mathstyle.subscript)
		local start_row, start_col = context.node:start()
		local middle_row, middle_col = latex_nodes.closing_delimiter_start(context.argument_nodes[1])
		local finish_row, finish_col = latex_nodes.closing_delimiter_start(context.argument_nodes[2])
		local mode = Command.cursor_in_shell(context) and Render.mode.reveal or Render.mode.replace
		if super and sub then
			return Render.concat_many({
				Render.delim_open("", start_row, start_col, mode),
				super,
				Render.delim_middle("/", middle_row, middle_col, mode),
				sub,
				Render.delim_close("", finish_row, finish_col, mode),
			})
		end
		return Render.concat_many({
			Render.delim_open("(", start_row, start_col, mode),
			numerator,
			Render.delim_middle(")/(", middle_row, middle_col, mode),
			denominator,
			Render.delim_close(")", finish_row, finish_col, mode),
		})
	end,
}

M.register_command("frac", frac_spec)
M.register_command("dfrac", frac_spec)
M.register_command("tfrac", frac_spec)
M.register_command("mathbb", Command.transform(mathstyle.mathbb, hl.symbol))
M.register_command("mathcal", Command.transform(mathstyle.mathcal, hl.symbol))
M.register_command("mathbbm", Command.transform(mathstyle.mathbbm, hl.symbol))
M.register_command("mathfrak", Command.transform(mathstyle.mathfrak, hl.symbol))
M.register_command("mathscr", Command.transform(mathstyle.mathscr, hl.symbol))
M.register_command("mathsf", Command.transform(mathstyle.mathsf, hl.symbol))
M.register_command("mathrm", Command.highlight(hl.constant))
M.register_command("operatorname", Command.highlight(hl.constant))
M.register_command(
	"not",
	Command.transform(function(char)
		return char .. "̸"
	end)
)
M.register_command("norm", Command.delimited("‖", "‖"))
M.register_command("abs", Command.delimited("|", "|"))
M.register_command("binom", Command.delimited("(", "C", ")"))

local accent_maps = {
	["'"] = "́",
	['"'] = "̈",
	["`"] = "̀",
	["="] = "̄",
	["~"] = "̃",
	["."] = "̇",
	["^"] = "̂",
	tilde = "̂",
	overline = "̅",
	bar = "̅",
}
-- All accent commands share the same one-argument template.
for name, suffix in pairs(accent_maps) do
	M.register_command(name, Command.accent(suffix))
end

M.register_command("sqrt", {
	narg = 1,
	optional = true,
	cursor_aware = true,
	render = function(args, context)
		local argument = args[2]
		local root = args[1]
		local revealed_shell = Command.reveal_shell(args, context)
		if revealed_shell then
			return revealed_shell
		end
		local argument_highlight = argument:first_highlight() or hl.default
		local start_row, start_col = context.node:start()
		local finish_row, finish_col = latex_nodes.closing_delimiter_start(context.argument_nodes[2])
		local narrow = argument.width <= 1
		-- A one-cell radicand can use a combining overline; wider content needs
		-- explicit parentheses because terminal cells cannot draw a long radical.
		local overlined = narrow and argument:try_transform(mathstyle.overline, argument_highlight) or nil
		if overlined then
			local prefix
			if root then
				local styled_root = root:try_transform(mathstyle.superscript, argument_highlight)
				prefix = styled_root
					and Render.concat_many({
						styled_root,
						Render.highlight(Render.text("√", start_row, start_col), argument_highlight),
					})
				if not prefix then
					local root_end_row, root_end_col = latex_nodes.closing_delimiter_start(context.argument_nodes[1])
					prefix = Render.concat_many({
						Render.highlight(Render.text("(", start_row, start_col), argument_highlight),
						root,
						Render.highlight(Render.text(")√", root_end_row, root_end_col), argument_highlight),
					})
				end
			else
				prefix = Render.highlight(Render.text("√", start_row, start_col), argument_highlight)
			end
			return Render.concat_many({ prefix, overlined })
		end

		local prefix
		if root then
			local styled_root = root:try_transform(mathstyle.superscript, argument_highlight)
			prefix = styled_root
				and Render.concat_many({
					Render.delim_open("", start_row, start_col),
					styled_root,
					Render.delim_middle("√", start_row, start_col),
				})
			if not prefix then
				local root_end_row, root_end_col = latex_nodes.closing_delimiter_start(context.argument_nodes[1])
				prefix = Render.concat_many({
					Render.delim_open("(", start_row, start_col),
					root,
					Render.delim_middle(")√", root_end_row, root_end_col),
				})
			end
		else
			prefix = Render.delim_open("√", start_row, start_col)
		end
		local argument_start_row, argument_start_col = first_start(argument, start_row, start_col)
		return Render.concat_many({
			prefix,
			Render.delim_middle("(", argument_start_row, argument_start_col),
			argument,
			Render.delim_close(")", finish_row, finish_col),
		})
	end,
})

---Scripts own their group syntax; only their contents become template args.
---@param node Nvimtex.LNode
---@param source number|string
---@param spec Nvimtex.RenderSpec
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
local function render_script(node, source, spec, session)
	local argument = node:named_child(0)
	if not argument then
		return node_tree(node, source, Render.mode.reveal)
	end
	return spec.render({ render_argument(argument, source, session) }, {
		node = node,
		source = source,
		argument_nodes = { argument },
		argument_count = 1,
		cursor = session and session.cursor,
	})
end

local command_symbols = require("nvimtex.conceal.command_name")

---Render a zero-argument symbol command, revealing its source under the cursor.
---@param symbol string|table
---@param node Nvimtex.LNode
---@param source number|string
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
local function command_symbol_tree(symbol, node, source, session)
	local text = type(symbol) == "table" and symbol[1] or symbol
	local highlight = type(symbol) == "table" and symbol[2] or hl.symbol
	local context = { node = node, cursor = session and session.cursor }
	if Command.cursor_in_node(context, node) then
		return node_tree(node, source, Render.mode.reveal, highlight)
	end
	local row, col = node:start()
	return Render.highlight(Render.text(text, row, col), highlight)
end

---Recursively preserve unsupported syntax instead of silently dropping it.
---@param node Nvimtex.LNode
---@param source number|string
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
function M.render_fallback(node, source, session)
	if node:child_count() == 0 then
		return node_tree(node, source, Render.mode.reveal)
	end
	local children = {}
	for child in parser.iter_children(node, source) do
		children[#children + 1] = child
	end
	local rendered = render_sequence(children, source, session)
	-- Some named nodes (notably operators) contain only anonymous grammar
	-- tokens, which the parser stream intentionally omits. They are understood
	-- literal source, so keep them plain and therefore eligible for transforms.
	if rendered == Render.empty() then
		local context = { node = node, cursor = session and session.cursor }
		return Command.cursor_in_node(context, node) and node_tree(node, source, Render.mode.reveal)
			or node_tree(node, source, Render.mode.plain)
	end
	return rendered
end

---Dispatch one syntax node to a command, symbol, script, or fallback renderer.
---@param node Nvimtex.LNode
---@param source number|string
---@param session? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
function render_node(node, source, session)
	local node_type = node:type()
	if node_type == "if_statement" then
		local block = node:field("if_block")[1]
		return block and M.render_fallback(block, source, session) or Render.empty()
	elseif node_type == "generic_command" then
		local name = latex_nodes.command_name(source, node)
		local spec = name and M.command_spec(name, source)
		if spec then
			return (spec.adapter or M.command_adapters[name])(node, source, session)
		end
		local symbol = name and command_symbols[name]
		if symbol then
			return command_symbol_tree(symbol, node, source, session)
		end
		return M.render_fallback(node, source, session)
	elseif node_type == "command_name" then
		local name = vim.treesitter.get_node_text(node, source):sub(2)
		local symbol = command_symbols[name]
		return symbol and command_symbol_tree(symbol, node, source, session)
			or node_tree(node, source, Render.mode.reveal)
	elseif node_type == "word" or node_type == "letter" then
		local text = vim.treesitter.get_node_text(node, source)
		local context = { node = node, cursor = session and session.cursor }
		if Command.cursor_in_node(context, node) then
			return node_tree(node, source, Render.mode.reveal, tonumber(text) and hl.constant or nil)
		end
		return node_tree(node, source, Render.mode.plain, tonumber(text) and hl.constant or nil)
	elseif Command.scripts[node_type] then
		return render_script(node, source, Command.scripts[node_type], session)
	elseif node_type == "\\(" or node_type == "\\)" then
		local context = { node = node, cursor = session and session.cursor }
		if Command.cursor_in_node(context, node) then
			return node_tree(node, source, Render.mode.reveal, hl.constant)
		end
		local row, col = node:start()
		return text_tree("$", row, col, Render.mode.replace, hl.constant)
	elseif node_type == "\\[" or node_type == "\\]" then
		local context = { node = node, cursor = session and session.cursor }
		if Command.cursor_in_node(context, node) then
			return node_tree(node, source, Render.mode.reveal, hl.constant)
		end
		local row, col = node:start()
		return text_tree("$$", row, col, Render.mode.replace, hl.constant)
	elseif node_type == "placeholder" then
		return node_tree(node, source, Render.mode.reveal, hl.error)
	end
	return M.render_fallback(node, source, session)
end

---Render one complete math root and append the boundary required by emit.
---@param node Nvimtex.LNode
---@param source number|string
---@param opts? Nvimtex.RenderSession
---@return Nvimtex.RenderTree
function M.render_node(node, source, opts)
	return Render.concat_many({ render_node(node, source, opts), Render.boundary(node:end_()) })
end

---Resolve symbols as zero-argument renderers for compiled document commands.
---@param name string
---@param source number|string
---@return Nvimtex.RenderSpec?
function M.program_spec(name, source)
	local spec = M.command_spec(name, source)
	if spec then
		return spec
	end
	local symbol = command_symbols[name]
	if symbol then
		return {
			narg = 0,
			render = function(_, context)
				return command_symbol_tree(symbol, context.node, context.source)
			end,
		}
	end
end

return M
