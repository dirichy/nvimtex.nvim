local M = {}
local api = vim.api
local highlights = require("nvimtex.highlight")

---@enum Nvimtex.RenderTree.Kind
local kind = {
	empty = 1,
	text = 2,
	concat = 3,
	highlight = 4,
	boundary = 5,
	atomic = 6,
	delimiter = 7,
}

---@alias Nvimtex.RenderTree.Mode "replace"|"plain"|"reveal"|"insert"
---`replace` consumes source, `plain` preserves it, `reveal` exposes it, and
---`insert` emits virtual text without consuming source.
M.mode = { replace = "replace", plain = "plain", reveal = "reveal", insert = "insert" }

---@class Nvimtex.RenderTree.Position
---@field [1] integer
---@field [2] integer

---@class Nvimtex.RenderTree
---@field kind Nvimtex.RenderTree.Kind
---@field width integer
---@field text? string
---@field mode? "replace"|"plain"|"reveal"|"insert"
---@field row? integer
---@field col? integer
---@field children? Nvimtex.RenderTree[]
---@field child? Nvimtex.RenderTree
---@field highlight? string|string[]
---@field before? integer delimiter depth adjustment before this leaf
---@field after? integer delimiter depth adjustment after this leaf
local RenderTree = {}
RenderTree.__index = RenderTree

---@type Nvimtex.RenderTree
local EMPTY = setmetatable({ kind = kind.empty, width = 0 }, RenderTree)
---Matches one UTF-8 codepoint without first allocating a character array.
local char_pattern = "[%z\1-\127\194-\244][\128-\191]*"

---@return -1|0|1
local function compare_position(left_row, left_col, right_row, right_col)
	if left_row ~= right_row then
		return left_row < right_row and -1 or 1
	end
	if left_col ~= right_col then
		return left_col < right_col and -1 or 1
	end
	return 0
end

---Return the shared identity element used by concat constructors.
---@return Nvimtex.RenderTree
function M.empty()
	return EMPTY
end

---Create a display leaf. Its source end is the next leaf's start.
---@param text string
---@param row integer
---@param col integer
---@param mode? Nvimtex.RenderTree.Mode
---@return Nvimtex.RenderTree
function M.text(text, row, col, mode)
	assert(type(text) == "string", "RenderTree.text: text must be a string")
	assert(type(row) == "number" and type(col) == "number", "RenderTree.text: start position is required")
	mode = mode or M.mode.replace
	assert(
		mode == M.mode.replace or mode == M.mode.plain or mode == M.mode.reveal or mode == M.mode.insert,
		"RenderTree.text: invalid mode"
	)
	return setmetatable({
		kind = kind.text,
		text = text,
		row = row,
		col = col,
		mode = mode,
		width = vim.fn.strdisplaywidth(text),
	}, RenderTree)
end

---Terminate the preceding leaf's source range without displaying text.
---@param row integer
---@param col integer
---@return Nvimtex.RenderTree
function M.boundary(row, col)
	assert(type(row) == "number" and type(col) == "number", "RenderTree.boundary: position is required")
	return setmetatable({ kind = kind.boundary, row = row, col = col, width = 0 }, RenderTree)
end

---A delimiter is a text leaf whose colour is resolved from the current
---delimiter depth while flattening. `before` and `after` change that depth on
---the corresponding side of the displayed text. Empty text is allowed.
---@param text string
---@param row integer
---@param col integer
---@param before? integer
---@param after? integer
---@param mode? "replace"|"reveal"
---@return Nvimtex.RenderTree
function M.delimiter(text, row, col, before, after, mode)
	assert(type(text) == "string", "RenderTree.delimiter: text must be a string")
	assert(type(row) == "number" and type(col) == "number", "RenderTree.delimiter: start position is required")
	mode = mode or M.mode.replace
	assert(mode == M.mode.replace or mode == M.mode.reveal, "RenderTree.delimiter: invalid mode")
	return setmetatable({
		kind = kind.delimiter,
		text = text,
		row = row,
		col = col,
		before = before or 0,
		after = after or 0,
		mode = mode,
		width = vim.fn.strdisplaywidth(text),
	}, RenderTree)
end

