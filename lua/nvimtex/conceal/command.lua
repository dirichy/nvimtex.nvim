local Render = require("nvimtex.conceal.render_tree")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local mathstyle = require("nvimtex.latex.mathstyle")
local hl = require("nvimtex.highlight")

local M = {}

---Compare two zero-based byte positions.
local function position_before(left_row, left_col, right_row, right_col)
	return left_row < right_row or left_row == right_row and left_col < right_col
end

---The inverse half of the position comparison used by half-open ranges.
local function position_at_or_after(left_row, left_col, right_row, right_col)
	return left_row > right_row or left_row == right_row and left_col >= right_col
end

---@param cursor? integer[] zero-based row and byte column
---@return boolean
local function cursor_in_range(cursor, start_row, start_col, end_row, end_col)
	return cursor ~= nil
		and position_at_or_after(cursor[1], cursor[2], start_row, start_col)
		and position_before(cursor[1], cursor[2], end_row, end_col)
end

---Whether the cursor is inside a node's half-open source range.
---@param context Nvimtex.RenderContext
---@param node? Nvimtex.LNode
---@return boolean
function M.cursor_in_node(context, node)
	if not context.cursor or not node then
		return false
	end
	local start_row, start_col, end_row, end_col = node:range()
	return cursor_in_range(context.cursor, start_row, start_col, end_row, end_col)
end

---Whether the cursor is inside an argument's contents, excluding `{}`, `[]`.
---@param context Nvimtex.RenderContext
---@param index integer
---@return boolean
function M.cursor_in_argument(context, index)
	local node = context.argument_nodes[index]
	if not M.cursor_in_node(context, node) then
		return false
	end
	if not latex_nodes.group_delimiters(node) then
		return true
	end
	local opening = node:child(0)
	local closing = node:child(node:child_count() - 1)
	if not opening or not closing then
		return false
	end
	local start_row, start_col = opening:end_()
	local end_row, end_col = closing:start()
	return cursor_in_range(context.cursor, start_row, start_col, end_row, end_col)
end

---Whether the cursor is on command syntax rather than argument contents.
---@param context Nvimtex.RenderContext
---@return boolean
function M.cursor_in_shell(context)
	if not M.cursor_in_node(context, context.node) then
		return false
	end
	for index = 1, context.argument_count or #context.argument_nodes do
		if M.cursor_in_argument(context, index) then
			return false
		end
	end
	return true
end

---Build a command spec around an arbitrary RenderTree renderer.
---@param narg integer
---@param render Nvimtex.Renderer
---@param options? Nvimtex.RenderSpec
---@return Nvimtex.RenderSpec
function M.create(narg, render, options)
	local spec = vim.tbl_extend("force", {}, options or {})
	spec.narg = narg
	spec.render = render
	return spec
end

