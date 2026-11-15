local parser = require("nvimtex.parser")
local nodes = require("nvimtex.parser.latex_nodes")
local ranges = require("nvimtex.textobject.ranges")
local M = {}

local openings = {
	["("] = ")",
	["["] = "]",
	["{"] = "}",
	["\\{"] = "\\}",
	langle = "rangle",
	lbrace = "rbrace",
	lvert = "rvert",
	lVert = "rVert",
	lfloor = "rfloor",
	lceil = "rceil",
	ulcorner = "urcorner",
}
local closings = {}
for _, close in pairs(openings) do
	closings[close] = true
end
local modifiers = {
	["\\left"] = "\\right",
	["\\mleft"] = "\\mright",
	["\\bigl"] = "\\bigr",
	["\\Bigl"] = "\\Bigr",
	["\\biggl"] = "\\biggr",
	["\\Biggl"] = "\\Biggr",
	["\\big"] = "\\big",
	["\\Big"] = "\\Big",
	["\\bigg"] = "\\bigg",
	["\\Bigg"] = "\\Bigg",
}

local function missing(node)
	return not node or type(node) == "userdata" and node:missing()
end

---@param node Nvimtex.LNode
---@param ctx Nvimtex.Textobject.Context
---@return Nvimtex.Textobject.Pair[]
function M.candidates(node, ctx)
	local result = {}
	local function append(outer, inside)
		if ranges.contains(outer, ctx.reference) then
			result[#result + 1] = ranges.boundaries(outer, inside)
		end
	end
	if nodes.group_delimiters(node) then
		local inside = ranges.interior(node)
		if inside then
			append(ranges.of(node), inside)
		end
	elseif node:type() == "math_delimiter" then
		-- A sized pair owns modifier, delimiter, body, modifier, delimiter.
		local modifier = node:child(0)
		local open = node:child(1)
		local close = node:child(node:child_count() - 2)
		local last = node:child(node:child_count() - 1)
		if
			modifier
			and open
			and close
			and last
			and modifiers[modifier:type()] == close:type()
			and not missing(modifier)
			and not missing(open)
			and not missing(close)
			and not missing(last)
		then
			local row, col = open:end_()
			local end_row, end_col = close:start()
			if not ranges.before(end_row, end_col, row, col) then
				append(ranges.of(node), { row, col, end_row, end_col })
			end
		end
	end
	-- Unsized math delimiters are sibling tokens rather than AST containers.
	-- Sized pairs/groups remain atomic, so their contents cannot cross this scope.
	local stack = {}
	for child in parser.iter_children(node, ctx.bufnr) do
		local token = nodes.command_name(ctx.bufnr, child) or child:type()
		if openings[token] then
			stack[#stack + 1] = { node = child, close = openings[token] }
		elseif closings[token] then
			local opening = stack[#stack]
			if opening and opening.close == token then
				stack[#stack] = nil
				local outer, finish = ranges.of(opening.node), ranges.of(child)
				append({ outer[1], outer[2], finish[3], finish[4] }, { outer[3], outer[4], finish[1], finish[2] })
			else
				stack = {}
			end
		end
	end
	return result
end

return M
