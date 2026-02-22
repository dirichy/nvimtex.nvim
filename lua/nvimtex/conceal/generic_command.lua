local highlight = require("nvimtex.highlight")
local concealer = require("nvimtex.conceal.util")
local style = require("nvimtex.latex.mathstyle")
local processor = require("nvimtex.conceal.processor")
local inline = require("nvimtex.conceal.inline")
local LNode = require("nvimtex.parser.lnode")
local subscript_tbl = style.subscript
local superscript_tbl = style.superscript
---@param node LNode
---@param buffer number|string
---@param state Nvimtex.State
local function frac(node, buffer, state)
	local delim_deepth = state:get("delim")
	state:set("delim", delim_deepth + 1)
	local arg_nodes = node:field("arg")
	local up = LNode.remove_bracket(arg_nodes[1])
	local down = LNode.remove_bracket(arg_nodes[2])
	up = processor.default_processor(up, buffer, state)
	down = processor.default_processor(down, buffer, state)
	local super = up:style(superscript_tbl, true)
	local sub = up:style(subscript_tbl, true)
	if super and sub then
		return super:append(inline:new({ "/", highlight.rainbow[delim_deepth % 4] }), sub)
	else
		return inline:new({ "(", highlight.rainbow[delim_deepth % 4] }):append(
			up,
			inline:new({ ")/(", highlight.rainbow[delim_deepth % 4] }),
			down,
			inline:new({ ")", highlight.rainbow[delim_deepth % 4] })
		)
	end
end
---@param buffer integer
---@param node Nvimtex.LNode
---@param opts table
local function overline(buffer, node, opts)
	local arg = LNode:new(node:field("arg")[1])
	if not arg then
		return
	end
	arg = concealer.node2grid(buffer, arg:remove_bracket())
	if arg.height == 1 and arg.width == 1 then
		return concealer.modify_next_char("̅", {})
	end
	local pss = concealer.delim({ "‾", highlight.delim }, { "‾", highlight.delim })
	pss.grid = function(buf, lnode)
		return Grid:new({ string.rep("_", arg.width), arg.data[1][1][2] }) - arg
	end
	return pss
end

local function tilde(buffer, node, opts)
	local arg = LNode:new(node:field("arg")[1])
	if not arg then
		return
	end
	arg = concealer.node2grid(buffer, arg:remove_bracket())
	if arg.height == 1 and arg.width == 1 then
		return concealer.modify_next_char("̃", "MathZone")
	end
	local pss = concealer.delim({ "˜", highlight.delim }, { "˜", highlight.delim })
	if arg.width == 2 then
		pss.grid = function(buf, lnode)
			return Grid:new({ "⏜𛰜", arg.data[1][1][2] }) - arg
			--𛰐--𛰛𛰜⏜⏝𛰩𛰪
		end
	elseif arg.width == 1 then
		pss.grid = function(buf, lnode)
			return Grid:new({ "˜", arg.data[1][1][2] }) - arg
		end
	else
		pss.grid = function(buf, lnode)
			local line = arg.width - 3
			local over = math.ceil(line / 2)
			local under = line - over
			return Grid:new({
				"/" .. string.rep("‾", over) .. "\\" .. string.rep("_", under) .. "/",
				arg.data[1][1][2],
			}) - arg
		end
	end
	return pss