---Reveal command prefixes and group delimiters while preserving rendered args.
---Returns nil when the cursor is not on the command shell.
---@param values table<integer,Nvimtex.RenderTree>
---@param context Nvimtex.RenderContext
---@return Nvimtex.RenderTree?
function M.reveal_shell(values, context)
	if not M.cursor_in_shell(context) then
		return nil
	end
	local start_row, start_col = context.node:start()
	local result = { Render.text("", start_row, start_col, Render.mode.reveal) }
	for index = 1, context.argument_count or #context.argument_nodes do
		if values[index] then
			result[#result + 1] = values[index]
			local end_row, end_col = latex_nodes.closing_delimiter_start(context.argument_nodes[index])
			result[#result + 1] = Render.text("", end_row, end_col, Render.mode.reveal)
		end
	end
	return Render.concat_many(result)
end

---@param tree Nvimtex.RenderTree
---@param context Nvimtex.RenderContext
---@return Nvimtex.RenderTree
local function reveal_single_argument_shell(tree, context)
	return M.reveal_shell({ tree }, context) or tree
end

---Build a command with one leading optional argument. The optional default may
---be a RenderTree or a function of the render context; nil preserves absence.
---@param narg integer
---@param default? Nvimtex.RenderTree|fun(context:Nvimtex.RenderContext):Nvimtex.RenderTree?
---@param render Nvimtex.Renderer
---@param options? Nvimtex.RenderSpec
---@return Nvimtex.RenderSpec
function M.optional(narg, default, render, options)
	options = vim.tbl_extend("force", {}, options or {})
	options.optional = true
	options.default_optional = default
	return M.create(narg, render, options)
end

---Fill an absent optional argument. An explicit default that returns nil is a
---render failure; a command without a default may keep its first slot empty.
---@param args table<integer,Nvimtex.RenderTree>
---@param spec Nvimtex.RenderSpec
---@param context Nvimtex.RenderContext
---@return boolean
function M.apply_default(args, spec, context)
	if spec.optional and not args[1] and spec.default_optional ~= nil then
		local default = spec.default_optional
		if type(default) == "function" then
			args[1] = default(context)
			return args[1] ~= nil
		end
		args[1] = default
	end
	return true
end

---Apply only a highlight to a single argument.
---@param highlight string|string[]
---@return Nvimtex.RenderSpec
function M.highlight(highlight)
	return M.create(1, function(args, context)
		return reveal_single_argument_shell(Render.highlight(args[1], highlight), context)
	end, { cursor_aware = true })
end

---Apply an exact display transform. Any unsupported leaf returns nil so the
---adapter reveals the complete source command without changing its semantics.
---@param map table<string,string>|fun(char:string):string?
---@param highlight? string|string[]
---@return Nvimtex.RenderSpec
function M.transform(map, highlight)
	return M.create(1, function(args, context)
		-- Revealed leaves represent syntax the renderer could not safely
		-- interpret. Never run arbitrary character maps over that source.
		if args[1]:has_reveal() then
			return nil
		end
		local tree = args[1]:try_transform(map, highlight)
		return tree and reveal_single_argument_shell(tree, context) or nil
	end, { reveal_on_failure = true, cursor_aware = true })
end

---Apply a combining suffix to every displayable character.
---@param suffix string
---@param highlight? string|string[]
---@return Nvimtex.RenderSpec
function M.accent(suffix, highlight)
	return M.transform(function(char)
		return char .. suffix
	end, highlight)
end

---Choose a delimiter anchor from an argument, generated call, or command node.
---@param context Nvimtex.RenderContext
---@param argument_index? integer
---@return integer, integer
local function anchor(context, argument_index)
	local node = argument_index and context.argument_nodes[argument_index]
	local row, col = latex_nodes.closing_delimiter_start(node)
	if row ~= nil then
		return row, col
	end
	if context.anchor_row ~= nil then
		return context.anchor_row, context.anchor_col
	end
	return context.node:start()
end

---Surround arguments with rainbow delimiters. Generated-command programs may
---omit argument_nodes; in that case all virtual pieces use the call anchor.
---@param ... string
---@return Nvimtex.RenderSpec
function M.delimited(...)
	local delimiters = { ... }
	return M.create(#delimiters - 1, function(args, context)
		local values = {}
		local row, col = anchor(context)
		local mode = M.cursor_in_shell(context) and Render.mode.reveal or Render.mode.replace
		for index, argument in ipairs(args) do
			values[#values + 1] = index == 1 and Render.delim_open(delimiters[index], row, col, mode)
				or Render.delim_middle(delimiters[index], row, col, mode)
			values[#values + 1] = argument
			row, col = anchor(context, index)
		end
		values[#values + 1] = Render.delim_close(delimiters[#delimiters], row, col, mode)
		return Render.concat_many(values)
	end, { cursor_aware = true })
end

---Share script display semantics between source nodes and compiled commands.
---The caller supplies rendered contents; this template owns `_`/`^` and braces.
---@param marker string
---@param map table<string,string>
---@return Nvimtex.RenderSpec
local function script_spec(marker, map)
	return M.create(1, function(args, context)
		local value = args[1]
		local row, col = context.node:start()
		local styled = value:try_transform(map, hl.script)
		if styled then
			return M.reveal_shell({ styled }, context) or Render.concat_many({ Render.text("", row, col), styled })
		end
		local end_row, end_col = latex_nodes.closing_delimiter_start(context.argument_nodes[1])
		local mode = M.cursor_in_shell(context) and Render.mode.reveal or Render.mode.replace
		return Render.concat_many({
			Render.delim_open(marker .. "{", row, col, mode),
			value,
			Render.delim_close("}", end_row, end_col, mode),
		})
	end, { cursor_aware = true })
end

---@type table<string,Nvimtex.RenderSpec>
M.scripts = {
	subscript = script_spec("_", mathstyle.subscript),
	superscript = script_spec("^", mathstyle.superscript),
}

return M