---Open a rainbow delimiter level before displaying this leaf.
---@param text string
---@param row integer
---@param col integer
---@param mode? "replace"|"reveal"
---@return Nvimtex.RenderTree
function M.delim_open(text, row, col, mode)
	return M.delimiter(text, row, col, 1, 0, mode)
end

---Display a separator at the current rainbow delimiter level.
---@param text string
---@param row integer
---@param col integer
---@param mode? "replace"|"reveal"
---@return Nvimtex.RenderTree
function M.delim_middle(text, row, col, mode)
	return M.delimiter(text, row, col, 0, 0, mode)
end

---Close the rainbow delimiter level after displaying this leaf.
---@param text string
---@param row integer
---@param col integer
---@param mode? "replace"|"reveal"
---@return Nvimtex.RenderTree
function M.delim_close(text, row, col, mode)
	return M.delimiter(text, row, col, 0, -1, mode)
end

---Collapse a possibly reordered subtree into one source-owned leaf.
---@param child Nvimtex.RenderTree
---@param row integer
---@param col integer
---@return Nvimtex.RenderTree
function M.atomic(child, row, col)
	assert(type(row) == "number" and type(col) == "number", "RenderTree.atomic: start position is required")
	return setmetatable({ kind = kind.atomic, child = child, row = row, col = col, width = child.width }, RenderTree)
end

---Concatenate two immutable trees, eliminating empty operands.
---@param left Nvimtex.RenderTree
---@param right Nvimtex.RenderTree
---@return Nvimtex.RenderTree
function M.concat(left, right)
	if left.kind == kind.empty then
		return right
	end
	if right.kind == kind.empty then
		return left
	end
	return setmetatable(
		{ kind = kind.concat, children = { left, right }, width = left.width + right.width },
		RenderTree
	)
end

