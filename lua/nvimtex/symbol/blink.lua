local symbol = require("nvimtex.symbol.items")
local hl = require("nvimtex.highlight")
local source = {}

for _, value in pairs(symbol) do
	if type(value.tex) == "string" then
		table.insert(source, {
			label = value.tex,
			filterText = value.tex:sub(2, -1),
			insertText = value.tex,
			kind_icon = type(value.conceal) == "string" and value.conceal,
			-- autosnip = value.autosnip,
			kind_hl = hl[value.class],
		})
	end
end

---@type blink.cmp.Source
local M = {}

function M.new(opts)
	local self = setmetatable({}, { __index = M })
	self.opts = opts
	return self
end

function M:enabled()
	return vim.bo.filetype == "tex" or vim.bo.filetype == "latex"
end

local range
---@param context blink.cmp.Context
function M:get_completions(context, callback)
	local is_char_trigger = vim.list_contains(
		self:get_trigger_characters(),
		context.line:sub(context.bounds.start_col - 1, context.bounds.start_col - 1)
	)
	-- range = {
	-- 	start = { line = context.cursor[1] - 1, character = context.bounds.start_col - 2 },
	-- 	-- ["end"] = { line = context.cursor[1] - 1, character = context.cursor[2] - 1 },
	-- }
	callback({
		is_incomplete_forward = true,
		is_incomplete_backward = true,
		items = is_char_trigger and source or {},
		context = context,
	})
end

---`newText` is used for `ghost_text`, thus it is set to the emoji name in `emojis`.
---Change `newText` to the actual emoji when accepting a completion.
-- function M:resolve(item, callback)
-- 	item = vim.deepcopy(item)
-- 	-- item.textEdit = {
-- 	-- 	newText = "\\" .. item.filterText,
-- 	-- 	-- range = range,
-- 	-- }
-- 	callback(item)
-- end

function M:get_trigger_characters()
	-- return {}
	return { "\\" }
end
return M
