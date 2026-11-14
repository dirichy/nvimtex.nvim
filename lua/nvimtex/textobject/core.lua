local parser = require("nvimtex.parser")
local nodes = require("nvimtex.parser.latex_nodes")
local syntax = require("nvimtex.conditions.util")

local M = {}

---@alias Nvimtex.Textobject.Id "c"|"a"|"m"|"e"|"g"|"S"|"N"
---@class Nvimtex.Textobject.Context
---@field bufnr integer
---@field reference Range4 Zero-based byte coordinates, end-exclusive; equal endpoints mean a cursor point.
---@field inner boolean
---@field count? integer Enclosing layer, defaults to 1.
---@alias Nvimtex.Textobject.Point {[1]:integer,[2]:integer}
---@alias Nvimtex.Textobject.Pair {outer_start:Nvimtex.Textobject.Point, inner_start:Nvimtex.Textobject.Point, inner_end:Nvimtex.Textobject.Point, outer_end:Nvimtex.Textobject.Point}

---@type Nvimtex.Textobject.Id[]
M.ids = { "c", "a", "m", "e", "g", "S", "N" }
local latex_filetypes = { tex = true, plaintex = true, latex = true }
local node_types = {
	c = syntax.CMD_NODES,
	m = syntax.MATH_NODES,
	e = syntax.ENV_NODES,
	S = { subscript = true, superscript = true },
	N = syntax.ENV_NODES,
}

local function before(ar, ac, br, bc)
	return ar < br or ar == br and ac < bc
end

