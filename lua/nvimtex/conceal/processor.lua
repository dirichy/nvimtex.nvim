local State = require("nvimtex.conceal.state")
local extmark = require("nvimtex.conceal.extmark")
local renderer = require("nvimtex.conceal.renderer")
local definitions = require("nvimtex.conceal.definitions")
local command_symbols = require("nvimtex.conceal.command_name")
local parser = require("nvimtex.parser")
local latex_nodes = require("nvimtex.parser.latex_nodes")
local util = require("nvimtex.conceal.util")

local M = {}

---@enum Nvimtex.processor.feedback
M.feedback = { continue = 0, skip = 1, conceal = 2 }

local function conceal_node()
	return M.feedback.conceal
end

local function conceal_math(_, _, state)
	state:set("mmode", true)
	return M.feedback.conceal
end

local function skip_node()
	return M.feedback.skip
end

---@type table<string,fun(node:Nvimtex.LNode,source:number|string,state:Nvimtex.State):Nvimtex.processor.feedback>
M.processor = {
	ERROR = skip_node,
	line_comment = skip_node,
	new_command_definition = skip_node,
	source_file = function(node, source, state)
		local has_document = latex_nodes.find_document(node, source) ~= nil
		state:set("conceal", not has_document)
		state:set("preamble", has_document)
		return M.feedback.continue
	end,
	generic_environment = function(node, source, state)
		if latex_nodes.environment_name(source, node) == "document" then
			state:set("conceal", true)
			state:set("preamble", false)
		end
		return M.feedback.continue
	end,
	generic_command = function(node, source)
		local name = latex_nodes.command_name(source, node)
		if name and (command_symbols[name] or renderer.command_spec(name, source)) then
			return M.feedback.conceal
		end
		return M.feedback.continue
	end,
	inline_formula = conceal_math,
	displayed_equation = conceal_math,
	math_environment = conceal_math,
	["\\("] = conceal_node,
	["\\)"] = conceal_node,
	["\\["] = conceal_node,
	["\\]"] = conceal_node,
	subscript = conceal_node,
	superscript = conceal_node,
}

---@type table<integer,integer[]>
local cursor_render_extmarks = {}

---Neovim's extmark query includes its end position; syntax ranges do not.
---@param buffer integer
---@param namespace integer
---@param node Nvimtex.LNode
---@return table[]
local function marks_in_node(buffer, namespace, node)
	local start_row, start_col, end_row, end_col = node:range()
	if start_row == end_row and start_col == end_col then
		return {}
	end
	local finish = end_col > 0 and { end_row, end_col - 1 } or { end_row - 1, -1 }
	return vim.api.nvim_buf_get_extmarks(buffer, namespace, { start_row, start_col }, finish, {})
end

---Remove only the previous interactive render. The next viewport pass restores
---it without a cursor context, while other cached math trees remain intact.
---@param buffer integer
function M.begin_cursor_refresh(buffer)
	for _, id in ipairs(cursor_render_extmarks[buffer] or {}) do
		pcall(vim.api.nvim_buf_del_extmark, buffer, extmark.ns_id.conceal, id)
	end
	cursor_render_extmarks[buffer] = nil
end

---Render a complete math tree when new, under the cursor, or on revealed lines.
---The refresh entry runs in the target window, so its cursor belongs to buffer.
---@param node Nvimtex.LNode
---@param buffer integer
---@param opts Nvimtex.Processor.Options
local function render_tree(node, buffer, opts)
	local namespace = extmark.ns_id.conceal
	local marks = marks_in_node(buffer, namespace, node)
	local cursor
	if vim.api.nvim_get_current_buf() == buffer then
		local position = vim.api.nvim_win_get_cursor(0)
		local row, col = position[1] - 1, position[2]
		if vim.treesitter.node_contains(node, { row, col, row, col + 1 }) then
			cursor = { row, col }
		end
	end
	local start_row, _, end_row, end_col = node:range()
	local rows = opts.reveal_rows
	local reveal = rows and start_row <= rows[2] and (end_row > rows[1] or end_row == rows[1] and end_col > 0)
	if cursor or reveal then
		for _, mark in ipairs(marks) do
			vim.api.nvim_buf_del_extmark(buffer, namespace, mark[1])
		end
		local ids = renderer.render_node(node, buffer, { cursor = cursor }):emit_extmarks(buffer, namespace, {
			reveal_rows = rows,
		})
		cursor_render_extmarks[buffer] = vim.list_extend(cursor_render_extmarks[buffer] or {}, ids)
	elseif #marks == 0 then
		renderer.render_node(node, buffer):emit_extmarks(buffer, namespace)
	end
end

---@class Nvimtex.Processor.Options
---@field binary_threshold? integer minimum child count before binary seeking
---@field lookbehind? integer children retained before the binary-search result
---@field reveal_rows? integer[] inclusive zero-based rows to leave unconcealed

---@param node Nvimtex.LNode
---@param source number|string
---@param state Nvimtex.State
---@param viewport_top? integer
---@param viewport_bottom? integer
---@param opts? Nvimtex.Processor.Options
function M.default_processor(node, source, state, viewport_top, viewport_bottom, opts)
	opts = opts or {}
	if viewport_top == nil then
		viewport_top, viewport_bottom = util.viewport()
	end
	if not util.node_in_screen(node, viewport_top, viewport_bottom) then
		return
	end
	local handler = M.processor[node:type()]
	local feedback = handler and handler(node, source, state) or M.feedback.continue
	if feedback == M.feedback.continue or (feedback == M.feedback.conceal and not state:get("conceal")) then
		for child in
			parser.iter_children(node, source, {
				start_row = viewport_top,
				end_row = viewport_bottom,
				binary_threshold = opts.binary_threshold,
				lookbehind = opts.lookbehind,
			})
		do
			state:addUndoPoint()
			M.default_processor(child, source, state, viewport_top, viewport_bottom, opts)
			state:undo()
		end
	elseif feedback == M.feedback.conceal and type(source) == "number" then
		render_tree(node, source, opts)
	end
end

-- Keep existing entry points while their implementations live with their owners.
M.find_document = latex_nodes.find_document
M.scan_preamble = definitions.scan

---@param buffer integer
function M.detach(buffer)
	cursor_render_extmarks[buffer] = nil
	definitions.clear(buffer)
end

---@param root Nvimtex.LNode
---@param source number|string
---@param viewport_top integer
---@param viewport_bottom integer
---@param opts? Nvimtex.Processor.Options
function M.process_conceal(root, source, viewport_top, viewport_bottom, opts)
	M.default_processor(root, source, State:new(), viewport_top, viewport_bottom, opts)
end

return M
