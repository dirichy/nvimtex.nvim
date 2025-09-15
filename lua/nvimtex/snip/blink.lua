local symbol = require("nvimtex.symbol.items")
local hl = require("nvimtex.highlight")
local source = {}

for key, value in pairs(symbol) do
	table.insert(source, {
		label = value.alias,
		filterText = value.alias,
		insertText = value.tex,
		kind_icon = value.conceal,
		kind_hl = hl[value.class],
	})
end

---@type blink.cmp.Source
local M = {}

function M.new(opts)
	local self = setmetatable({}, { __index = M })
	self.opts = opts
	return self
end

function M:enabled()
	return require("nvimtex.conditions.luasnip").in_math() and (vim.bo.filetype == "tex" or vim.bo.filetype == "latex")
end

---@param context blink.cmp.Context
function M:get_completions(context, callback)
	local backslash =
		vim.list_contains({ "\\" }, context.line:sub(context.bounds.start_col - 1, context.bounds.start_col - 1))
	callback({
		is_incomplete_forward = true,
		is_incomplete_backward = true,
		items = backslash and {} or source,
		context = context,
	})
end

---`newText` is used for `ghost_text`, thus it is set to the emoji name in `emojis`.
---Change `newText` to the actual emoji when accepting a completion.
-- function M:resolve(item, callback)
-- 	item = vim.deepcopy(item)
-- 	callback(item)
-- end

return M
