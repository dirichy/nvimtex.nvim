local nodes = require("nvimtex.parser.latex_nodes")
local M = {}

function M.before(ar, ac, br, bc)
	return ar < br or ar == br and ac < bc
end

function M.equal(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

---@param outer Range4
---@param reference Range4
---@return boolean
function M.contains(outer, reference)
	if M.before(reference[1], reference[2], outer[1], outer[2]) then
		return false
	end
	if reference[1] == reference[3] and reference[2] == reference[4] then
		return M.before(reference[1], reference[2], outer[3], outer[4])
	end
	return not M.before(outer[3], outer[4], reference[3], reference[4])
end

---@param node Nvimtex.LNode
---@return Range4
function M.of(node)
	return { node:range() }
end

---Use actual syntax boundaries, preserving newlines and UTF-8 byte offsets.
---An absent/missing closing token cannot define a safe inside selection.
---@param node Nvimtex.LNode
---@return Range4?
function M.interior(node)
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
	if M.before(end_row, end_col, row, col) then
		return nil
	end
	return { row, col, end_row, end_col }
end

---@param outer Range4
---@param inside Range4
---@return Nvimtex.Textobject.Pair
function M.boundaries(outer, inside)
	return {
		outer_start = { outer[1], outer[2] },
		inner_start = { inside[1], inside[2] },
		inner_end = { inside[3], inside[4] },
		outer_end = { outer[3], outer[4] },
	}
end

return M
