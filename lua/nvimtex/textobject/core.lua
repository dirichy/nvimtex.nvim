local parser = require("nvimtex.parser")
local nodes = require("nvimtex.parser.latex_nodes")
local syntax = require("nvimtex.conditions.util")

local ranges = require("nvimtex.textobject.ranges")
local structure = require("nvimtex.textobject.structure")
local delimiters = require("nvimtex.textobject.delimiters")
local before, equal, contains = ranges.before, ranges.equal, ranges.contains
local range, interior, boundaries = ranges.of, ranges.interior, ranges.boundaries
local M = {}

---@alias Nvimtex.Textobject.Id "c"|"a"|"m"|"e"|"g"|"u"|"S"|"i"|"d"
---@class Nvimtex.Textobject.Context
---@field bufnr integer
---@field reference Range4 Zero-based byte coordinates, end-exclusive; equal endpoints mean a cursor point.
---@field inner boolean
---@field count? integer Enclosing layer, defaults to 1.
---@alias Nvimtex.Textobject.Point {[1]:integer,[2]:integer}
---@alias Nvimtex.Textobject.Pair {outer_start:Nvimtex.Textobject.Point, inner_start:Nvimtex.Textobject.Point, inner_end:Nvimtex.Textobject.Point, outer_end:Nvimtex.Textobject.Point}

---@type Nvimtex.Textobject.Id[]
M.ids = { "c", "a", "m", "e", "u", "S", "i", "d" }
local latex_filetypes = { tex = true, plaintex = true, latex = true }
local node_types = {
	c = syntax.CMD_NODES,
	m = syntax.MATH_NODES,
	e = syntax.ENV_NODES,
	u = { subscript = true, superscript = true },
}

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
	-- Argument selection depends on the group's structure, not its parent's type.
	if id == "a" or id == "g" then
		if not nodes.group_delimiters(node) then
			return nil
		end
	elseif not node_types[id][node:type()] then
		return nil
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
	if id == "u" then
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
	if not ctx.inner and id ~= "a" and id ~= "g" then
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
	assert(
		id == "a" or id == "g" or id == "d" or structure.types[id] or node_types[id],
		"unknown LaTeX textobject: " .. tostring(id)
	)
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
		local candidates = {}
		if (id == "S" or id == "i") and not pair_only then
			candidates = structure.candidates(root, ctx, id)
		else
			local ancestors =
				parser.descendants_node_covering_range(root, ctx.bufnr, reference[1], reference[2], end_row, end_col)
			for index = #ancestors, 1, -1 do
				local node = ancestors[index]
				if id == "d" then
					vim.list_extend(candidates, delimiters.candidates(node, ctx))
				else
					local pair = pair_only and surround_bounds(node, id, ctx) or nil
					if not pair_only then
						pair = object_bounds(node, id, ctx)
					end
					if pair then
						candidates[#candidates + 1] = pair
					end
				end
			end
		end
		for _, pair in ipairs(candidates) do
			local first = ctx.inner and pair.inner_start or pair.outer_start
			local last = ctx.inner and pair.inner_end or pair.outer_end
			local candidate = { first[1], first[2], last[1], last[2] }
			if point or contains(candidate, reference) and not equal(candidate, reference) then
				local key = table.concat(candidate, ":")
				if not seen[key] then
					seen[key] = true
					if record then
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
