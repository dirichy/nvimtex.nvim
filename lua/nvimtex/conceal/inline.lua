---@class Nvimtex.Inline.atom
---@field [1] string
---@field [2] string|string[]
---@alias Nvimtex.Inline.data Nvimtex.Inline.atom[]
---@class Nvimtex.Inline
---@field node Nvimtex.LNode?
---@field type string?
---@field width integer
---@field [table] Nvimtex.Inline.data
local Inline = {}
local hl = require("nvimtex.highlight")
Inline.__index = Inline
local function get_length(data)
	if not data then
		return 0
	end
	local length = 0
	for _, value in ipairs(data) do
		length = length + vim.fn.strdisplaywidth(value[1])
	end
	return length
end
local subscript_tbl = require("nvimtex.latex.mathstyle").subscript
local superscript_tbl = require("nvimtex.latex.mathstyle").superscript
local private_data = {}

---@param data string|Nvimtex.Inline.atom|Nvimtex.Inline.data|Nvimtex.Inline
---@param copy boolean? will copy data by vim.deepcopy, so edit new object will not change old's. default is true.
---@return Nvimtex.Inline
---@overload fun(self:Nvimtex.Inline,source:number|string,lnode:Nvimtex.LNode):Nvimtex.Inline
function Inline:new(data, copy, highlight)
	if copy == nil then
		copy = true
	end
	if type(copy) ~= "boolean" then
		data = { { vim.treesitter.get_node_text(copy, data), highlight or hl.default } }
	end
	if not data then
		data = {}
	end
	if type(data) == "string" then
		data = { { data, "Normal" } }
	end
	if data[private_data] then
		if copy then
			local res = {}
			for key, value in pairs(data) do
				res[key] = vim.deepcopy(value)
			end
			return setmetatable(res, Inline)
		else
			return data
		end
	end
	if type(data[1]) == "string" then
		data = { data }
	end
	local inline = { [private_data] = copy and vim.deepcopy(data) or data }
	inline.width = get_length(data)
	setmetatable(inline, Inline)
	return inline
end

function Inline:show()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 5,
		col = 10,
		width = self.width,
		height = 2,
		style = "minimal",
		border = "rounded",
	})
	-- local virt_lines = {}
	-- for i = #self[private_data] - self.height + 1, #self[private_data] do
	-- 	virt_lines[i + self.height - #self[private_data]] = self[private_data][i]
	-- end
	vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("nvimtex"), 0, 0, {
		virt_lines = { self[private_data] },
	})
	vim.keymap.set("n", "q", ":q<cr>", { buffer = buf, remap = false })
end

function Inline:atom(n)
	return self[private_data][n]
end

---@param right integer
---@param left integer?
---@return Nvimtex.Inline
---@overload fun(self:Nvimtex.Inline,right:integer,left:nil):Nvimtex.Inline when left is nil, will split right into right and left equally.
function Inline:add_blank_col(right, left)
	if not right then
		return self
	end
	if not left then
		left = math.floor(right / 2)
		right = right - left
	end
	if right + left == 0 then
		return self
	end
	if left > 0 then
		table.insert(self[private_data], 1, { string.rep(" ", left), {} })
	end
	if right > 0 then
		table.insert(self[private_data], { string.rep(" ", right), {} })
	end
	self.width = self.width + left + right
	return self
end
--- add some Nvimtex.Inlines
---@vararg Nvimtex.Inline|Nvimtex.Inline.data|Nvimtex.Inline.atom
---@return Nvimtex.Inline
function Inline:append(...)
	local c = self
	local adds = { ... }
	if #adds == 0 then
		return c
	end
	c.type = adds[#adds].type
	for _, add in ipairs(adds) do
		if type(add[1]) == "string" then
			table.insert(c[private_data], add)
			c.width = c.width + vim.fn.strdisplaywidth(add[1])
		else
			local data = add[private_data] or add
			for _, v in ipairs(data) do
				table.insert(c[private_data], v)
			end
			c.width = c.width + add.width or get_length(data)
		end
	end
	return c
end

--- add two grid
---@param a Nvimtex.Inline
---@param b Nvimtex.Inline
---@return Nvimtex.Inline
function Inline.__add(a, b)
	local c = Inline:new(a)
	c.type = b.type
	for _, v in ipairs(b[private_data]) do
		table.insert(c[private_data], v)
	end
	c.width = c.width + b.width
	return c
end

Inline.__concat = Inline.__add

function Inline:style(style, copy, highlight)
	local c = copy and Inline:new(self) or self
	if style then
		local f
		local flag = true
		if type(style) == "table" then
			f = function(char)
				if style[char] then
					return style[char]
				else
					flag = false
					return char
				end
			end
		else
			f = function(char)
				local res = style(char)
				if res then
					return res
				else
					flag = false
					return char
				end
			end
		end
		for _, value in ipairs(c[private_data]) do
			value[1] = string.gsub(value[1], "[%z\1-\127\194-\244][\128-\191]*", f)
			value[2] = highlight or value[2]
			if not flag then
				return nil
			end
		end
	elseif highlight then
		for _, value in ipairs(c[private_data]) do
			value[2] = highlight or value[2]
		end
	end
	return c
end

function Inline:superscript(copy)
	return self:style(superscript_tbl, copy)
end

function Inline:subscript(copy)
	return self:style(subscript_tbl, copy)
end

Inline.__mod = function(a, b)
	return a:style(b, true)
end

function Inline.__pow(a, b)
	local c = b % superscript_tbl
	if c then
		return a:append(c)
	else
		return a:append(Inline:new({ "^{", "Normal" }), c, Inline:new({ "}", "Normal" }))
	end
end
function Inline.__div(a, b)
	local c = b % subscript_tbl
	if c then
		return a:append(c)
	else
		return a:append(Inline:new({ "_{", "Normal" }), c, Inline:new({ "}", "Normal" }))
	end
end

function Inline:first_hl()
	local first_item = self[private_data][1]
	return first_item and first_item[2]
end

local extmark_config = { virt_text_pos = "inline", invalidate = true, undo_restore = false, conceal = "" }
function Inline:conceal(buffer, range, ns_id, extmark_opt, other_opt)
	local text = self
	local start_row, start_col, end_row, end_col
	extmark_opt = extmark_opt or {}
	other_opt = other_opt or {}
	ns_id = ns_id or vim.api.nvim_create_namespace("nvimtex")
	if range[1] then
		start_row, start_col, end_row, end_col = unpack(range)
	elseif range.node then
		start_row, start_col, end_row, end_col = range.node:range()
		if range.offset then
			start_row = start_row + range.offset[1]
			start_col = start_col + range.offset[2]
			end_row = end_row + range.offset[3]
			end_col = end_col + range.offset[4]
		end
	else
		start_row, start_col, end_row, end_col = range:range()
	end
	local opts
	if extmark_opt then
		opts = vim.tbl_deep_extend("force", extmark_config, extmark_opt)
	else
		opts = vim.deepcopy(extmark_config)
	end
	if other_opt.virtline then
		local win_id = vim.api.nvim_get_current_win()
		local textoff = vim.fn.getwininfo(win_id)[1].textoff
		local screenpos = vim.fn.screenpos(win_id, start_row, start_col).col
		text:add_blank_col(0, screenpos - textoff)
		opts.virt_lines = { text[private_data] }
		opts.conceal = nil
	else
		opts.virt_text = text[private_data]
	end
	opts.end_row = end_row
	opts.end_col = end_col
	return vim.api.nvim_buf_set_extmark(buffer, ns_id, start_row, start_col, opts)
end

return Inline
