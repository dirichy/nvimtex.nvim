local LNode = require("nvimtex.parser.lnode")
local generic_command = require("nvimtex.parser.generic_command")
local Consumer = require("nvimtex.parser.consumer")
---@class Nvimtex.LNode.withfield
---@field [1] Nvimtex.LNode
---@field [2] string|nil
---@class Nvimtex.Consumer.result.residual
---@field finish Nvimtex.LNode.withfield
---@field residual Nvimtex.LNode.withfield[]
---@class Nvimtex.Parser
---@field stack Nvimtex.Consumer[]
---@field nodestack (Nvimtex.LNode.withfield|fun():Nvimtex.LNode,string)[]
local M = {}
M.__index = M
---@param consumer Nvimtex.Consumer[]|Nvimtex.Consumer|nil
---@return Nvimtex.Parser
function M:new(consumer)
	local res = {}
	consumer = consumer or {}
	if type(consumer) ~= "table" then
		consumer = { consumer }
	end
	res.stack = consumer
	res.nodestack = {}
	setmetatable(res, M)
	return res
end

--- add a consumer
---@param consumer Nvimtex.Consumer
function M:push_consumer(consumer)
	table.insert(self.stack, consumer)
end
--- remove a consumer
---@return Nvimtex.Consumer
function M:pop_consumer()
	return table.remove(self.stack)
end
--- feed a lnode
---@param lnode Nvimtex.LNode
---@param source number|string
function M:feed_to_consumer(lnode, field, source)
	local consumer = self.stack[#self.stack]
	if not consumer then
		return Consumer.feedback.finish, { lnode, field }
	end
	local feedback, res = consumer(lnode, field, source)
	while feedback == Consumer.feedback.finish or feedback == Consumer.feedback.residual do
		self:pop_consumer()
		if feedback == Consumer.feedback.finish then
			---@type Nvimtex.LNode
			lnode, field = unpack(res)
		else
			---@type Nvimtex.LNode
			lnode, field = unpack(res.finish)
			for i = #res.residual, 1, -1 do
				table.insert(self.nodestack, res.residual[i])
			end
		end
		consumer = self.stack[#self.stack]
		if not consumer then
			return Consumer.feedback.finish, { lnode, field }
		end
		feedback, res = consumer(lnode, field, source)
	end
	if feedback == Consumer.feedback.subconsumer then
		self:push_consumer(res)
		return Consumer.feedback.continue, nil
	end
	if feedback == Consumer.feedback.continue then
		return feedback, nil
	end
	error("unknown return value of consumer: " .. feedback)
end
--- Used in consumer:feed, get next unconsumed node in nodestack
---@return Nvimtex.LNode|nil,string|nil
function M:next_unconsumed_node()
	local node = self.nodestack[#self.nodestack]
	while type(node) == "function" do
		local n, f = node()
		if n then
			return n, f
		else
			table.remove(self.nodestack)
			node = self.nodestack[#self.nodestack]
		end
	end
	if not node then
		return nil
	end
	return unpack(table.remove(self.nodestack))
end

---@type Nvimtex.Parser[]
local pool = {}
--- return a iter of lnode's children
---@param lnode Nvimtex.LNode
---@param source number|string
function M.iter_children(lnode, source)
	---@type Nvimtex.Parser
	local parser = table.remove(pool) or M:new()
	table.insert(parser.nodestack, lnode:iter_children())
	---@type fun():Nvimtex.LNode?,string?
	return function()
		local n, f, c, feedback, res
		repeat
			repeat
				n, f = parser:next_unconsumed_node()
				if n then
					local ntype = n:type()
					if ntype == "text" then
						table.insert(parser.nodestack, n:iter_children())
						n, f = parser:next_unconsumed_node()
					end
					c = parser:get_consumer(n, source)
					if c then
						if type(c) == "function" then
							parser:push_consumer(c)
						end
						if type(c) == "table" then
							n, f = c[1], c[2]
							c = nil
						end
					end
				else
					c = nil
				end
			until not c
			feedback, res = parser:feed_to_consumer(n, f, source)
		until feedback == Consumer.feedback.finish
		return res[1], res[2]
	end
end

function M:sexpr(lnode, field, source, result, range_comment)
	local root = false
	if not result then
		root = true
	end
	result = result or {}
	range_comment = range_comment or {}
	table.insert(result, (field and field .. ": " or "") .. "(" .. lnode:type())
	local a, b, c, d = lnode:range()
	table.insert(range_comment, " ; [" .. a .. ", " .. b .. "] - [" .. c .. ", " .. d .. "]")
	for n, f in M.iter_children(lnode, source) do
		self:sexpr(n, f, source, result, range_comment)
	end
	result[#result] = result[#result] .. ")"
	if root then
		for index, value in ipairs(range_comment) do
			result[index] = result[index] .. value
		end
		return table.concat(result, "\n")
	end
end
--- get consumer of a node
---@param lnode Nvimtex.LNode
---@param source number|string
---@return Nvimtex.Consumer?
function M:get_consumer(lnode, source)
	if lnode:type() == "generic_command" then
		local command_name = vim.treesitter.get_node_text(lnode:child(0), source):sub(2, -1)
		local arg_table = generic_command[command_name]
		if arg_table then
			local feedback, res = Consumer.generic_command(lnode, arg_table.oarg, arg_table.narg)
			if feedback == Consumer.creater_feedback.success then
				return res
			end
			if feedback == Consumer.creater_feedback.noneed then
				return nil
			end
			if feedback == Consumer.creater_feedback.residual then
				table.insert(self.nodestack, res.residual)
				return res.finish
			end
		end
	end
end

---@param root Nvimtex.LNode
---@param source number
---@param a integer
---@param b integer
---@param c integer
---@param d integer
---@return Nvimtex.LNode[]
---@overload fun(root:Nvimtex.LNode,source:number,a:number):Nvimtex.LNode[]
---@overload fun(root:Nvimtex.LNode,source:number,a:number,b:number):Nvimtex.LNode[]
function M.descendants_node_covering_range(root, source, a, b, c, d)
	if not b then
		local cursor = vim.api.nvim_win_get_cursor(a or 0)
		a, b = cursor[1] - 1, cursor[2]
	end
	if not d then
		c, d = a, b + 1
	end
	local res = {}
	local flag = LNode.contains(root, a, b, c, d)
	while flag do
		flag = false
		table.insert(res, root)
		for n in M.iter_children(root, source) do
			if LNode.contains(n, a, b, c, d) then
				root = n
				flag = true
				break
			end
		end
	end
	return res
end

function M:test()
	local parser = M:new()
	local node = require("nvimtex.conditions.luasnip").in_math()
	print(parser:sexpr(node, nil, vim.api.nvim_win_get_buf(0)))
	-- local iter = parser:iter_children(node, vim.api.nvim_win_get_buf(0))
	-- for n, f in iter do
	-- 	local a, b, c, d = n:range()
	-- 	print(n:type(), a, b, c, d, f)
	-- end
end

return M
