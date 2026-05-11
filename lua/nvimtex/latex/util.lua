local M = {}
local t = {
	["neq"] = true,
	["leq"] = true,
	["geq"] = true,
}
M.relation_operator = {
	["="] = true,
	["<"] = true,
	[">"] = true,
	["neq"] = true,
	["leq"] = true,
	["geq"] = true,
	generic_command = function(name)
		return t[name]
	end,
}
return M
