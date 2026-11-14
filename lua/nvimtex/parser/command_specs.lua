local LNode = require("nvimtex.parser.lnode")

local M = {}

---@param ctx Nvimtex.Parser.Context
---@param node Nvimtex.LNode
---@return Nvimtex.LNode
local function parse_verb(ctx, node)
	local result = LNode:new(node)
	local delimiter = ctx:read_char()
	if not delimiter then
		result:set_end()
		return result
	end

	local group = ctx:make_node("verb_group")
	group:add_child(delimiter)
	group:set_start(delimiter)

	local content, close = ctx:read_until_char(ctx:node_text(delimiter))
	group:add_child(content)
	if close then
		group:add_child(close)
		group:set_end(close)
	else
		group:set_end(content)
	end

	result:add_child(group)
	result:set_end(group)
	return result
end

M["not"] = { narg = 1 }
M["'"] = { narg = 1 }
M['"'] = { narg = 1 }
M["`"] = { narg = 1 }
M["="] = { narg = 1 }
M["~"] = { narg = 1 }
M["."] = { narg = 1 }
M["^"] = { narg = 1 }

M.frac = { narg = 2 }
M.dfrac = { narg = 2 }
M.tfrac = { narg = 2 }
M.bar = { narg = 1 }
M.tilde = { narg = 1 }
M.norm = { narg = 1 }
M.abs = { narg = 1 }
M.sqrt = { oarg = true, narg = 1 }
M.mathbb = { narg = 1 }
M.mathsrc = { narg = 1 }
M.mathfrak = { narg = 1 }
M.mathrm = { narg = 1 }
M.mathbbm = { narg = 1 }
M.verb = { parse = parse_verb }
M["verb*"] = { parse = parse_verb }

return M
