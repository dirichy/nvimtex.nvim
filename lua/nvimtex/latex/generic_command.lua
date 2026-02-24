local mathstyle = require("nvimtex.latex.mathstyle")
local hl = require("nvimtex.highlight")
---@class Nvimtex.generic_command.concealer.table
---@field prev? fun(state:Nvimtex.State)
---@field concealer? fun(args:Nvimtex.Inline[],state:Nvimtex.State):Nvimtex.Inline
---@field rawconcealer? Nvimtex.concealer
---@field style? {[1]:(table<string,string>|fun(char:string):string?)|string,[2]:string|string[]|nil}
---@field delim? string[]
---@alias Nvimtex.generic_command.concealer Nvimtex.generic_command.concealer.table | fun(args:Nvimtex.Inline[],state:Nvimtex.State):Nvimtex.Inline
---@class Nvimtex.generic_command.spec
---@field narg? number?
---@field oarg? boolean?
---@field consumer? fun(lnode:Nvimtex.LNode,source:number|string,state:Nvimtex.State):Nvimtex.Consumer
---@field concealer? Nvimtex.generic_command.concealer

local M = {}
---@param map (table<string,string>|fun(char:string):string?)|string
---@param highlight string|string[]|nil}
function M.style(map, highlight)
	return { narg = 1, concealer = { style = { map, highlight } } }
end
---@vararg string
function M.delim(...)
	local delims = { ... }
	return { narg = #delims - 1, concealer = { delim = { ... } } }
end
---@type table<string,Nvimtex.generic_command.spec>
M.spec = {
	["'"] = M.style("́", hl.default),
	['"'] = M.style("̈", hl.default),
	["`"] = M.style("̀", hl.default),
	["="] = M.style("̄", hl.default),
	["~"] = M.style("̃", hl.default),
	["."] = M.style("̇", hl.default),
	["^"] = M.style("̂", hl.default),
}

return M
