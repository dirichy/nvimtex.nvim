---@alias Nvimtex.concealer fun(lnode:Nvimtex.LNode,source:number|string,state:Nvimtex.State):Nvimtex.Inline
---@alias Nvimtex.concealer.creater fun(...:any):Nvimtex.concealer
local M = {}
local State = require("nvimtex.conceal.state")
local inline = require("nvimtex.conceal.inline")
local concealer = M
local mathstyle = require("nvimtex.latex.mathstyle")
local LNode = require("nvimtex.parser.lnode")
local hl = require("nvimtex.highlight")
local parser = require("nvimtex.parser")

---@type Nvimtex.concealer
function M.direct_concealer(lnode, source, state)
	return inline:new(source, lnode)
end
---@type Nvimtex.concealer
function M.fallback_concealer(lnode, source, state)
	if lnode:child_count() == 0 then
		return M.direct_concealer(lnode, source, state)
	end
	local res = inline:new({})
	for node in parser.iter_children(lnode, source) do
		res:append(M.conceal_node_with_state(node, source, state, M.default_concealer))
	end
	return res
end
---@param lnode Nvimtex.LNode
---@param state Nvimtex.State
---@param source number|string
---@param p fun(...:any):Nvimtex.Inline
function M.conceal_node_with_state(lnode, source, state, p)
	state:addUndoPoint()
	local res = p(lnode, source, state)
	state:undo()
	return res
end

---@type Nvimtex.concealer
function M.default_concealer(lnode, source, state)
	local type = lnode:type()
	if M.concealer[type] then
		return M.conceal_node_with_state(lnode, source, state, M.concealer[type])
	else
		return M.conceal_node_with_state(lnode, source, state, M.fallback_concealer)
	end
end

---@type Nvimtex.concealer
function M.conceal_arg_without_bracket(lnode, source, state)
	if lnode:child_count() == 0 then
		return M.direct_concealer(lnode, source, state)
	end
	local ntype = lnode:type()
	if string.match(ntype, "^curly_group") or ntype == "brack_group" then
		local iter = parser.iter_children(lnode, source)
		local prev_node
		iter()
		local res = inline:new({})
		prev_node = iter()
		for node in iter do
			res:append(M.conceal_node_with_state(prev_node, source, state, M.default_concealer))
			prev_node = node
		end
		return res
	end
	return M.default_concealer(lnode, source, state)
end
---@type Nvimtex.concealer.creater
function M.style(map, highlight)
	local f
	if type(map) == "string" then
		f = function(char)
			return char .. map
		end
	else
		f = map
	end
	return function(node, source, state)
		local arg_nodes = node:field("arg")
		if #arg_nodes == 0 then
			return M.fallback_concealer(node, source, state)
		end
		local arg_node = arg_nodes[1]
		local text = M.conceal_arg_without_bracket(arg_node, source, state)
		return text:style(f, true, highlight) or text
	end
end

---@type Nvimtex.concealer.creater
function M.delim(...)
	local delims = { ... }
	local n = #delims
	return M.create_command_concealer({
		prev = function(state)
			state:set("delim", state:get("delim") + 1)
		end,
		concealer = function(args, state)
			local highlight = hl.rainbow(state:get("delim"))
			local res = inline:new({ delims[1], highlight })
			for index, value in ipairs(args) do
				res:append(value)
				res:append({ delims[index + 1], highlight })
			end
		end,
	}, n - 1)
end

---@type Nvimtex.concealer.creater
function M.script(script_char, map, highlight)
	---@param node TSNode
	return function(node, source, state)
		local arg_node = node:named_child(0)
		if not arg_node then
			return
		end
		local text
		local delim_deepth = state:get("delim")
		state:set("delim", delim_deepth + 1)
		if arg_node:type() == "command_name" then
			text = M.concealer.command_name(arg_node, source, state)
		else
			text = M.conceal_arg_without_bracket(arg_node, source, state)
		end
		local new_text = text:style(map, true, highlight)
			or inline
				:new({ script_char .. "{", hl.rainbow(delim_deepth) })
				:append(text)
				:append({ "}", hl.rainbow(delim_deepth) })
		return new_text
	end
end

--- get inline conceal of all arg node, then pass them to fn
---@param fn Nvimtex.generic_command.concealer
---@param narg number
---@param default Nvimtex.LNode?
---@return Nvimtex.concealer
function M.create_command_concealer(fn, narg, default)
	local prev
	if type(fn) == "table" then
		prev = fn.prev
		fn = fn.concealer
	end
	return function(lnode, source, state)
		local narg_res = lnode:field("arg")
		if narg and #narg_res ~= narg then
			return M.fallback_concealer(lnode, source, state)
		end
		if prev then
			state:addUndoPoint()
			prev(state)
		end
		local arg_res = {}
		if default then
			local oarg_res = lnode:field("optional_arg")[1] or default
			if type(oarg_res) ~= "boolean" then
				oarg_res = M.conceal_arg_without_bracket(oarg_res, source, state)
				table.insert(arg_res, oarg_res)
			end
		end
		local shift = default and 1 or 0
		for index, value in ipairs(narg_res) do
			table.insert(arg_res, index + shift, M.conceal_arg_without_bracket(value, source, state))
		end
		if prev then
			state:undo()
		end
		return fn(arg_res, state)
	end
end