end
---@type table<string,function|LaTeX.Processor>
return {
	["verb"] = {
		parser = function(buffer, node, opts)
			local field = opts.field
			local lnode = LNode:new("generic_command")
			lnode:add_child(node:field("command")[1], "command")
			lnode:set_range(node)
			local arg_node = LNode:new("verb_group")
			local open = nil
			---@param nodee Nvimtex.LNode?
			---@param fieldd string
			---@return Nvimtex.LNode|Nvimtex.LNode[]|nil if return nil, then this node is not finished, so we need to continue parse.
			---If return Lnode or LNode[], then this node is finished.
			return function(nodee, fieldd)
				if not nodee then
					return { { lnode, field } }
				end
				if not open then
					if nodee:type() == "word" then
						nodee = LNode:new(nodee)
						nodee._type = "char"
						local a, b, x = nodee:start()
						nodee:set_end(a, b + 1, x + 1)
					end
					open = vim.treesitter.get_node_text(nodee, buffer)
					if #open > 1 then
						return { { nodee, fieldd }, { lnode, field } }
					end
					arg_node:add_child(nodee, "open")
					arg_node:set_start(nodee)
					lnode:add_child(arg_node, "arg")
					return
				end
				local i = string.find(vim.treesitter.get_node_text(nodee, buffer), open, nil, true)
				local wordnode
				if nodee:type() == "word" and i then
					local a, b, x, c, d, y = nodee:range(true)
					if x + i < y then
						wordnode = LNode:new(nodee)
						wordnode:set_start(a, b + i, x + i)
					end
					nodee = LNode:new("char")
					nodee:set_range(a, b + i - 1, x + i - 1, a, b + i, x + i)
				end
				if open == vim.treesitter.get_node_text(nodee, buffer) then
					arg_node:add_child(nodee, "close")
					arg_node:set_end(nodee)
					lnode:set_end(nodee)
					local a, b, x = arg_node:start()
					local c, d, y = arg_node:end_()
					local verb_inner = LNode:new("verb_inner")
					verb_inner:set_range(a, b + 1, x + 1, c, d - 1, y - 1)
					if wordnode then
						return { { wordnode, fieldd }, { lnode, field } }
					end
					return { { lnode, field } }
				end
			end
		end,
	},
	["not"] = concealer.modify_next_char("̸", highlight.relationship, false),
	["'"] = concealer.modify_next_char("́", highlight.default, false),
	['"'] = concealer.modify_next_char("̈", highlight.default, false),
	["`"] = concealer.modify_next_char("̀", highlight.default, false),
	["="] = concealer.modify_next_char("̄", highlight.default, false),
	["~"] = concealer.modify_next_char("̃", highlight.default, false),
	["."] = concealer.modify_next_char("̇", highlight.default, false),
	["^"] = concealer.modify_next_char("̂", highlight.default, false),
	--command_delim
	["frac"] = { processor = frac, narg = 2 },
	["dfrac"] = { processor = frac, narg = 2 },
	["tfrac"] = { processor = frac, narg = 2 },
	["bar"] = overline,
	["overline"] = overline,
	["tilde"] = tilde,
	["norm"] = concealer.delim("‖", "‖"),
	["abs"] = concealer.delim("|", "|"),
	["binom"] = concealer.delim("(", "C", ")"),
	["sqrt"] = {
		oarg = true,
		narg = 2,
		processor = function(buffer, node)
			local optional_arg = node:field("optional_arg")[1]
			if optional_arg then
				local up_number = vim.treesitter.get_node_text(optional_arg, buffer):sub(2, -2)
				if up_number:match("^[-]?[0-9-]*$") then
					up_number = string.gsub(up_number, ".", superscript_tbl)
					return concealer.delim(up_number .. "√(", ")", false)
				end
				return concealer.delim({ "(", highlight.delim }, { ")√(", highlight.delim }, { ")", highlight.delim })
			else
				return concealer.delim({ "√(", highlight.delim }, { ")", highlight.delim })
			end
		end,
		--   ___________
		--  ⎛
		--  ⎜
		--  ⎜
		--  ⎜
		--  ⎜
		-- √
		grid = function(buffer, node)
			local oarg = node:field("optional_arg")[1]
			local arg = node:field("arg")[1]
			arg = concealer.node2grid(buffer, LNode.remove_bracket(arg))
			local hi = arg.data[1][1][2]
			if arg.height == 1 then
				if arg.width == 1 then
					arg.data[1][1] = { "√" .. arg.data[1][1][1] .. "̅", arg.data[1][1][2] }
					arg.width = arg.width + 1
				else
					arg = Grid:new({ string.rep("_", arg.width), hi }) - arg
					arg = Grid:new({ "√", hi }) + arg
				end
			else
				arg = Grid:new({ string.rep("_", arg.width), hi }) - arg
				arg.center = math.ceil(arg.height / 2) + 1
				local data = { { { "  ", hi } }, { { " ⎛", hi } } }
				for _ = 3, arg.height - 1 do
					table.insert(data, { { " ⎜", hi } })
				end
				table.insert(data, { { "√ ", hi } })
				local sqrt = Grid:new(data)
				sqrt.center = arg.center
				arg = sqrt + arg
			end
			if oarg then
				oarg = concealer.node2grid(buffer, LNode.remove_bracket(oarg))
				if oarg.height == 1 and arg.height == 1 then
					local ss = Grid:new(oarg)
					local flag = true
					for index, value in ipairs(oarg.data[1]) do
						local s = string.gsub(value[1], ".", function(str)
							if style.superscript[str] then
								return style.superscript[str]
							else
								flag = false
								return str
							end
						end)
						if not flag then
							break
						end
						ss.data[1][index][1] = s
					end
					if flag then
						arg = ss + arg
						return arg
					end
				end
				oarg.center = arg.center + 1
				arg = oarg + arg
			end
			return arg
		end,
	},
	--fonts
	["mathbb"] = concealer.font(style.mathbb, highlight.symbol),
	["mathcal"] = concealer.font(style.mathcal, highlight.symbol),
	["mathbbm"] = concealer.font(style.mathbbm, highlight.symbol),
	["mathfrak"] = concealer.font(style.mathfrak, highlight.symbol),
	["mathscr"] = concealer.font(style.mathscr, highlight.symbol),
	["mathsf"] = concealer.font(style.mathsf, highlight.symbol),
	["operatorname"] = concealer.font(function(str)
		return str
	end, highlight.operatorname),
	["mathrm"] = concealer.font(function(str)
		return str
	end, highlight.constant),
	--other
	["footnote"] = function(buffer, node)
		counter.step_counter(buffer, "footnote")
		local arg_nodes = node:field("arg")
		if #arg_nodes < 2 then
			return
		end
		local a, b = node:range()
		local _, _, c, d = arg_nodes[1]:range()
		d = d + 1
		extmark.multichar_conceal(buffer, { a, b, c, d }, { counter.the(buffer, "footnote"), highlight.footnotemark })
		_, _, a, b = arg_nodes[2]:range()
		extmark.multichar_conceal(buffer, { a, b - 1, a, b }, "")
	end,
}
