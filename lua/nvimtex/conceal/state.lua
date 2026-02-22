---@class Nvimtex.State
---@field data table
---@field changeLog table[]
---@field changeHis table[]
local M = {}
local private_data = {}
local initial_data = { delim = 0, placeholder = {}, parser_command_definition = false }
M.__index = M
---@return Nvimtex.State
function M:new(t)
	local res = {}
	res[private_data] = t and vim.deepcopy(t) or { delim = 0 }
	res.changeLog = {}
	res.changeHis = { res.changeLog }
	return setmetatable(res, M)
end

function M:addUndoPoint()
	self.changeLog = {}
	table.insert(self.changeHis, self.changeLog)
end

function M:undo()
	local changeLog = table.remove(self.changeHis)
	for key, value in pairs(changeLog) do
		self[private_data][key] = value
	end
	self.changeLog = self.changeHis[#self.changeHis]
end

function M:get(key)
	return self[private_data][key]
end

function M:set(key, value)
	self.changeLog[key] = self.changeLog[key] or self[private_data][key]
	self[private_data][key] = value
end

function M:setglobal(key, value)
	self[private_data][key] = value
end

--\(\frac{1}{\frac{2}{3}}\)

return M