---@type Nvimtex.concealer
local frac = concealer.create_command_concealer({
	prev = function(state)
		state:set("delim", state:get("delim") + 1)
	end,
	concealer = function(args, state)
		local delim_deepth = state:get("delim")
		local up = args[1]
		local down = args[2]
		local super = up:style(mathstyle.superscript, true)
		local sub = down:style(mathstyle.subscript, true)
		if super and sub then
			return super:append({ "/", hl.rainbow(delim_deepth) }, sub)
		else
			return inline
				:new({ "(", hl.rainbow(delim_deepth) })
				:append(up, { ")/(", hl.rainbow(delim_deepth) }, down, { ")", hl.rainbow(delim_deepth) })
		end
	end,
}, 2)
function M.setup(opts) end

M.map = {
	generic_command = {
		["not"] = concealer.style(function(char)
			return char .. "̸"
		end),
		["mathbb"] = concealer.style(mathstyle.mathbb, hl.symbol),
		["mathcal"] = concealer.style(mathstyle.mathcal, hl.symbol),
		["mathbbm"] = concealer.style(mathstyle.mathbbm, hl.symbol),
		["mathfrak"] = concealer.style(mathstyle.mathfrak, hl.symbol),
		["mathscr"] = concealer.style(mathstyle.mathscr, hl.symbol),
		["mathsf"] = concealer.style(mathstyle.mathsf, hl.symbol),
		mathrm = concealer.style(nil, hl.constant),
		operatorname = concealer.style(nil, hl.constant),
		["'"] = concealer.style("́"),
		['"'] = concealer.style("̈"),
		["`"] = concealer.style("̀"),
		["="] = concealer.style("̄"),
		["~"] = concealer.style("̃"),
		["."] = concealer.style("̇"),
		["^"] = concealer.style("̂"),
		tilde = concealer.style("̂"),
		overline = concealer.style("̅"),
		bar = concealer.style("̅"),
		["frac"] = frac,
		["dfrac"] = frac,
		["tfrac"] = frac,
		["norm"] = concealer.delim("‖", "‖"),
		["abs"] = concealer.delim("|", "|"),
		["binom"] = concealer.delim("(", "C", ")"),

		sqrt = concealer.create_command_concealer({
			prev = function(state)
				state:set("delim", state:get("delim") + 1)
			end,
			---@param args Nvimtex.Inline[]
			concealer = function(args, state)
				local delim_hl = hl.rainbow(state:get("delim"))
				local arg_hl = args[2]:first_hl()
				local flag = args[2].width <= 1
				local res
				if args[1] then
					res = args[1]:style(mathstyle.superscript, true, flag and arg_hl or delim_hl)
					res = res and res:append({ "√", arg_hl })
						or inline:new({ "(", delim_hl }):append(args[0], { ")√", delim_hl })
				else
					res = inline:new({ "√", flag and arg_hl or delim_hl }, false)
				end
				if flag then
					return res:append(args[2]:style(mathstyle.overline, false))
				else
					return res:append({ "(", delim_hl }, args[1], { ")", delim_hl })
				end
			end,
		}, 1, true),
	},
	command_name = require("nvimtex.conceal.command_name"),
}
M.concealer = {
	command_name = function(lnode, source, state)
		local command_name = vim.treesitter.get_node_text(lnode, source):sub(2, -1)
		local text = M.map.command_name[command_name]
		if text then
			return inline:new(text)
		end
		return inline:new(source, lnode)
	end,
	generic_command = function(lnode, source, state)
		local command_node = lnode:field("command")[1]
		local command_name = vim.treesitter.get_node_text(command_node, source):sub(2, -1)
		local c = M.map.generic_command[command_name]
		if c then
			return M.conceal_node_with_state(lnode, source, state, c)
		end
		local text = M.map.command_name[command_name]
		if text then
			return inline:new(text)
		end
		return M.conceal_node_with_state(lnode, source, state, M.fallback_concealer)
	end,
	subscript = concealer.script("_", mathstyle.subscript, hl.script),
	superscript = concealer.script("^", mathstyle.superscript, hl.script),
	word = function(lnode, source, state)
		local text = vim.treesitter.get_node_text(lnode, source)
		if tonumber(text) then
			return inline:new({ text, hl.constant })
		else
			return inline:new({ text, hl.default })
		end
	end,
	["\\("] = function()
		return inline:new({ "$", hl.constant })
	end,
	["\\)"] = function()
		return inline:new({ "$", hl.constant })
	end,
	["\\["] = function()
		return inline:new({ "$$", hl.constant })
	end,
	["\\]"] = function()
		return inline:new({ "$$", hl.constant })
	end,
	placeholder = function(lnode, source, state)
		local text = vim.treesitter.get_node_text(lnode, source)
		local number = tonumber(text:match("#*(%d*)"))
		local placeholder = state:get("placeholder")[number]
		return placeholder or inline:new({ text, hl.error })
	end,
}
function M.conceal(lnode, source)
	local state = State:new()
	if not lnode then
		lnode = require("nvimtex.conditions.luasnip").in_math()
		if not lnode then
			error("no node to conceal")
		end
	end
	if not source then
		source = vim.api.nvim_win_get_buf(0)
	end
	local virt_text = M.default_concealer(lnode, source, state)
	M.show(virt_text)
end

---@param inline_conceal Nvimtex.Inline
function M.show(inline_conceal)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 5,
		col = 10,
		width = inline_conceal.width,
		height = 2,
		style = "minimal",
		border = "rounded",
	})
	vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("nvimtex"), 0, 0, {
		virt_lines = { inline_conceal.data },
	})
	vim.keymap.set("n", "q", ":q<cr>", { buffer = buf, remap = false })
end

--- expand a command definition
---@param inode Nvimtex.LNode
---@return Nvimtex.concealer
function M.expand(inode, source, narg, default)
	return M.create_command_concealer(function(args, state)
		state:set("placeholder", args)
		return M.default_concealer(inode, source, state)
	end, narg, default)
end

return M
