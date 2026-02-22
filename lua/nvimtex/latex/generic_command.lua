---@class Nvimtex.generic_command.spec
---@field narg number?
---@field oarg boolean?
---@field consumer Nvimtex.Consumer
---@field concealer function|table<string,function>

local M = {}
---@type table<string,Nvimtex.generic_command.spec>
M.spec = {}

return M
