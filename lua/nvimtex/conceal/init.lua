local M = {}
local processor = require("nvimtex.conceal.processor")
local extmark = require("nvimtex.conceal.extmark")
M.enabled = true
local refresh_timers = {}

local function clear_marks(buffer)
	processor.begin_cursor_refresh(buffer)
	for _, namespace in pairs(extmark.ns_id) do
		vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
	end
end

function M.toggle()
	M.enabled = not M.enabled
	for buffer in pairs(M.have_setup) do
		if vim.api.nvim_buf_is_valid(buffer) then
			if M.enabled then
				M.refresh(buffer)
			else
				clear_marks(buffer)
			end
		end
	end
end
M.have_setup = {}

M.config = {
	processor = {},
	extmark = {},
	conceal_cursor = "nvic",
	filetypes = { "tex", "plaintex", "latex", "markdown", "rmd", "quarto" },
	latex_filetypes = { tex = true, plaintex = true, latex = true },
	refresh_events = { "InsertLeave", "BufWritePost" },
	local_refresh_events = { "TextChangedI", "TextChanged" },
	cursor_refresh_events = { "CursorMovedI", "CursorMoved" },
	debounce = 50,
	viewport_margin = 3,
	binary_threshold = 16,
	child_lookbehind = 2,
}

---@class Nvimtex.Conceal.BufferState
---@field preamble_dirty boolean
---@field preamble_end? integer zero-based document start row
---@field changedtick? integer source version represented by the extmarks

---@type table<integer,Nvimtex.Conceal.BufferState>
M.buffer_state = {}

