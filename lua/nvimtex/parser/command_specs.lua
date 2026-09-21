local LNode = require("nvimtex.parser.lnode")

local M = {}

---@param ctx Nvimtex.Parser.Context
---@param node Nvimtex.LNode
---@param field string?
---@return Nvimtex.LNode, string?
local function parse_verb(ctx, node, field)
	local result = LNode:new(node)
	local delimiter = ctx:read_char()
	if not delimiter then
		result:set_end()
		return result, field
	end

	local group = ctx:make_node("verb_group")
	group:add_child(delimiter, "open")
	group:set_start(delimiter)

	local content, close = ctx:read_until_char(ctx:node_text(delimiter))
	group:add_child(content, "content")
	if close then
		group:add_child(close, "close")
		group:set_end(close)
	else
		group:set_end(content)
	end

	result:add_child(group, "arg")
	result:set_end(group)
	return result, field
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