local function equal(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

---@param outer Range4
---@param reference Range4
---@return boolean
local function contains(outer, reference)
	if before(reference[1], reference[2], outer[1], outer[2]) then
		return false
	end
	if reference[1] == reference[3] and reference[2] == reference[4] then
		return before(reference[1], reference[2], outer[3], outer[4])
	end
	return not before(outer[3], outer[4], reference[3], reference[4])
end

---@param node Nvimtex.LNode
---@return Range4
local function range(node)
	return { node:range() }
end

---Use actual syntax boundaries, preserving newlines and UTF-8 byte offsets.
---An absent/missing closing token cannot define a safe inside selection.
---@param node Nvimtex.LNode
---@return Range4?
local function interior(node)
	local opening, closing = node:child(0), node:child(node:child_count() - 1)
	if not opening or not closing or opening == closing then
		return nil
	end
	if type(closing) == "userdata" and closing:missing() then
		return nil
	end
	local open_type, close_type = nodes.group_delimiters(node)
	if open_type and (opening:type() ~= open_type or closing:type() ~= close_type) then
		return nil
	end
	local row, col = opening:end_()
	local end_row, end_col = closing:start()
	if before(end_row, end_col, row, col) then
		return nil
	end
	return { row, col, end_row, end_col }
end

---@param outer Range4
---@param inside Range4
---@return Nvimtex.Textobject.Pair
local function boundaries(outer, inside)
	return {
		outer_start = { outer[1], outer[2] },
		inner_start = { inside[1], inside[2] },
		inner_end = { inside[3], inside[4] },
		outer_end = { outer[3], outer[4] },
	}
end

---@param node Nvimtex.LNode
---@param ctx Nvimtex.Textobject.Context
---@return Nvimtex.Textobject.Pair?
local function argument_bounds(node, ctx)
	if not syntax.CMD_NODES[node:type()] then
		return nil
	end
	local arguments = nodes.arguments(node)
	local optional = nodes.optional_argument(node)
	if optional then
		arguments[#arguments + 1] = optional
	end
	for _, argument in ipairs(arguments) do
		local outer = range(argument)
		if contains(outer, ctx.reference) then
			---@type Range4?
			local inside = outer
			if nodes.group_delimiters(argument) then
				inside = interior(argument)
			end
			if inside then
				return boundaries(outer, inside)
			end
		end
	end
end

---Only a complete, braced single-argument command is a two-ended wrapper.
---Optional arguments belong to the opening; environment markers are not wrappers.
---@param node Nvimtex.LNode
---@param bufnr integer
---@return Nvimtex.Textobject.Pair?
local function command_pair(node, bufnr)
	if node:type() == "begin" or node:type() == "end" then
		return nil
	end
	local arguments = nodes.arguments(node)
	local name = nodes.command_name(bufnr, node)
	local spec = name and parser.command_spec(name, bufnr)
	if #arguments ~= 1 or spec and spec.narg and spec.narg ~= 1 then
		return nil
	end
	local argument = arguments[1]
	if not nodes.group_delimiters(argument) then
		return nil
	end
	local inside = interior(argument)
	if not inside then
		return nil
	end
	return boundaries(range(node), inside)
end

---@param node Nvimtex.LNode
---@param id Nvimtex.Textobject.Id
---@param ctx Nvimtex.Textobject.Context
---@return Nvimtex.Textobject.Pair?
local function object_bounds(node, id, ctx)
	if id == "a" then
		return argument_bounds(node, ctx)
	end
	if id == "g" then
		if not nodes.group_delimiters(node) then
			return nil
		end
	elseif not node_types[id][node:type()] then
		return nil
	end
	if id == "N" then
		local closing = nodes.environment_end(node)
		local marker = closing and contains(range(closing), ctx.reference) and closing or nodes.environment_begin(node)
		local name = marker and nodes.environment_name_node(marker)
		local inside = name and interior(name)
		return name and inside and boundaries(range(name), inside) or nil
	end
	local outer = range(node)
	if id == "c" then
		local command = nodes.command(node)
		if not command then
			return nil
		end
		local name = range(command)
		-- The backslash belongs to the command, but not to its editable name.
		name[2] = name[2] + 1
		return boundaries(outer, name)
	end
	if id == "S" then
		local argument = nodes.script_argument(node)
		if not argument then
			return nil
		end
		---@type Range4?
		local inside = range(argument)
		if nodes.group_delimiters(argument) then
			inside = interior(argument)
		end
		return inside and boundaries(outer, inside) or nil
	end
	local inside = interior(node)
	if inside then
		return boundaries(outer, inside)
	end
	if not ctx.inner then
		return boundaries(outer, outer)
	end
end

---@param node Nvimtex.LNode
---@param id Nvimtex.Textobject.Id
---@param ctx Nvimtex.Textobject.Context
---@return Nvimtex.Textobject.Pair?
local function surround_bounds(node, id, ctx)
	if id == "c" then
		return syntax.CMD_NODES[node:type()] and command_pair(node, ctx.bufnr) or nil
	end
	if id ~= "m" and id ~= "e" and id ~= "g" then
		return nil
	end
	local pair = object_bounds(node, id, ctx)
	if not pair then
		return nil
	end
	if syntax.ENV_NODES[node:type()] then
		local closing = nodes.environment_end(node)
		if not closing or nodes.environment_name(ctx.bufnr, node) ~= nodes.environment_name(ctx.bufnr, closing) then
			return nil
		end
	end
	-- Surround needs both delimiters; selection may still support an unfinished node.
	if
		before(pair.outer_start[1], pair.outer_start[2], pair.inner_start[1], pair.inner_start[2])
		and before(pair.inner_end[1], pair.inner_end[2], pair.outer_end[1], pair.outer_end[2])
	then
		return pair
	end
end

---Parse the queried buffer, including LaTeX injections, without consulting a
---window or the current cursor. Hidden buffers work with the same context.
---@param ctx Nvimtex.Textobject.Context
---@return TSNode[]
local function roots(ctx)
	local language = latex_filetypes[vim.bo[ctx.bufnr].filetype] and "latex" or nil
	local ok, language_tree = pcall(vim.treesitter.get_parser, ctx.bufnr, language)
	if not ok or not language_tree then
		return {}
	end
	local parsed = pcall(language_tree.parse, language_tree, { { ctx.reference[1], ctx.reference[3] + 1 } })
	if not parsed then
		return {}
	end
	local result = {}
	language_tree:for_each_tree(function(tree, owner)
		local root = tree:root()
		if owner:lang() == "latex" and contains(range(root), ctx.reference) then
			result[#result + 1] = root
		end
	end)
	return result
end

---@param id Nvimtex.Textobject.Id
---@param ctx Nvimtex.Textobject.Context
---@param pair_only? boolean
---@param record? fun(pair:Nvimtex.Textobject.Pair)
---@return Nvimtex.Textobject.Pair?
local function find(id, ctx, pair_only, record)
	assert(id == "a" or id == "g" or node_types[id], "unknown LaTeX textobject: " .. tostring(id))
	local count = ctx.count or 1
	assert(count >= 1 and count % 1 == 0, "textobject count must be a positive integer")
	if not vim.api.nvim_buf_is_loaded(ctx.bufnr) then
		return nil
	end
	local reference = ctx.reference
	local point = reference[1] == reference[3] and reference[2] == reference[4]
	local end_row, end_col = reference[3], reference[4]
	if point then
		end_col = end_col + 1
	end
	local seen = {}
	for _, root in ipairs(roots(ctx)) do
		local ancestors =
			parser.descendants_node_covering_range(root, ctx.bufnr, reference[1], reference[2], end_row, end_col)
		for index = #ancestors, 1, -1 do
			local node = ancestors[index]
			local pair
			if pair_only then
				pair = surround_bounds(node, id, ctx)
			else
				pair = object_bounds(node, id, ctx)
			end
			local first = pair and (ctx.inner and pair.inner_start or pair.outer_start)
			local last = pair and (ctx.inner and pair.inner_end or pair.outer_end)
			local candidate = first and last and { first[1], first[2], last[1], last[2] }
			if candidate and (point or contains(candidate, reference) and not equal(candidate, reference)) then
				local key = table.concat(candidate, ":")
				if not seen[key] then
					seen[key] = true
					if pair and record then
						record(pair)
					end
					count = count - 1
					if count == 0 then
						return pair
					end
				end
			end
		end
	end
end

---Find an enclosing object without changing editor state.
---Nonempty references require a strictly larger result.
---@param id Nvimtex.Textobject.Id
---@param ctx Nvimtex.Textobject.Context
---@return Range4?
function M.find(id, ctx)
	local pair = find(id, ctx)
	if not pair then
		return nil
	end
	local first = ctx.inner and pair.inner_start or pair.outer_start
	local last = ctx.inner and pair.inner_end or pair.outer_end
	return { first[1], first[2], last[1], last[2] }
end

---Selection boundaries for integrations that derive inside/around from four points.
---These are independent of the removable command-wrapper boundaries.
---@param id Nvimtex.Textobject.Id
---@param ctx Nvimtex.Textobject.Context
---@param record? fun(pair:Nvimtex.Textobject.Pair)
---@return Nvimtex.Textobject.Pair?
function M.find_bounds(id, ctx, record)
	return find(id, ctx, false, record)
end

---Find complete removable delimiters, independently of textobject name selections.
---@param id Nvimtex.Textobject.Id
---@param ctx Nvimtex.Textobject.Context
---@param record? fun(pair:Nvimtex.Textobject.Pair)
---@return Nvimtex.Textobject.Pair?
function M.find_pair(id, ctx, record)
	return find(id, ctx, true, record)
end

return M