local function collect_latex_roots(langtree, roots, seen)
	if not langtree then
		return
	end

	if langtree:lang() == "latex" then
		for _, tree in ipairs(langtree:trees() or {}) do
			local root = tree:root()
			local key = table.concat({ root:range() }, ":")
			if not seen[key] then
				seen[key] = true
				roots[#roots + 1] = root
			end
		end
	end

	for _, child in pairs(langtree:children() or {}) do
		collect_latex_roots(child, roots, seen)
	end
end

local function filetype_enabled(filetype)
	return vim.tbl_contains(M.config.filetypes, filetype)
end

---Return a valid window displaying the buffer, preferring the current window.
---@param buffer integer
---@return integer?
local function window_for_buffer(buffer)
	-- Viewport-dependent work needs an actual window, not merely a valid buffer.
	local current = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(current) == buffer then
		return current
	end
	for _, win in ipairs(vim.fn.win_findbuf(buffer)) do
		if vim.api.nvim_win_is_valid(win) then
			return win
		end
	end
end

---@param buffer? integer
---@return Nvimtex.LNode[]
function M.latex_roots(buffer)
	buffer = buffer or vim.api.nvim_get_current_buf()
	local roots = {}
	local seen = {}
	local ft = vim.api.nvim_get_option_value("filetype", { scope = "local", buf = buffer })

	if M.config.latex_filetypes[ft] then
		local ok, parser = pcall(vim.treesitter.get_parser, buffer, "latex")
		if ok then
			local parsed, trees = pcall(function()
				return parser:parse()
			end)
			if parsed then
				for _, tree in ipairs(trees or {}) do
					roots[#roots + 1] = tree:root()
				end
			end
		end
		return roots
	end

	local ok, parser = pcall(vim.treesitter.get_parser, buffer)
	if ok then
		local win = window_for_buffer(buffer)
		if not win then
			return roots
		end
		local top, bottom = require("nvimtex.conceal.util").viewport(win)
		bottom = bottom + 2
		local parsed = pcall(function()
			parser:parse({ { top, bottom } })
		end)
		if parsed then
			collect_latex_roots(parser, roots, seen)
		end
	end
	return roots
end

local function refresh_now(buffer, root)
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return
	end
	if not M.enabled then
		clear_marks(buffer)
		return
	end
	local win = window_for_buffer(buffer)
	if not win then
		return
	end
	-- Renderer cursor context and window options must belong to this buffer.
	vim.api.nvim_win_call(win, function()
		vim.wo.conceallevel = 2
		if M.config.conceal_cursor then
			vim.wo.concealcursor = M.config.conceal_cursor
		end
		local state = M.buffer_state[buffer]
		local tick = vim.api.nvim_buf_get_changedtick(buffer)
		if not state or state.changedtick ~= tick then
			-- Extmarks move with edits, but their generated text does not update.
			clear_marks(buffer)
			if state then
				state.changedtick = tick
			end
		end
		vim.api.nvim_buf_clear_namespace(buffer, extmark.ns_id.fast, 0, -1)
		local roots = root and { root } or M.latex_roots(buffer)
		processor.begin_cursor_refresh(buffer)
		local ft = vim.bo[buffer].filetype
		local top, bottom = require("nvimtex.conceal.util").viewport(win)
		top = math.max(top - M.config.viewport_margin, 0)
		bottom = math.min(bottom + M.config.viewport_margin, vim.api.nvim_buf_line_count(buffer) - 1)
		for _, latex_root in ipairs(roots) do
			local document
			if M.config.latex_filetypes[ft] then
				document = processor.find_document(latex_root, buffer)
				if state and state.preamble_dirty then
					processor.scan_preamble(latex_root, buffer, document)
					state.preamble_end = document and document:start() or nil
					state.preamble_dirty = false
					clear_marks(buffer)
				end
			end
			processor.process_conceal(document or latex_root, buffer, top, bottom, {
				binary_threshold = M.config.binary_threshold,
				lookbehind = M.config.child_lookbehind,
			})
		end
	end)
end

---Cancel pending work before replacing a timer or releasing a buffer.
---@param buffer integer
local function cancel_refresh(buffer)
	local timer = refresh_timers[buffer]
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	refresh_timers[buffer] = nil
end

---Independent timers prevent activity in one buffer from cancelling another.
---@param buffer? integer
---@param root? Nvimtex.LNode
function M.refresh(buffer, root)
	buffer = buffer and buffer ~= 0 and buffer or vim.api.nvim_get_current_buf()
	cancel_refresh(buffer)
	refresh_timers[buffer] = vim.defer_fn(function()
		refresh_timers[buffer] = nil
		refresh_now(buffer, root)
	end, M.config.debounce)
end

local function detach(buffer)
	cancel_refresh(buffer)
	processor.detach(buffer)
	M.buffer_state[buffer] = nil
	M.have_setup[buffer] = nil
	pcall(vim.api.nvim_del_augroup_by_name, "nvimtex.conceal." .. buffer)
end

---Initialize conceal for a buffer; missing parsers can be retried on BufEnter.
---@param buffer? integer|{buf:integer}
function M.setup_buf(buffer)
	buffer = buffer and (type(buffer) == "number" and buffer or buffer.buf) or vim.api.nvim_get_current_buf()
	buffer = buffer ~= 0 and buffer or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return
	end
	if M.have_setup[buffer] then
		M.refresh(buffer)
		return
	end
	local ft = vim.bo[buffer].filetype
	if not filetype_enabled(ft) then
		return
	end
	local ok, parser = pcall(vim.treesitter.get_parser, buffer, M.config.latex_filetypes[ft] and "latex" or nil)
	if not ok or not parser then
		return
	end
	M.have_setup[buffer] = true
	M.buffer_state[buffer] = { preamble_dirty = true }
	vim.api.nvim_buf_attach(buffer, false, {
		on_lines = function(_, changed_buffer, _, first_line)
			local state = M.buffer_state[changed_buffer]
			if state and (state.preamble_end == nil or first_line <= state.preamble_end) then
				state.preamble_dirty = true
			end
		end,
		on_reload = function(_, changed_buffer)
			local state = M.buffer_state[changed_buffer]
			if state then
				state.preamble_dirty = true
				state.changedtick = nil
			end
			M.refresh(changed_buffer)
		end,
		on_detach = function(_, detached_buffer)
			detach(detached_buffer)
		end,
	})
	local group = vim.api.nvim_create_augroup("nvimtex.conceal." .. buffer, { clear = true })
	local events = { "BufWinEnter", "WinEnter" }
	for _, configured in ipairs({
		M.config.refresh_events,
		M.config.local_refresh_events,
		M.config.cursor_refresh_events,
	}) do
		for _, event in ipairs(configured or {}) do
			if not vim.tbl_contains(events, event) then
				events[#events + 1] = event
			end
		end
	end
	vim.api.nvim_create_autocmd(events, {
		group = group,
		buffer = buffer,
		callback = function()
			M.refresh(buffer)
		end,
	})
	vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
		group = group,
		callback = function()
			if window_for_buffer(buffer) then
				M.refresh(buffer)
			end
		end,
	})
	M.refresh(buffer)
end

---@param buffer? integer
function M.forceRefresh(buffer)
	buffer = buffer and buffer ~= 0 and buffer or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_loaded(buffer) then
		return
	end
	clear_marks(buffer)
	local state = M.buffer_state[buffer]
	if state then
		state.preamble_dirty = true
	end
	M.refresh(buffer)
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	local group = vim.api.nvim_create_augroup("nvimtex.conceal", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = M.config.filetypes,
		callback = function(buffer)
			vim.schedule(function()
				M.setup_buf(buffer)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(buffer)
			local ft = vim.api.nvim_get_option_value("filetype", { scope = "local", buf = buffer.buf })
			if not filetype_enabled(ft) then
				return
			end
			vim.schedule(function()
				M.setup_buf(buffer)
			end)
		end,
	})
	local buffer = vim.api.nvim_get_current_buf()
	if filetype_enabled(vim.api.nvim_get_option_value("filetype", { scope = "local", buf = buffer })) then
		vim.schedule(function()
			M.setup_buf(buffer)
		end)
	end
end

return M
