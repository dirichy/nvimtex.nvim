local parser = require("nvimtex.parser")
local ranges = require("nvimtex.textobject.ranges")
local M = {}

M.types = {
	S = {
		part = true,
		chapter = true,
		section = true,
		subsection = true,
		subsubsection = true,
		paragraph = true,
		subparagraph = true,
	},
	i = { enum_item = true },
}

-- Include indentation only when the heading starts a line of its own.
---@param bufnr integer
---@param row integer
---@param col integer
---@return integer
local function line_start(bufnr, row, col)
	local prefix = vim.api.nvim_buf_get_text(bufnr, row, 0, row, col, {})[1] or ""
	return prefix:match("^%s*$") and 0 or col
end

-- Keep around ranges through the separator before the next sibling. A nested
-- last section/item inherits its container's boundary, not the whole document.
---@param node Nvimtex.LNode
---@param following? Nvimtex.LNode
---@param limit Nvimtex.Textobject.Point
---@param bufnr integer
---@return Range4
local function extent(node, following, limit, bufnr)
	local outer = ranges.of(node)
	outer[2] = line_start(bufnr, outer[1], outer[2])
	if following then
		local row, col = following:start()
		outer[3], outer[4] = row, line_start(bufnr, row, col)
	else
		outer[3], outer[4] = limit[1], limit[2]
	end
	return outer
end

---@param node Nvimtex.LNode
---@param outer Range4
---@param bufnr integer
---@return Range4?
local function body(node, outer, bufnr)
	local heading = node:child(0)
	if not heading then
		return nil
	end
	local start_row, start_col = heading:end_()
	local section = M.types.S[node:type()]
	for index = 1, node:child_count() - 1 do
		local child = node:child(index)
		local kind = child and child:type() or ""
		if child and (kind:match("^brack_group") or section and kind:match("^curly_group")) then
			start_row, start_col = child:end_()
			if section and kind:match("^curly_group") then
				break
			end
		else
			break
		end
	end
	local end_row, end_col = outer[3], outer[4]
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
	-- VimTeX's inside selections exclude whitespace around the body.
	local first, last
	for index, line in ipairs(lines) do
		local row = start_row + index - 1
		local lo = row == start_row and start_col or 0
		local hi = row == end_row and end_col or #line
		local text = line:sub(lo + 1, hi)
		local left, right = text:find("%S"), text:match(".*()%S")
		if left then
			first = first or { row, lo + left - 1 }
			last = { row, lo + right }
		end
	end
	first = first or { start_row, start_col }
	last = last or first
	return { first[1], first[2], last[1], last[2] }
end

---@param root TSNode
---@param ctx Nvimtex.Textobject.Context
---@param id Nvimtex.Textobject.Id
---@return Nvimtex.Textobject.Pair[]
function M.candidates(root, ctx, id)
	local types = M.types[id]
	if not types then
		return {}
	end
	local result, node, outer = {}, root, ranges.of(root)
	while node do
		if types[node:type()] then
			local inside = body(node, outer, ctx.bufnr)
			if inside then
				table.insert(result, 1, ranges.boundaries(outer, inside))
			end
		end
		local children = {}
		for child in parser.iter_children(node, ctx.bufnr) do
			children[#children + 1] = child
		end
		local selected, selected_range
		for index, child in ipairs(children) do
			local child_range = ranges.of(child)
			if M.types.S[child:type()] or M.types.i[child:type()] then
				child_range = extent(child, children[index + 1], { outer[3], outer[4] }, ctx.bufnr)
			end
			if ranges.contains(child_range, ctx.reference) then
				selected, selected_range = child, child_range
				break
			end
		end
		node, outer = selected, selected_range
	end
	return result
end

return M