---Build one shallow multiway concat instead of a deep binary chain.
---@param values Nvimtex.RenderTree[]
---@return Nvimtex.RenderTree
function M.concat_many(values)
	local children = {}
	local width = 0
	for _, value in ipairs(values) do
		if value.kind ~= kind.empty then
			children[#children + 1] = value
			width = width + value.width
		end
	end
	if #children == 0 then
		return EMPTY
	elseif #children == 1 then
		return children[1]
	end
	return setmetatable({ kind = kind.concat, children = children, width = width }, RenderTree)
end

---Force a highlight over a subtree without copying its leaves.
---@param child Nvimtex.RenderTree
---@param highlight string|string[]
---@return Nvimtex.RenderTree
function M.highlight(child, highlight)
	if child.kind == kind.empty then
		return child
	end
	assert(highlight ~= nil, "RenderTree.highlight: highlight is required")
	return setmetatable(
		{ kind = kind.highlight, child = child, highlight = highlight, width = child.width },
		RenderTree
	)
end

RenderTree.__add = M.concat
RenderTree.__concat = M.concat

---Transform UTF-8 codepoints and report whether every codepoint was mapped.
---@param text string
---@param map table<string,string>|fun(char:string):string?
---@param require_all boolean
---@return boolean, string
local function map_text(text, map, require_all)
	local valid = true
	local transformed = text:gsub(char_pattern, function(char)
		local replacement
		if type(map) == "table" then
			replacement = map[char]
		else
			replacement = map(char)
		end
		if replacement == nil then
			valid = false
			return char
		end
		return replacement
	end)
	return not require_all or valid, transformed
end

---@class Nvimtex.RenderTree.Leaf
---@field kind Nvimtex.RenderTree.Kind
---@field text? string
---@field chunks? [string,string|string[]?][]
---@field child? Nvimtex.RenderTree
---@field mode? "replace"|"plain"|"reveal"|"insert"
---@field row integer
---@field col integer
---@field highlight? string|string[]
---@field before? integer
---@field after? integer

---Visit flattened leaves without recursively growing Lua's call stack.
---Returning false from `visit` stops the traversal immediately.
---@param root Nvimtex.RenderTree
---@param visit fun(leaf:Nvimtex.RenderTree.Leaf):boolean?
---@return boolean
local function walk_leaves(root, visit)
	-- A concat frame stores only its parent and next child index. Parallel
	-- arrays carry highlight contexts without allocating a table per frame.
	---@type Nvimtex.RenderTree[]
	local parents = {}
	---@type integer[]
	local indices = {}
	---@type (string|string[]|nil)[]
	local parent_highlights = {}
	local depth = 0
	local node = root
	local forced_highlight
	local delimiter_depth = 0

	---Pop completed concat frames until another sibling is available.
	local function advance()
		while depth > 0 do
			local parent = parents[depth]
			local index = indices[depth]
			local child = parent.children[index]
			if child then
				indices[depth] = index + 1
				return child, parent_highlights[depth]
			end
			parents[depth] = nil
			indices[depth] = nil
			parent_highlights[depth] = nil
			depth = depth - 1
		end
		return nil, nil
	end

	while node do
		if node.kind == kind.empty then
			node, forced_highlight = advance()
		elseif node.kind == kind.text then
			local text = node.text
			local mode = node.mode
			local effective_highlight = forced_highlight
			if
				visit({
					kind = kind.text,
					text = text,
					mode = mode,
					row = node.row,
					col = node.col,
					highlight = effective_highlight,
				}) == false
			then
				return false
			end
			node, forced_highlight = advance()
		elseif node.kind == kind.delimiter then
			-- Resolve rainbow colour here so renderers need no mutable depth state.
			delimiter_depth = delimiter_depth + node.before
			assert(delimiter_depth >= 0, "RenderTree: delimiter depth became negative")
			if
				visit({
					kind = kind.delimiter,
					text = node.text,
					mode = node.mode,
					row = node.row,
					col = node.col,
					highlight = forced_highlight or highlights.rainbow(delimiter_depth),
					before = node.before,
					after = node.after,
				}) == false
			then
				return false
			end
			delimiter_depth = delimiter_depth + node.after
			assert(delimiter_depth >= 0, "RenderTree: delimiter depth became negative")
			node, forced_highlight = advance()
		elseif node.kind == kind.boundary then
			if
				visit({ kind = kind.boundary, row = node.row, col = node.col, highlight = forced_highlight }) == false
			then
				return false
			end
			node, forced_highlight = advance()
		elseif node.kind == kind.atomic then
			-- Atomic leaves discard child positions and retain only final chunks.
			if
				visit({
					kind = kind.atomic,
					row = node.row,
					col = node.col,
					chunks = node.child:to_virt_text(forced_highlight, true),
					child = node.child,
					highlight = forced_highlight,
				}) == false
			then
				return false
			end
			node, forced_highlight = advance()
		elseif node.kind == kind.concat then
			if #node.children == 0 then
				node, forced_highlight = advance()
			else
				depth = depth + 1
				parents[depth] = node
				indices[depth] = 2
				parent_highlights[depth] = forced_highlight
				node = node.children[1]
			end
		elseif node.kind == kind.highlight then
			-- The outermost highlight wins: keep a highlight already in force.
			forced_highlight = forced_highlight or node.highlight
			node = node.child
		end
	end
	assert(delimiter_depth == 0, "RenderTree: unbalanced delimiters")
	return true
end

---@param root Nvimtex.RenderTree
---@return Nvimtex.RenderTree.Leaf[]
local function collect_leaves(root)
	local leaves = {}
	walk_leaves(root, function(leaf)
		leaves[#leaves + 1] = leaf
	end)
	return leaves
end

---Attempt a display-only transform such as superscript or subscript.
---Return nil atomically if any visible codepoint cannot be transformed.
---@param map table<string,string>|fun(char:string):string?
---@param highlight? string|string[]
---@return Nvimtex.RenderTree?
function RenderTree:try_transform(map, highlight)
	local values = {}
	local valid = walk_leaves(self, function(leaf)
		if leaf.kind == kind.boundary then
			values[#values + 1] = M.boundary(leaf.row, leaf.col)
		elseif leaf.kind == kind.atomic then
			local transformed = leaf.child:try_transform(map, highlight)
			if not transformed then
				return false
			end
			values[#values + 1] = M.atomic(transformed, leaf.row, leaf.col)
		else
			local supported, transformed = map_text(leaf.text, map, true)
			if not supported then
				return false
			end
			local preserve = leaf.mode == M.mode.reveal
			local text = preserve and leaf.text or transformed
			local mode = leaf.mode == M.mode.plain and M.mode.replace or leaf.mode
			local node = leaf.kind == kind.delimiter
					and M.delimiter(text, leaf.row, leaf.col, leaf.before, leaf.after, mode)
				or M.text(text, leaf.row, leaf.col, mode)
			local effective_highlight = highlight or leaf.highlight or highlights.default
			values[#values + 1] = effective_highlight and M.highlight(node, effective_highlight) or node
		end
	end)
	return valid and M.concat_many(values) or nil
end

---@param result [string,string|string[]?][]
---@param text string
---@param highlight? string|string[]
local function append_chunk(result, text, highlight)
	if text ~= "" then
		result[#result + 1] = { text, highlight }
	end
end

---Flatten displayable leaves into Neovim `virt_text` chunks.
---@param default_highlight? string|string[]
---@param include_revealed? boolean include source-preserving leaves for atomic output
---@return [string,string|string[]?][]
function RenderTree:to_virt_text(default_highlight, include_revealed)
	local result = {}
	walk_leaves(self, function(leaf)
		if
			(leaf.kind == kind.text or leaf.kind == kind.delimiter)
			and (include_revealed or leaf.mode ~= M.mode.reveal and leaf.mode ~= M.mode.plain)
		then
			append_chunk(result, leaf.text, leaf.highlight or default_highlight)
		elseif leaf.kind == kind.atomic then
			for _, chunk in ipairs(leaf.chunks) do
				append_chunk(result, chunk[1], chunk[2] or default_highlight)
			end
		end
	end)
	return result
end

---Return the first resolved display highlight, if any.
---@return string|string[]|nil
function RenderTree:first_highlight()
	local result
	walk_leaves(self, function(leaf)
		if leaf.kind == kind.text or leaf.kind == kind.delimiter or leaf.kind == kind.atomic then
			result = leaf.highlight
			return false
		end
	end)
	return result
end

---Whether the subtree contains source that must remain explicitly visible.
---@return boolean
function RenderTree:has_reveal()
	local result = false
	walk_leaves(self, function(leaf)
		if leaf.kind == kind.atomic then
			if leaf.child:has_reveal() then
				result = true
				return false
			end
		elseif leaf.kind == kind.text and leaf.mode == M.mode.reveal then
			result = true
			return false
		end
	end)
	return result
end

---Return the first leaf position; traversal stops after that leaf.
---@return integer?, integer?
function RenderTree:source_start()
	local row, col
	walk_leaves(self, function(leaf)
		row, col = leaf.row, leaf.col
		return false
	end)
	return row, col
end

---Return the first non-whitespace byte column, or the line length.
---@param line string
---@return integer
local function first_nonblank(line)
	local byte = line:find("%S")
	return byte and byte - 1 or #line
end

---Split a replacement range at physical line boundaries. Continuation lines
---start after their indentation so conceal never changes the source layout.
---@class Nvimtex.RenderTree.Segment
---@field start_row integer
---@field start_col integer
---@field finish_row integer
---@field finish_col integer
---@field first boolean
---@param buffer integer
---@param start_row integer
---@param start_col integer
---@param finish_row integer
---@param finish_col integer
---@return Nvimtex.RenderTree.Segment[]
local function replacement_segments(buffer, start_row, start_col, finish_row, finish_col)
	if start_row == finish_row then
		return {
			{
				start_row = start_row,
				start_col = start_col,
				finish_row = finish_row,
				finish_col = finish_col,
				first = true,
			},
		}
	end
	local lines = api.nvim_buf_get_lines(buffer, start_row, finish_row + 1, false)
	local segments = {
		{
			start_row = start_row,
			start_col = start_col,
			finish_row = start_row,
			finish_col = #(lines[1] or ""),
			first = true,
		},
	}
	for row = start_row + 1, finish_row do
		local line = lines[row - start_row + 1] or ""
		local segment_finish_col = row == finish_row and finish_col or #line
		local segment_start_col = math.min(first_nonblank(line), segment_finish_col)
		if segment_start_col < segment_finish_col then
			segments[#segments + 1] = {
				start_row = row,
				start_col = segment_start_col,
				finish_row = row,
				finish_col = segment_finish_col,
				first = false,
			}
		end
	end
	return segments
end

---@class Nvimtex.RenderTree.EmitOptions
---@field default_highlight? string|string[]
---@field reveal? fun(start:Nvimtex.RenderTree.Position,finish:Nvimtex.RenderTree.Position,leaf:Nvimtex.RenderTree.Leaf):boolean?
---@field extmark? table<string,any>
---@field reveal_rows? integer[] inclusive zero-based rows to leave unconcealed

---Emit one extmark per display leaf, or per physical line for multiline
---replacements. A non-insert leaf ends at the following leaf's start.
---@param buffer integer
---@param namespace integer
---@param opts? Nvimtex.RenderTree.EmitOptions
---@return integer[] extmark ids
function RenderTree:emit_extmarks(buffer, namespace, opts)
	opts = opts or {}
	local leaves = collect_leaves(self)
	local extmark_ids = {}
	for index, leaf in ipairs(leaves) do
		if leaf.kind == kind.text or leaf.kind == kind.delimiter or leaf.kind == kind.atomic then
			-- Inserts are zero-width. Other leaves require a following boundary.
			local inserting = (leaf.kind == kind.text or leaf.kind == kind.delimiter) and leaf.mode == M.mode.insert
			local finish_row, finish_col
			if inserting then
				finish_row, finish_col = leaf.row, leaf.col
			else
				local next_leaf = assert(leaves[index + 1], "RenderTree.emit_extmarks: a final boundary is required")
				finish_row, finish_col = next_leaf.row, next_leaf.col
			end
			assert(
				inserting or compare_position(leaf.row, leaf.col, finish_row, finish_col) <= 0,
				"RenderTree.emit_extmarks: source positions must be monotonic; use an atomic render for reordered output"
			)
			local dynamically_revealed = opts.reveal
				and opts.reveal({ leaf.row, leaf.col }, { finish_row, finish_col }, leaf)
			local revealed = (leaf.kind == kind.text or leaf.kind == kind.delimiter)
				and (leaf.mode == M.mode.reveal or leaf.mode == M.mode.plain or dynamically_revealed)
			local empty_range = compare_position(leaf.row, leaf.col, finish_row, finish_col) == 0
			local empty = (leaf.kind == kind.text or leaf.kind == kind.delimiter) and leaf.text == ""
				or leaf.kind == kind.atomic and #leaf.chunks == 0
			if revealed and not dynamically_revealed and leaf.highlight and not empty_range then
				-- Revealed source can still carry its resolved display highlight.
				extmark_ids[#extmark_ids + 1] = api.nvim_buf_set_extmark(buffer, namespace, leaf.row, leaf.col, {
					end_row = finish_row,
					end_col = finish_col,
					hl_group = leaf.highlight,
					undo_restore = false,
					invalidate = true,
				})
			elseif not revealed and not (empty_range and empty) then
				-- Atomic leaves already own final chunks; normal leaves contribute one.
				local chunks = leaf.kind == kind.atomic and leaf.chunks
					or { { leaf.text, leaf.highlight or opts.default_highlight } }
				local segments = inserting
						and {
							{
								start_row = leaf.row,
								start_col = leaf.col,
								finish_row = finish_row,
								finish_col = finish_col,
								first = true,
							},
						}
					or replacement_segments(buffer, leaf.row, leaf.col, finish_row, finish_col)
				for _, segment in ipairs(segments) do
					local rows = opts.reveal_rows
					if not rows or segment.start_row < rows[1] or segment.start_row > rows[2] then
						-- Only the first physical line shows virtual text. Continuation
						-- segments merely conceal non-indentation source bytes.
						local extmark_opts = vim.tbl_deep_extend("force", {}, opts.extmark or {}, {
							end_row = segment.finish_row,
							end_col = segment.finish_col,
							virt_text = segment.first and chunks or {},
							virt_text_pos = "inline",
							undo_restore = false,
							invalidate = true,
						})
						if not inserting then
							extmark_opts.conceal = ""
						end
						extmark_ids[#extmark_ids + 1] = api.nvim_buf_set_extmark(
							buffer,
							namespace,
							segment.start_row,
							segment.start_col,
							extmark_opts
						)
					end
				end
			end
		end
	end
	return extmark_ids
end

M.RenderTree = RenderTree
return M
