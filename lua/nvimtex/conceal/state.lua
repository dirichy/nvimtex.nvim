---@class Nvimtex.State
---@field data table
---@field changeLog table[]
---@field changeHis table[]
local M = {}
local private_data = {}
local nil_value = {}
local initial_data =
	{ delim = 0, placeholder = {}, parser_command_definition = false, conceal = true, preamble = false }
M.__index = M
---@return Nvimtex.State
function M:new(t)
	local res = {}
	res[private_data] = vim.deepcopy(t or initial_data)
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
		if value == nil_value then
			self[private_data][key] = nil
		else
			self[private_data][key] = value
		end
	end
	self.changeLog = self.changeHis[#self.changeHis]
end

function M:get(key)
	return self[private_data][key]
end

function M:set(key, value)
	if self.changeLog[key] == nil then
		local old_value = self[private_data][key]
		self.changeLog[key] = old_value == nil and nil_value or old_value
	end
	self[private_data][key] = value
end

function M:setglobal(key, value)
	self[private_data][key] = value
end

--\(\frac{1}{\frac{2}{3}}\)

return M
